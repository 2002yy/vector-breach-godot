"""Preserve frozen geometry and prevent selection/goal score laundering."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native_jump_candidates import (
    GEOMETRY,
    RUNTIME,
    choose,
    freeze,
    grid_payload,
    outcomes,
)


class NativeJumpCandidatesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in (*RUNTIME, "project.godot"):
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")
        self.point = dict(
            id="crouch_jump",
            start=[0, 0.9, 0],
            yaw=0,
            target_feet=[0, 0.5, -3],
            target_radius=1.6,
            target_height_tolerance=0.2,
            duration=2,
            timeline=[
                dict(at=0, direction=[0, -1], crouch=True),
                dict(at=0.1, jump=True),
                dict(at=0.2, jump=False),
            ],
        )
        self.parent = self.root / "parent.json"
        self.parent.write_text(
            json.dumps(dict(cases=[self.point], identity={}, level="fixture"))
        )

    def grid(self, revision="v1"):
        return grid_payload(self.parent, "mirage", self.root, revision)

    def test_six_bounded_variants_each_profile_and_negative_control(self):
        grid = self.grid()
        self.assertEqual(len(grid["cases"]), 36)
        self.assertFalse(grid["formal_qualification"])
        for point in grid["cases"]:
            self.assertEqual(
                [point[k] for k in GEOMETRY], [self.point[k] for k in GEOMETRY]
            )

    def test_backstep_changes_inputs_not_start_or_goal(self):
        grid = self.grid("v2")
        self.assertEqual(len(grid["cases"]), 12)
        for point in grid["cases"]:
            self.assertEqual(
                [point[k] for k in GEOMETRY], [self.point[k] for k in GEOMETRY]
            )
            self.assertEqual(point["native_timeline"][0]["keys"], ["S"])

    def test_paired_control_removes_only_jump_key(self):
        for jump, control in zip(self.grid()["cases"][::2], self.grid()["cases"][1::2]):
            expected = copy.deepcopy(jump["native_timeline"])
            for event in expected:
                event["keys"] = [k for k in event["keys"] if k != "Space"]
            self.assertEqual(control["native_timeline"], expected)

    def test_source_cannot_be_overwritten(self):
        data = self.parent.read_bytes()
        with self.assertRaises(ValueError):
            freeze(self.parent, {}, [self.parent])
        self.assertEqual(self.parent.read_bytes(), data)

    def test_frozen_input_cannot_be_replaced(self):
        output = self.root / "frozen.json"
        freeze(output, {"keys": ["W"]})
        with self.assertRaises(ValueError):
            freeze(output, {"keys": ["S"]})

    def candidate_results(self):
        grid = self.grid()
        results = {
            p["id"]: dict(first_landing=False, supported_arrival=False)
            for p in grid["cases"]
        }
        return grid, results

    def test_later_arrival_alone_is_not_precision_selection(self):
        grid, results = self.candidate_results()
        for point in grid["cases"]:
            if point["trial_mode"] == "jump":
                results[point["id"]]["supported_arrival"] = True
        selected, rejected = choose(grid, results)
        self.assertEqual(selected, [])
        self.assertEqual(len(rejected), 3)

    def test_positive_walking_control_disqualifies_selection(self):
        grid, results = self.candidate_results()
        results[grid["cases"][0]["id"]]["first_landing"] = True
        results[grid["cases"][1]["id"]]["supported_arrival"] = True
        self.assertEqual(choose(grid, results)[0], [])

    def test_selects_first_declared_success_not_an_unreported_best(self):
        grid, results = self.candidate_results()
        for point in grid["cases"]:
            if point["scheme"] == "current" and point["trial_mode"] == "jump":
                results[point["id"]]["first_landing"] = True
        selected, rejected = choose(grid, results)
        self.assertEqual(selected[0]["variant"], "precrouch_010")
        self.assertEqual(len(selected), 2)
        self.assertEqual(len(rejected), 2)

    def result(self):
        point = dict(self.point, trial_mode="jump")
        trace = [
            dict(position=[0, 1.4, -0.5], jumped=True, grounded_after=False),
            dict(position=[0, 1.4, -0.6], jumped=False, grounded_after=True, time=0.5),
            dict(position=[0, 1.4, -3], jumped=False, grounded_after=True, time=0.9),
        ]
        row = dict(
            trace=trace,
            goal_entry_support=[dict(body="original", normal=[0, 1, 0])],
            target_entry=trace[2],
            landing=trace[1],
            start_valid=True,
            support=[{}],
            route_arrival_reached=True,
            target_reached=False,
        )
        return point, row

    def test_trace_keeps_first_landing_separate_from_platform_entry(self):
        point, row = self.result()
        result = outcomes(point, row)
        self.assertFalse(result["first_landing"])
        self.assertTrue(result["supported_arrival"])

    def test_later_entry_cannot_replace_first_landing_record(self):
        point, row = self.result()
        row["landing"] = row["target_entry"]
        row["target_reached"] = True
        with self.assertRaises(ValueError):
            outcomes(point, row)

    def test_fabricated_first_landing_boolean_rejected(self):
        point, row = self.result()
        row["target_reached"] = True
        with self.assertRaises(ValueError):
            outcomes(point, row)

    def test_airborne_entry_is_not_supported_arrival(self):
        point, row = self.result()
        row["trace"][2]["grounded_after"] = False
        with self.assertRaises(ValueError):
            outcomes(point, row)

    def test_support_with_wall_normal_rejected(self):
        point, row = self.result()
        row["goal_entry_support"][0]["normal"] = [1, 0, 0]
        with self.assertRaises(ValueError):
            outcomes(point, row)


if __name__ == "__main__":
    unittest.main()
