"""Ingress must reverse onto the exact surface and finish supported, not just pass it."""

import json
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_surface_edges as fixtures
from surface_ingress_study import (
    PROBE,
    grid_payload,
    initial_jump_rejection,
    qualify,
    selection,
    timeline,
)


class SurfaceIngressTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.SurfaceEdgeTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        source = self.fixture.build()
        source["stage"] = "selected_current60_before_holdout"
        self.source = self.root / "selected-surface.json"
        self.source.write_text(json.dumps(source))
        (self.root / PROBE).write_text("fixture ingress")

    def build(self):
        return grid_payload(self.source, self.root, self.root / "reject.json")

    def test_complete_frozen_profile_variant_controls(self):
        result = self.build()
        self.assertEqual(len(result["cases"]), 108)
        self.assertEqual(len({p["id"] for p in result["cases"]}), 108)
        self.assertEqual(
            {p["scheme"] for p in result["cases"]},
            {"current", "legacy_16", "modern_cs"},
        )
        self.assertFalse(result["formal_qualification"])

    def test_lower_floor_start_and_exact_upper_goal_preserved(self):
        original = json.loads(self.source.read_text())["cases"][0]
        before = self.source.read_bytes()
        for p in self.build()["cases"]:
            self.assertEqual(p["target_feet"], original["geometry"]["feet"])
            floor = original["target_feet"]
            self.assertEqual(p["start"], [floor[0], floor[1] + 0.91, floor[2]])
            self.assertEqual(p["target_radius"], 0.35)
            self.assertEqual(p["target_height_tolerance"], 0.18)
            self.assertIn("res://" + PROBE, p["probe_sha256"])
        self.assertEqual(before, self.source.read_bytes())

    def test_controls_remove_only_jump_and_walk_adds_shift(self):
        points = self.build()["cases"]
        for p in points:
            if p["trial_mode"] != "jump":
                self.assertFalse(
                    any("Space" in e["keys"] for e in p["native_timeline"])
                )
            if p["trial_mode"] == "walk":
                self.assertTrue(all("Shift" in e["keys"] for e in p["native_timeline"]))

    def test_air_crouch_and_key_release_are_frozen_in_time(self):
        events = timeline(0.1, 0.3, True)
        self.assertEqual(events[2]["keys"], ["W", "Ctrl"])
        self.assertAlmostEqual(events[2]["at"], 0.15)
        self.assertAlmostEqual(events[-1]["at"], 0.4)
        self.assertEqual(events[-1]["keys"], ["Ctrl"])

    def test_wrong_parent_stage_rejected(self):
        data = json.loads(self.source.read_text())
        data["stage"] = "unselected"
        self.source.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            self.build()

    def initial_fixture(self) -> tuple[dict[str, Any], dict[str, Any]]:
        point = dict(
            trial_mode="jump",
            queued_input=True,
            probe_sha256={},
            native_timeline=timeline(0, 0.15, False),
        )
        row = dict(
            queued_input=True,
            trace=[
                dict(
                    time=i / 60,
                    jump_requested_time=0,
                    input=dict(jump=i == 1),
                    probe_sha256={},
                    cadence=dict(
                        tick=i,
                        violation=False,
                        process_delta=1,
                        prequeued=True,
                        inline_events=0,
                    ),
                )
                for i in range(2)
            ],
        )
        return point, row

    def test_initial_tick_failure_is_rejected_without_editing_raw_evidence(self):
        point, row = self.initial_fixture()
        before = json.dumps(row)
        self.assertTrue(initial_jump_rejection(point, row, 60))
        self.assertEqual(before, json.dumps(row))

    def test_rejected_initial_tick_still_checks_other_cadence_contracts(self):
        for field, value in (
            ("inline_events", 1),
            ("prequeued", False),
            ("violation", True),
            ("process_delta", 2),
        ):
            point, row = self.initial_fixture()
            row["trace"][1]["cadence"][field] = value
            with self.assertRaises(ValueError):
                initial_jump_rejection(point, row, 60)

    def test_noninitial_or_wrong_delay_is_fatal(self):
        for requested, observed in ((0.1, 1 / 60), (0, 2 / 60)):
            point, row = self.initial_fixture()
            row["trace"][1].update(jump_requested_time=requested, time=observed)
            with self.assertRaises(ValueError):
                initial_jump_rejection(point, row, 60)

    def test_valid_boundary_is_not_classified_as_rejected(self):
        point, row = self.initial_fixture()
        row["trace"][1]["jump_requested_time"] = 1 / 60
        self.assertFalse(initial_jump_rejection(point, row, 60))

    def test_selection_excludes_initial_tick_even_when_geometric_outcome_passes(self):
        grid = self.root / "grid.json"
        grid.write_text(json.dumps(self.build()))
        report = self.root / "report.json"
        report.write_text(
            json.dumps(
                dict(
                    results=[dict(id=p["id"], trace=[]) for p in self.build()["cases"]]
                )
            )
        )
        with (
            patch("surface_ingress_study.check_report"),
            patch("surface_ingress_study.check_control"),
            patch("surface_ingress_study.check_cadence"),
            patch(
                "surface_ingress_study.initial_jump_rejection",
                side_effect=lambda p, *_: p["variant"].startswith("jump0_"),
            ),
            patch("surface_ingress_study.qualify", return_value={"passed": True}),
            patch(
                "surface_ingress_study.outcomes",
                return_value={"supported_arrival": False},
            ),
        ):
            result = selection(grid, report, self.root)
        self.assertEqual(len(result["cases"]), 9)
        self.assertTrue(
            all(p["variant"].startswith("jump100_") for p in result["cases"])
        )
        self.assertEqual(len(result["rejected_cadence_trials"]), 36)

    def qualifying_fixture(self, rate):
        point = dict(
            target_feet=[0, 0, 0], target_radius=0.35, target_height_tolerance=0.18
        )
        row: dict[str, Any] = dict(
            ingress_corridor={},
            trace=[
                dict(grounded_after=True, position=[0, 0.9, 0])
                for _ in range(round(rate * 0.1) + 1)
            ],
        )
        return point, row

    def check_qualify(self, point, row, rate, action=True, corridor=True, arrival=True):
        with (
            patch("surface_ingress_study.action_gate", return_value={"passed": action}),
            patch(
                "surface_ingress_study.clear_corridor", return_value=(corridor, False)
            ),
            patch(
                "surface_ingress_study.outcomes",
                return_value={"supported_arrival": arrival},
            ),
        ):
            return qualify(point, row, rate)

    def test_stable_goal_requires_supported_tail_at_both_rates(self):
        for rate in (60, 120):
            point, row = self.qualifying_fixture(rate)
            self.assertTrue(self.check_qualify(point, row, rate)["passed"])
            row["trace"][0]["grounded_after"] = False
            self.assertFalse(self.check_qualify(point, row, rate)["passed"])

    def test_overflying_or_leaving_goal_after_arrival_does_not_pass(self):
        point, row = self.qualifying_fixture(60)
        row["trace"][-1]["position"][0] = 1
        self.assertFalse(self.check_qualify(point, row, 60)["passed"])

    def test_action_corridor_and_arrival_are_all_required(self):
        point, row = self.qualifying_fixture(60)
        for key in ("action", "corridor", "arrival"):
            self.assertFalse(
                self.check_qualify(point, row, 60, **{key: False})["passed"]
            )


if __name__ == "__main__":
    unittest.main()
