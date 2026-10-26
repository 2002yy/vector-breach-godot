"""A supported action, walkable target and qualified jump route are distinct."""

import copy
import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from movement_dimension_gates import (
    action_gate,
    category_coverage,
    check_control,
    route_gate,
)


class MovementDimensionTests(unittest.TestCase):
    def fixture(self, rate=60) -> tuple[dict[str, Any], dict[str, Any]]:
        point = dict(
            queued_input=True,
            trial_mode="jump",
            duration=3 / rate,
            probe_sha256={"fixture": "sha"},
            native_timeline=[
                dict(at=0, keys=["Space"], mouse_dx=0),
                dict(at=1 / rate, keys=[], mouse_dx=0),
            ],
        )
        trace = [
            dict(
                time=i / rate,
                probe_sha256=point["probe_sha256"],
                native_command=dict(keys=["Space"] if i == 0 else [], mouse_dx=0),
                input=dict(direction=[0, 0], crouch=False, walk=False, jump=i == 0),
                key_events_seen=1 if i == 0 else 2,
                mouse_events_seen=0,
                jump_requested_time=0,
                jumped=i == 0,
                grounded_before=i == 0,
                grounded_after=False,
                velocity=[0, 1, 0],
                position=[0, 1 + i / rate, 0],
                cadence=dict(
                    tick=i,
                    process_frame=10 + i,
                    physics_frame=20 + i,
                    process_delta=1,
                    prequeued=True,
                    inline_events=0,
                    violation=False,
                ),
            )
            for i in range(3)
        ]
        row = dict(
            queued_input=True,
            feedback=False,
            input_released=True,
            trace=trace,
            start_valid=True,
            target_reached=False,
            reason="missed",
            route_arrival_reached=False,
        )
        return point, row

    def test_actual_takeoff_can_pass_without_target_arrival_at_both_rates(self):
        for rate in (60, 120):
            point, row = self.fixture(rate)
            self.assertTrue(action_gate(point, row, rate)["passed"])

    def test_edge_fall_without_jump_does_not_pass_action(self):
        point, row = self.fixture()
        row["trace"][0]["jumped"] = False
        self.assertFalse(action_gate(point, row, 60)["passed"])

    def test_takeoff_must_be_supported_and_upward(self):
        for field, value in (("grounded_before", False), ("grounded_after", True)):
            point, row = self.fixture()
            row["trace"][0][field] = value
            self.assertFalse(action_gate(point, row, 60)["passed"])
        point, row = self.fixture()
        row["trace"][0]["velocity"][1] = 0
        self.assertFalse(action_gate(point, row, 60)["passed"])

    def test_jump_flag_at_different_tick_is_not_input_response(self):
        point, row = self.fixture()
        row["trace"][0]["jumped"] = False
        row["trace"][1]["jumped"] = True
        self.assertFalse(action_gate(point, row, 60)["passed"])

    def test_repeated_takeoff_does_not_certify_single_jump(self):
        point, row = self.fixture()
        row["trace"][1]["jumped"] = True
        self.assertFalse(action_gate(point, row, 60)["passed"])

    def test_counter_claim_cannot_override_actual_counters(self):
        for counter in ("process_frame", "physics_frame"):
            point, row = self.fixture()
            row["trace"][1]["cadence"][counter] += 1
            with self.assertRaises(ValueError):
                action_gate(point, row, 60)

    def test_nonfinite_physical_evidence_rejected(self):
        for field in ("position", "velocity"):
            point, row = self.fixture()
            row["trace"][1][field][0] = float("nan")
            with self.assertRaises(ValueError):
                action_gate(point, row, 60)

    def test_inline_legacy_evidence_cannot_pass_queued_action_gate(self):
        point, row = self.fixture()
        point["queued_input"] = False
        with self.assertRaises(ValueError):
            action_gate(point, row, 60)

    def test_invalid_controls_cannot_supply_negative_arrival_evidence(self):
        _, row = self.fixture()
        with self.assertRaises(ValueError):
            check_control(row)
        for sample in row["trace"]:
            sample["jumped"] = sample["input"]["jump"] = False
        check_control(row)
        row["trace"][1]["position"][0] = float("nan")
        with self.assertRaises(ValueError):
            check_control(row)

    def route(self) -> tuple[dict[int, Any], ...]:
        return (
            {60: (True, False), 120: (True, False)},
            {60: {"passed": True}, 120: {"passed": True}},
            {60: True, 120: True},
            {r: {"no_jump": False, "walk": False} for r in (60, 120)},
        )

    def test_route_requires_both_rates_actions_landings_and_negative_controls(self):
        self.assertTrue(route_gate(*self.route())["jump_route_passed"])
        for index in (1, 2):
            args = list(copy.deepcopy(self.route()))
            args[index][120] = {"passed": False} if index == 1 else False
            self.assertFalse(route_gate(*args)["jump_route_passed"])

    def test_valid_action_and_walkable_target_remain_walk_only(self):
        args = list(self.route())
        for rows in args[3].values():
            rows["walk"] = True
        result = route_gate(*args)
        self.assertTrue(result["action_passed"])
        self.assertEqual(result["status"], "walk_only")
        self.assertFalse(result["jump_route_passed"])

    def test_body_blocking_prevents_jump_qualification(self):
        args = list(self.route())
        args[0] = {60: (False, True), 120: (False, True)}
        self.assertEqual(route_gate(*args)["status"], "blocked_direct_route")

    def test_missing_rate_or_control_rejected(self):
        for index in (0, 1, 2, 3):
            args = list(copy.deepcopy(self.route()))
            del args[index][120]
            with self.assertRaises(ValueError):
                route_gate(*args)
        args = list(self.route())
        del args[3][120]["walk"]
        with self.assertRaises(ValueError):
            route_gate(*args)

    def test_one_kind_cannot_cover_ordinary_or_edge_or_other_profiles(self):
        coverage = category_coverage(
            [
                dict(
                    map="dust2",
                    kind="critical_landing",
                    scheme="current",
                    action_passed=True,
                    jump_route_passed=True,
                )
            ]
        )
        self.assertEqual(len(coverage), 15)
        self.assertFalse(any(p["all_profiles_route_passed"] for p in coverage))
        self.assertFalse(
            any(
                p["action_evidence_present"]
                for p in coverage
                if p["category"] in ("ordinary", "edge")
            )
        )


if __name__ == "__main__":
    unittest.main()
