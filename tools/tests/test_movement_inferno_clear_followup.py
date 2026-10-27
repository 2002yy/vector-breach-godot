"""Follow-up timings remain bounded, paired and on rise_03."""

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inferno_clear_followup import payload, timeline
import test_movement_inferno_clear_inputs as fixtures


class InfernoFollowupTests(unittest.TestCase):
    def test_current_brake_brackets_previous_overshoot(self):
        for variant, air in enumerate((0.15, 0.225)):
            events = timeline("current", variant)
            self.assertAlmostEqual(events[4]["at"] - events[2]["at"], air)
            self.assertAlmostEqual(events[5]["at"] - events[4]["at"], 1 / 30)

    def test_modern_extends_run_and_removes_air_reverse(self):
        for variant, run in enumerate((0.30, 0.35)):
            events = timeline("modern_cs", variant)
            self.assertAlmostEqual(events[2]["at"] - events[1]["at"], run)
            self.assertFalse(any("S" in e["keys"] for e in events[1:]))

    def test_followup_is_twelve_trials_same_point_unchanged_geometry(self):
        original = fixtures.InfernoClearInputsTests().grid()
        with patch("inferno_clear_followup.first_payload", return_value=original):
            data = payload(Path("s"), Path("o"), Path("p"))
        self.assertEqual(len(data["cases"]), 12)
        self.assertEqual({p["parent_case"] for p in data["cases"]}, {"rise_03"})
        self.assertEqual({p["scheme"] for p in data["cases"]}, {"current", "modern_cs"})
        for p in data["cases"]:
            self.assertEqual(p["start"], [1, 2, 3])
            self.assertEqual(p["target_feet"], [4, 5, 6])
            self.assertEqual(p["target_height_tolerance"], 0.18)


if __name__ == "__main__":
    unittest.main()
