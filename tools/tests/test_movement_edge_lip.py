"""An edge timing bracket needs observed support and a matching input prefix."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import SCHEMES, sha
from edge_lip_window import (
    bracket,
    first_contact,
    matrix_payload,
    observe,
    prefix_matches,
    support_loss,
)


def control_trace(loss=6) -> list[dict[str, Any]]:
    return [
        dict(
            time=i / 60,
            position=[0, 1.9 if i < loss else 0.9, 0],
            velocity=[0, 0, 0],
            input=dict(jump=False),
            jumped=False,
            grounded_before=i <= loss,
            grounded_after=i < loss,
            speed_limit=5.8,
            crouching=False,
            capsule_height=1.8,
            native_command=dict(keys=["W"], mouse_dx=0),
            yaw=0,
        )
        for i in range(20)
    ]


def control_row() -> dict[str, Any]:
    return dict(start_valid=True, trace=control_trace())


class EdgeLipTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "probe.gd").write_text("fixture")
        self.manifest = self.root / "source.json"
        self.report = self.root / "report60.json"
        self.points, self.rows = {}, {}
        for scheme, loss in zip(SCHEMES, (8, 10, 12)):
            for mode in ("jump", "no_jump", "walk"):
                key = f"edge__{scheme}__{mode}"
                self.points[key] = dict(
                    id=key,
                    scheme=scheme,
                    kind="edge",
                    trial_mode=mode,
                    queued_input=True,
                    enforce_cadence=True,
                    duration=2,
                    start=[0, 1.9, 0],
                    target_feet=[0, 0, 0],
                    geometry=dict(feet=[0, 1, 0], near_feet=[0, 0, 0]),
                    probe_sha256={"res://probe.gd": sha(self.root / "probe.gd")},
                    native_timeline=[
                        dict(at=0, keys=["W"], mouse_dx=0),
                        dict(at=1.5, keys=[], mouse_dx=0),
                    ],
                )
                self.rows[key] = dict(
                    start_valid=True,
                    settled_start=[0, 1.9, 0],
                    trace=control_trace(loss),
                )
        self.manifest.write_text(
            json.dumps(
                dict(
                    schema=4,
                    formal_qualification=False,
                    cases=list(self.points.values()),
                )
            )
        )
        self.report.write_text("{}")
        self.source = dict(manifest=str(self.manifest), report60=str(self.report))

    def build(self):
        with patch("edge_lip_window.checked", return_value=(self.points, self.rows)):
            return matrix_payload(
                "dust2", self.source, self.root, self.root / "reject.json"
            )

    def test_twenty_one_cases_with_five_offsets_and_shared_controls(self):
        result = self.build()
        self.assertEqual(len(result["cases"]), 21)
        self.assertEqual(len({p["id"] for p in result["cases"]}), 21)
        for scheme in SCHEMES:
            points = [p for p in result["cases"] if p["scheme"] == scheme]
            self.assertEqual(sum(p["trial_mode"] == "jump" for p in points), 5)
            self.assertEqual(
                {p["trial_mode"] for p in points}, {"jump", "no_jump", "walk"}
            )
        self.assertFalse(result["formal_qualification"])

    def test_anchor_uses_only_original60_control_and_preserves_geometry(self):
        before = copy.deepcopy(self.points)
        result = self.build()
        self.assertEqual(list(result["anchors_ticks60"].values()), [8, 10, 12])
        for point in result["cases"]:
            original = self.points[point["source_case"]]
            self.assertEqual(point["start"], original["start"])
            self.assertEqual(point["geometry"], original["geometry"])
            self.assertEqual(point["target_feet"], original["target_feet"])
            if point["trial_mode"] == "jump":
                expected = (
                    result["anchors_ticks60"][point["scheme"]]
                    + point["lip_offset_ticks60"]
                ) / 60
                self.assertEqual(point["request_time"], expected)
        self.assertEqual(self.points, before)

    def test_live_probe_drift_is_fatal(self):
        (self.root / "probe.gd").write_text("changed")
        with self.assertRaisesRegex(ValueError, "author probe drift"):
            self.build()

    def test_control_without_actual_drop_is_rejected(self):
        row = control_row()
        for sample in row["trace"]:
            sample["grounded_after"] = True
        with self.assertRaisesRegex(ValueError, "never left support"):
            support_loss(row)

    def test_initial_airborne_control_is_not_a_support_interval(self):
        row = control_row()
        row["trace"][0]["grounded_after"] = False
        with self.assertRaisesRegex(ValueError, "initial support interval"):
            support_loss(row)

    def prefix_fixture(
        self, tick=6
    ) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        control = control_row()
        row = copy.deepcopy(control)
        row["trace"][tick]["input"]["jump"] = True
        point = dict(
            request_time=tick / 60,
            lip_offset_ticks60=0,
            target_feet=[0, 0, 0],
            target_radius=0.35,
            target_height_tolerance=0.18,
        )
        return point, row, control

    def test_changed_motion_before_request_invalidates_counterfactual(self):
        point, row, control = self.prefix_fixture()
        row["trace"][1]["velocity"][0] = 0.1
        with self.assertRaises(ValueError):
            prefix_matches(point, row, control)

    def test_motion_after_request_can_differ(self):
        point, row, control = self.prefix_fixture()
        row["trace"][7]["position"][0] = 1
        self.assertTrue(prefix_matches(point, row, control)["input"]["jump"])

    def test_missing_or_shifted_request_is_rejected(self):
        point, row, control = self.prefix_fixture()
        point["request_time"] += 0.001
        with self.assertRaisesRegex(ValueError, "request missing or shifted"):
            prefix_matches(point, row, control)
        row["trace"][6]["input"]["jump"] = False
        with self.assertRaisesRegex(ValueError, "request missing or shifted"):
            prefix_matches(point, row, control)

    def test_arrival_after_failed_takeoff_does_not_become_jump_success(self):
        point, row, control = self.prefix_fixture(7)
        with (
            patch("edge_lip_window.action_gate", return_value=dict(passed=False)),
            patch(
                "edge_lip_window.outcomes",
                return_value=dict(first_landing=False, supported_arrival=True),
            ),
        ):
            result = observe(point, row, control, 60)
        self.assertEqual(result["classification"], "airborne_request_rejected")
        self.assertFalse(result["takeoff"])
        self.assertTrue(result["supported_arrival"])

    def test_physical_fall_contact_is_separate_from_jump_landing(self):
        point, row, _ = self.prefix_fixture(7)
        row["trace"][12]["grounded_after"] = True
        self.assertEqual(first_contact(point, row), dict(time=0.2, inside_goal=True))
        self.assertFalse(any(s["jumped"] for s in row["trace"]))

    def test_ordered_positive_and_negative_samples_bracket_a_boundary(self):
        result = bracket(
            [
                dict(request_time=0.1, classification="supported_takeoff"),
                dict(
                    request_time=0.1 + 1 / 60,
                    classification="airborne_request_rejected",
                ),
            ]
        )
        self.assertTrue(result["found"])
        self.assertAlmostEqual(result["interval_seconds"], 1 / 60)

    def test_missing_side_or_nonmonotonic_samples_do_not_certify_boundary(self):
        accepted = dict(request_time=0.2, classification="supported_takeoff")
        rejected = dict(request_time=0.1, classification="airborne_request_rejected")
        for samples in (
            [accepted],
            [rejected],
            [accepted, rejected],
            [
                dict(request_time=0.05, classification="supported_request_rejected"),
                accepted,
                rejected,
            ],
        ):
            self.assertFalse(bracket(samples)["found"])

    def test_jump_contaminated_control_is_rejected(self):
        row = control_row()
        row["trace"][2]["input"]["jump"] = True
        with self.assertRaisesRegex(ValueError, "control performed a jump"):
            support_loss(row)


if __name__ == "__main__":
    unittest.main()
