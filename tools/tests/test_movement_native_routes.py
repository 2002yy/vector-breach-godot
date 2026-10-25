"""Reject false input evidence, hidden feedback and rewritten frozen routes."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import SCHEMES, freeze, sha
from validate_native_route_study import check_trace


class NativeInputEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.seed, self.discovery, self.output = (self.root / n for n in ("seed.json", "discovery.json", "study.json"))
        point = dict(start=[0, 1, 0], yaw=0, target_feet=[0, 0, -3], target_radius=1,
                     target_height_tolerance=0.2, duration=2,
                     timeline=[dict(at=0, direction=[0, -1]), dict(at=0.1, jump=True), dict(at=0.2, jump=False)])
        self.seed.write_text(json.dumps(dict(level="fixture", identity={}, cases=[
            dict(point, id="run_up"), dict(point, id="crouch_jump")])))
        self.found = dict(manifest_sha256=sha(self.seed), identity={}, feedback=True,
                          runtime_sha256={}, input_map_sha256="input-map", results=[
            dict(scheme=s, mode=m, feedback=True, route_arrival_reached=True,
                 trace=[dict(time=0, native_command=dict(keys=["W"], mouse_dx=20))])
            for s in SCHEMES for m in ("no_jump", "walk")])
        self.save_found()

    def save_found(self):
        self.discovery.write_text(json.dumps(self.found))

    def test_routes_bound_to_each_profile_and_goals_separate(self):
        study = freeze(self.seed, self.discovery, self.output)
        self.assertEqual(len(study["cases"]), 15)
        self.assertFalse(study["formal_qualification"])
        self.assertEqual({p["goal_kind"] for p in study["cases"]},
                         {"supported_arrival", "first_landing", "input_contract"})

    def test_duplicate_profile_rejected(self):
        self.found["results"][-1] = copy.deepcopy(self.found["results"][0])
        self.save_found()
        with self.assertRaises(ValueError): freeze(self.seed, self.discovery, self.output)

    def test_unproven_route_rejected(self):
        self.found["results"][0]["route_arrival_reached"] = False
        self.save_found()
        with self.assertRaises(ValueError): freeze(self.seed, self.discovery, self.output)

    def test_parent_identity_drift_rejected(self):
        self.found["manifest_sha256"] = "different"
        self.save_found()
        with self.assertRaises(ValueError): freeze(self.seed, self.discovery, self.output)

    def test_parent_cannot_be_overwritten(self):
        original = self.seed.read_bytes()
        with self.assertRaises(ValueError): freeze(self.seed, self.discovery, self.seed)
        self.assertEqual(self.seed.read_bytes(), original)

    def test_frozen_inputs_cannot_be_replaced(self):
        freeze(self.seed, self.discovery, self.output)
        original = self.output.read_bytes()
        self.found["results"][0]["trace"][0]["native_command"]["mouse_dx"] = 40
        self.save_found()
        with self.assertRaises(ValueError): freeze(self.seed, self.discovery, self.output)
        self.assertEqual(self.output.read_bytes(), original)

    @staticmethod
    def input_fixture():
        point = dict(duration=0.2, native_timeline=[dict(at=0, keys=["W", "Space"], mouse_dx=20)])
        first = dict(time=0, native_command=dict(keys=["W", "Space"], mouse_dx=20),
                     input=dict(direction=[0, -1], crouch=False, walk=False, jump=False),
                     mouse_events_seen=1, key_events_seen=2,
                     last_mouse=dict(dx=20, before=0, after=-0.044, sensitivity=0.0022),
                     jump_requested_time=-1)
        second = copy.deepcopy(first)
        second.update(time=0.1, native_command=dict(keys=["W", "Space"], mouse_dx=0), jump_requested_time=0)
        second["input"]["jump"] = True
        row = dict(feedback=False, input_released=True, trace=[first, second],
                   target_reached=False, reason="outside_target", route_arrival_reached=False)
        return point, row

    def test_one_tick_jump_delay_recorded(self):
        point, row = self.input_fixture()
        self.assertEqual(check_trace(point, row, 10), [0.1])

    def test_viewport_scaled_mouse_rejected(self):
        point, row = self.input_fixture()
        row["trace"][0]["last_mouse"]["dx"] = 500
        with self.assertRaises(ValueError): check_trace(point, row, 10)

    def test_missing_mouse_handler_rejected(self):
        point, row = self.input_fixture()
        row["trace"][0]["last_mouse"]["after"] = 0
        with self.assertRaises(ValueError): check_trace(point, row, 10)

    def test_wrong_inputmap_direction_rejected(self):
        point, row = self.input_fixture()
        row["trace"][0]["input"]["direction"] = [1, 0]
        with self.assertRaises(ValueError): check_trace(point, row, 10)

    def test_hidden_feedback_rejected(self):
        point, row = self.input_fixture()
        row["feedback"] = True
        with self.assertRaises(ValueError): check_trace(point, row, 10)

    def test_lost_jump_edge_rejected(self):
        point, row = self.input_fixture()
        row["trace"][1]["input"]["jump"] = False
        with self.assertRaises(ValueError): check_trace(point, row, 10)

    def test_stuck_keys_rejected(self):
        point, row = self.input_fixture()
        row["input_released"] = False
        with self.assertRaises(ValueError): check_trace(point, row, 10)

    def test_arrival_does_not_promote_first_landing(self):
        point, row = self.input_fixture()
        row.update(route_arrival_reached=True, start_valid=True,
                   target_entry=dict(grounded_after=True), goal_entry_support=[dict(body="frozen")])
        check_trace(point, row, 10)
        self.assertFalse(row["target_reached"])

    def test_airborne_arrival_rejected(self):
        point, row = self.input_fixture()
        row.update(route_arrival_reached=True, start_valid=True,
                   target_entry=dict(grounded_after=False), goal_entry_support=[dict(body="frozen")])
        with self.assertRaises(ValueError): check_trace(point, row, 10)


if __name__ == "__main__":
    unittest.main()
