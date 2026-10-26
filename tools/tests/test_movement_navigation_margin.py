"""Margin revisions cannot erase holdout exposure or replace actual support."""

import copy
import json
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_navigation_ingress as fixtures
from build_native_route_study import read, sha
from navigation_ingress_margin import (
    MINIMUM_SECONDS,
    margin_gate,
    margin_score,
    policy_payload,
    selection,
)


class NavigationMarginTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.NavigationIngressTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.previous, self.directory = self.root / "r15", self.root / "r16"
        self.previous.mkdir()
        self.directory.mkdir()
        grid = self.fixture.build()
        self.grid = grid
        self.points = {p["id"]: p for p in grid["cases"]}
        variant = grid["cases"][0]["variant"]
        old = dict(
            grid,
            stage="navigation_ingress_selected60_before_holdout",
            cases=[p for p in grid["cases"] if p["variant"] == variant],
        )
        self.write(self.previous / "grid-v1.json", grid)
        self.write(
            self.previous / "grid-60.json",
            dict(results=[dict(id=k) for k in self.points]),
        )
        self.write(self.previous / "selected-v1.json", old)
        self.write(
            self.previous / "selection-lock.json",
            {"selected_sha256": sha(self.previous / "selected-v1.json")},
        )
        self.write(self.directory / "policy-v1.json", policy_payload(self.previous))

    def write(self, path, value):
        path.write_text(json.dumps(value))

    def margin_fixture(
        self, rate=60, margin=MINIMUM_SECONDS
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        point, _ = self.fixture.approach_fixture()
        checkpoint = round(0.1 * rate)
        end = checkpoint + round(margin * rate)
        row = dict(
            trace=[
                dict(
                    time=i / rate,
                    input=dict(jump=i == end),
                    position=[0, 0.9, 1.2 if i < checkpoint else 0],
                    grounded_after=i != end,
                    grounded_before=True,
                    jumped=i == end,
                )
                for i in range(end + 1)
            ]
        )
        return point, row

    def test_fixed_seconds_policy_binds_previous_receipts_and_exposure(self):
        policy = policy_payload(self.previous)
        self.assertEqual(policy["minimum_grounded_margin_seconds"], 0.05)
        self.assertEqual(policy["minimum_reference_ticks"], 3)
        self.assertEqual(policy["reference_hz"], 60)
        self.assertEqual(len(policy["previously_exposed_cases"]), 9)
        self.assertEqual(len(policy["source_evidence_sha256"]), 4)
        self.assertFalse(policy["formal_qualification"])

    def test_exact_seconds_boundary_at_both_physics_rates(self):
        for rate in (60, 120):
            point, row = self.margin_fixture(rate)
            before = copy.deepcopy(row)
            result = margin_gate(point, row)
            self.assertTrue(result["passed"])
            self.assertAlmostEqual(result["seconds"], 0.05)
            self.assertEqual(row, before)

    def test_one_physics_sample_short_is_rejected(self):
        for rate in (60, 120):
            point, row = self.margin_fixture(rate, MINIMUM_SECONDS - 1 / rate)
            self.assertEqual(margin_gate(point, row)["reason"], "insufficient_margin")

    def test_lost_support_between_checkpoint_and_jump_is_rejected(self):
        point, row = self.margin_fixture()
        row["trace"][-2]["grounded_after"] = False
        self.assertEqual(margin_gate(point, row)["reason"], "lost_support")

    def test_unsupported_or_missing_takeoff_cannot_gain_margin(self):
        for field in ("jumped", "grounded_before"):
            point, row = self.margin_fixture()
            row["trace"][-1][field] = False
            self.assertEqual(margin_gate(point, row)["reason"], "lost_support")
        point, row = self.margin_fixture()
        row["trace"][-1]["input"]["jump"] = False
        self.assertEqual(margin_gate(point, row)["reason"], "not_single_takeoff")

    def test_checkpoint_on_jump_sample_is_still_unproven(self):
        point, row = self.margin_fixture()
        for sample in row["trace"][:-1]:
            sample["position"][2] = 1.2
        self.assertEqual(margin_gate(point, row)["reason"], "approach_unproven")

    def test_ingress_and_margin_are_both_required(self):
        for base, margin in ((True, False), (False, True)):
            with (
                patch(
                    "navigation_ingress_margin.score", return_value=dict(passed=base)
                ),
                patch(
                    "navigation_ingress_margin.margin_gate",
                    return_value=dict(passed=margin),
                ),
            ):
                self.assertFalse(margin_score({}, {}, 60)["passed"])

    def select_fixture(self):
        with (
            patch(
                "navigation_ingress_margin.checked",
                return_value=(self.points, {k: {} for k in self.points}),
            ),
            patch(
                "navigation_ingress_margin.margin_score", return_value=dict(passed=True)
            ),
            patch(
                "navigation_ingress_margin.outcomes",
                return_value=dict(supported_arrival=False),
            ),
        ):
            return selection(self.directory, self.previous, self.root)

    def test_exposed_input_is_excluded_even_if_new_gate_says_pass(self):
        policy = read(self.directory / "policy-v1.json")
        result = self.select_fixture()
        self.assertEqual(len(result["cases"]), 9)
        self.assertFalse(
            set(policy["previously_exposed_cases"]).intersection(
                p["id"] for p in result["cases"]
            )
        )
        self.assertFalse(result["previous_holdout_results_replaced"])

    def test_selection_does_not_read_any_120hz_report(self):
        def guarded(path):
            self.assertNotIn("120", path.name)
            return read(path)

        with patch("navigation_ingress_margin.read", side_effect=guarded):
            self.select_fixture()

    def test_policy_or_source_change_is_rejected_before_selection(self):
        path = self.directory / "policy-v1.json"
        policy = read(path)
        policy["minimum_grounded_margin_seconds"] = 0.01
        self.write(path, policy)
        with self.assertRaisesRegex(ValueError, "policy or source changed"):
            self.select_fixture()
        self.write(path, policy_payload(self.previous))
        with (self.previous / "grid-60.json").open("a") as output:
            output.write(" ")
        with self.assertRaisesRegex(ValueError, "policy or source changed"):
            self.select_fixture()

    def test_prior_selection_lock_drift_is_rejected(self):
        self.write(
            self.previous / "selection-lock.json", dict(selected_sha256="changed")
        )
        with self.assertRaisesRegex(ValueError, "prior selection lock changed"):
            policy_payload(self.previous)

    def test_duplicate_prior_holdout_cannot_hide_exposure(self):
        path = self.previous / "selected-v1.json"
        selected = read(path)
        selected["cases"][-1] = selected["cases"][0]
        self.write(path, selected)
        self.write(
            self.previous / "selection-lock.json", dict(selected_sha256=sha(path))
        )
        with self.assertRaisesRegex(ValueError, "prior holdout cohort changed"):
            policy_payload(self.previous)

    def test_live_probe_drift_cannot_reuse_old_60hz_measurements(self):
        (self.root / fixtures.PROBE).write_text("changed")
        with self.assertRaisesRegex(ValueError, "live author probe drift"):
            self.select_fixture()


if __name__ == "__main__":
    unittest.main()
