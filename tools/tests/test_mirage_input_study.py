import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_mirage_input_study import check_outcomes, compare_unchanged


class InputStudyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        case = {"start": [0, 0.9, 0], "target_feet": [1, 0, 0], "yaw": 0,
                "timeline": [{"at": 0, "direction": [0, -1]}, {"at": 0.1, "jump": True}],
                "duration": 2, "target_radius": 0.2, "target_height_tolerance": 0.1}
        self.parent = self.root / "parent.json"
        self.parent.write_text(json.dumps({"level": "synthetic", "identity": {"collision": "x"},
            "cases": [dict(case, id="run_up"), dict(case, id="crouch_jump")]}), encoding="utf-8")
        self.discovery = self.root / "discovery.json"
        self.payload = {"manifest_sha256": hashlib.sha256(self.parent.read_bytes()).hexdigest(),
            "identity": {"collision": "x"}, "runtime_sha256": {"player": "baseline"}, "results": [
                {"mode": mode, "control_type": "feedback_discovery_not_acceptance",
                 "trace": [{"input": {"at": 0, "direction": [0, -1], "jump": False,
                                      "walk": mode == "walk", "crouch": False}}]}
                for mode in ("no_jump", "walk")]}
        self.discovery.write_text(json.dumps(self.payload), encoding="utf-8")

    def build(self, output):
        script = Path(__file__).resolve().parents[1] / "build_mirage_input_study.py"
        return subprocess.run([sys.executable, str(script), str(self.parent), str(self.discovery),
                               str(output)], capture_output=True)

    def test_feedback_inputs_are_frozen_without_promoting_qualification(self):
        output = self.root / "study.json"
        result = self.build(output)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        study = json.loads(output.read_text())
        self.assertFalse(study["formal_qualification"])
        self.assertEqual(len(study["cases"]), 6)
        self.assertEqual(study["cases"][0]["timeline"], [self.payload["results"][0]["trace"][0]["input"]])

    def test_wrong_discovery_identity_rejected(self):
        self.payload["manifest_sha256"] = "wrong"
        self.discovery.write_text(json.dumps(self.payload), encoding="utf-8")
        self.assertNotEqual(self.build(self.root / "study.json").returncode, 0)

    def test_study_cannot_overwrite_parent(self):
        original = self.parent.read_bytes()
        self.assertNotEqual(self.build(self.parent).returncode, 0)
        self.assertEqual(self.parent.read_bytes(), original)

    def test_captured_inputs_cannot_silently_replace_frozen_study(self):
        output = self.root / "study.json"
        self.assertEqual(self.build(output).returncode, 0)
        original = output.read_bytes()
        self.payload["results"][0]["trace"][0]["input"]["direction"] = [1, 0]
        self.discovery.write_text(json.dumps(self.payload), encoding="utf-8")
        self.assertNotEqual(self.build(output).returncode, 0)
        self.assertEqual(output.read_bytes(), original)

    @staticmethod
    def trial():
        return {"trace": [{"time": 0, "jumped": False, "grounded_before": True,
            "grounded_after": True, "position": [0, 0.9, 0], "velocity": [0, 0, 0],
            "input": {}, "speed_limit": 6.2, "crouching": False, "capsule_height": 1.8}],
            "reason": "outside_target", "route_arrival_reached": False}

    def test_current_motion_drift_rejected(self):
        before = {("point", "current"): self.trial()}
        after = copy.deepcopy(before)
        after[("point", "current")]["trace"][0]["position"][0] = 0.01
        with self.assertRaises(ValueError): compare_unchanged(before, after)

    def test_legacy_motion_drift_rejected(self):
        before = {("point", "legacy_16"): self.trial()}
        after = copy.deepcopy(before)
        after[("point", "legacy_16")]["trace"][0]["velocity"][0] = 0.01
        with self.assertRaises(ValueError): compare_unchanged(before, after)

    def test_later_arrival_does_not_rewrite_first_landing(self):
        row = {"target_reached": False, "reason": "outside_target", "route_arrival_reached": True,
               "target_entry": {"grounded_after": True}, "goal_entry_support": [{"body": "frozen"}]}
        check_outcomes(row)
        self.assertFalse(row["target_reached"])

    def test_arrival_without_support_rejected(self):
        row = {"target_reached": False, "reason": "outside_target", "route_arrival_reached": True,
               "target_entry": {"grounded_after": True}, "goal_entry_support": []}
        with self.assertRaises(ValueError): check_outcomes(row)

    def test_airborne_goal_entry_is_not_supported_arrival(self):
        row = {"target_reached": False, "reason": "outside_target", "route_arrival_reached": True,
               "target_entry": {"grounded_after": False}, "goal_entry_support": [{"body": "frozen"}]}
        with self.assertRaises(ValueError): check_outcomes(row)
