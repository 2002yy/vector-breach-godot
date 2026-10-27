"""Final brake timings and composite same-geometry authority."""

import copy
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_inferno_clear_inputs as fixtures
from inferno_current_brake import BRAKES, composite, payload, timeline


class CurrentBrakeTests(unittest.TestCase):
    def test_three_exact_brake_durations_preserve_launch(self):
        for i, brake in enumerate(BRAKES):
            events = timeline(i)
            self.assertEqual(events[2]["at"], 0.4)
            self.assertEqual(events[4]["at"], 0.55)
            self.assertAlmostEqual(events[5]["at"] - events[4]["at"], brake)
            self.assertEqual(events[5]["keys"], [])

    def test_nine_trials_only_current_same_original_point(self):
        original = fixtures.InfernoClearInputsTests().grid()
        with patch("inferno_current_brake.original_payload", return_value=original):
            data = payload(Path("s"), Path("o"), Path("p"))
        self.assertEqual(len(data["cases"]), 9)
        for p in data["cases"]:
            self.assertEqual(p["parent_case"], "rise_03")
            self.assertEqual(p["scheme"], "current")
            self.assertEqual(p["start"], [1, 2, 3])
            self.assertEqual(p["target_feet"], [4, 5, 6])
            self.assertEqual(p["target_height_tolerance"], 0.18)

    def fixture(self) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        point = dict(
            start=[1, 2, 3],
            yaw=0,
            target_feet=[4, 5, 6],
            target_radius=1.6,
            target_height_tolerance=0.18,
            geometry={},
            source_nav_node=1,
            kind="run_up",
            probe_sha256={},
            trial_mode="jump",
        )
        manifests = [
            dict(
                selected="rise_03",
                identity={},
                level="inferno",
                runtime_sha256={},
                input_map_sha256="same",
                cases=[copy.deepcopy(point)],
            )
            for _ in range(3)
        ]
        profiles = [
            dict(
                profiles={
                    s: dict(status="qualified_jump", category_action_passed=True)
                },
                selected_trials=6,
            )
            for s in ("legacy_16", "modern_cs", "current")
        ]
        return manifests, profiles

    def evaluate(self, manifests, reports):
        with (
            patch("inferno_current_brake.verify", side_effect=reports),
            patch("inferno_current_brake.read", side_effect=manifests),
            patch("inferno_current_brake.sha", return_value="0" * 64),
        ):
            return composite(Path("s"), Path("out/v3"), Path("p"))

    def test_composite_closes_only_all_three_strong_profiles(self):
        manifests, reports = self.fixture()
        self.assertTrue(self.evaluate(manifests, reports)["category_closed"])
        reports[2]["profiles"]["current"]["category_action_passed"] = False
        self.assertFalse(self.evaluate(manifests, reports)["category_closed"])

    def test_changed_target_cannot_borrow_other_profiles(self):
        manifests, reports = self.fixture()
        manifests[2]["cases"][0]["target_radius"] = 1.8
        with self.assertRaisesRegex(ValueError, "geometry"):
            self.evaluate(manifests, reports)

    def test_changed_runtime_or_probe_cannot_borrow_profiles(self):
        for changed in ("runtime", "probe"):
            manifests, reports = self.fixture()
            if changed == "runtime":
                manifests[2]["runtime_sha256"] = {"changed": "sha"}
            else:
                manifests[2]["cases"][0]["probe_sha256"] = {"changed": "sha"}
            with self.assertRaises(ValueError):
                self.evaluate(manifests, reports)


if __name__ == "__main__":
    unittest.main()
