"""A post-takeoff control cannot silently change the takeoff or landing goal."""

import copy
import json
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_edge_lip as fixtures
from edge_landing_controls import (
    VARIANTS,
    contact_metrics,
    observe,
    payload,
    prefix_before_switch,
    timeline,
)


class EdgeLandingTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.EdgeLipTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        matrix = self.fixture.build()
        for point in matrix["cases"]:
            point["yaw"] = 0
        self.path = self.root / "r17.json"
        self.path.write_text(json.dumps(matrix))
        self.points = {p["id"]: p for p in matrix["cases"]}
        self.rows = {k: {} for k in self.points}
        for name in ("old60.json", "old120.json"):
            (self.root / name).write_text("{}")
        self.source = dict(
            manifest=str(self.path),
            report60=str(self.root / "old60.json"),
            report120=str(self.root / "old120.json"),
        )

    def build(self, takeoff=True):
        with (
            patch(
                "edge_landing_controls.checked", return_value=(self.points, self.rows)
            ),
            patch(
                "edge_landing_controls.action_gate", return_value=dict(passed=takeoff)
            ),
        ):
            return payload("dust2", self.source, self.root, self.root / "reject.json")

    def test_fifteen_cases_cover_all_schemes_and_controls(self):
        result = self.build()
        self.assertEqual(len(result["cases"]), 15)
        self.assertEqual(len({p["id"] for p in result["cases"]}), 15)
        for scheme in ("current", "legacy_16", "modern_cs"):
            self.assertEqual(
                {
                    p["air_control_variant"]
                    for p in result["cases"]
                    if p["scheme"] == scheme
                },
                set(VARIANTS),
            )
        self.assertFalse(result["formal_qualification"])

    def test_goals_and_baseline_inputs_remain_exact(self):
        before = copy.deepcopy(self.points)
        for point in self.build()["cases"]:
            original = self.points[point["source_case"]]
            for field in ("start", "target_feet", "geometry", "yaw"):
                self.assertEqual(point[field], original[field])
            if point["air_control_variant"] == "baseline":
                self.assertEqual(point["native_timeline"], original["native_timeline"])
        self.assertEqual(self.points, before)

    def test_switch_occurs_after_identical_takeoff_and_releases_jump(self):
        for point in self.build()["cases"]:
            self.assertAlmostEqual(point["switch_time"] - point["request_time"], 1 / 60)
            events = point["native_timeline"]
            self.assertEqual(events[1]["keys"], ["W", "Space"])
            self.assertNotIn("Space", events[2]["keys"])
            self.assertAlmostEqual(events[2]["at"], point["switch_time"])

    def test_release_and_reverse_duration_are_frozen(self):
        original = self.points["lip__current__+0"]
        self.assertEqual(timeline(original, "release")[2]["keys"], [])
        for variant, duration in (("reverse_010", 0.1), ("reverse_030", 0.3)):
            events = timeline(original, variant)
            self.assertEqual(events[2]["keys"], ["S"])
            self.assertEqual(events[3]["keys"], [])
            self.assertAlmostEqual(events[3]["at"] - events[2]["at"], duration)
        self.assertEqual(timeline(original, "reverse_hold")[-1]["at"], 1.5)

    def test_unknown_input_or_wrong_parent_is_rejected(self):
        with self.assertRaises(ValueError):
            timeline({}, "unknown")
        parent = json.loads(self.path.read_text())
        parent["stage"] = "not_frozen"
        self.path.write_text(json.dumps(parent))
        with self.assertRaisesRegex(ValueError, "wrong edge parent"):
            self.build()

    def test_probe_drift_is_rejected(self):
        (self.root / "probe.gd").write_text("changed")
        with self.assertRaisesRegex(ValueError, "author probe drift"):
            self.build()

    def test_baseline_without_actual_takeoff_cannot_seed_controls(self):
        with self.assertRaisesRegex(ValueError, "baseline must take off"):
            self.build(takeoff=False)

    def prefix_fixture(self) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        point, row, _ = self.fixture.prefix_fixture()
        row["trace"][6]["jumped"] = True
        point["switch_time"] = 7 / 60
        return point, row, copy.deepcopy(row)

    def test_motion_change_before_switch_is_rejected(self):
        point, row, base = self.prefix_fixture()
        row["trace"][6]["velocity"][0] = 0.01
        with self.assertRaises(ValueError):
            prefix_before_switch(point, row, base)

    def test_post_switch_motion_can_change_without_mutating_baseline(self):
        point, row, base = self.prefix_fixture()
        before = copy.deepcopy(base)
        row["trace"][7]["velocity"][0] = -1
        prefix_before_switch(point, row, base)
        self.assertEqual(base, before)

    def test_prefix_requires_real_takeoff(self):
        point, row, base = self.prefix_fixture()
        row["trace"][6]["jumped"] = False
        with self.assertRaisesRegex(ValueError, "include actual takeoff"):
            prefix_before_switch(point, row, base)

    def test_contact_errors_have_signed_route_and_height_components(self):
        point = dict(start=[0, 1.9, 0], target_feet=[0, 0, -1])
        row = dict(landing=dict(position=[0, 1.1, -3], time=1.2))
        result = contact_metrics(point, row)
        self.assertEqual(result["forward_error_m"], 2)
        self.assertEqual(result["horizontal_error_m"], 2)
        self.assertEqual(result["lateral_error_m"], 0)
        self.assertAlmostEqual(result["height_error_m"], 0.2)

    def test_no_contact_or_zero_direction_cannot_fabricate_metrics(self):
        self.assertFalse(contact_metrics({}, dict(landing={}))["observed"])
        with self.assertRaisesRegex(ValueError, "zero forward reference"):
            contact_metrics(
                dict(start=[0, 0, 0], target_feet=[0, 0, 0]),
                dict(landing=dict(position=[0, 0.9, 0], time=1)),
            )

    def observe_fixture(self, row):
        point = dict(
            start=[0, 1.9, 0],
            target_feet=[0, 0, -1],
            switch_time=0.1,
            air_control_variant="release",
        )
        with (
            patch("edge_landing_controls.prefix_before_switch"),
            patch("edge_landing_controls.action_gate", return_value=dict(passed=True)),
            patch(
                "edge_landing_controls.outcomes",
                return_value=dict(first_landing=False, supported_arrival=True),
            ),
        ):
            return observe(point, row, {}, 60)

    def test_later_arrival_does_not_replace_first_landing(self):
        result = self.observe_fixture(
            dict(landing=dict(position=[0, 0.9, -3], time=1), trace=[])
        )
        self.assertFalse(result["first_landing"])
        self.assertTrue(result["supported_arrival"])
        self.assertEqual(result["contact"]["forward_error_m"], 2)

    def test_air_speed_excludes_reversal_after_first_contact(self):
        row = dict(
            landing=dict(position=[0, 0.9, -3], time=1),
            trace=[
                dict(time=0.2, velocity=[0, 0, -2], grounded_after=False),
                dict(time=0.3, velocity=[0, 0, 0.5], grounded_after=False),
                dict(time=1.2, velocity=[0, 0, 99], grounded_after=False),
            ],
        )
        result = self.observe_fixture(row)
        self.assertEqual(result["minimum_forward_speed_airborne"], -0.5)
        self.assertTrue(result["airborne_reversed"])


if __name__ == "__main__":
    unittest.main()
