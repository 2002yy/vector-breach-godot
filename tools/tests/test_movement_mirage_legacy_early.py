"""Early Legacy inputs keep frozen route geometry and the real ground-run gate."""

import copy
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mirage_legacy_early import TIMES, payload, prefix, timeline, verify


class LegacyEarlyTests(unittest.TestCase):
    @staticmethod
    def row() -> dict[str, Any]:
        return dict(
            settled_start=[0, 1, 0],
            trace=[
                dict(time=i / 60, position=[i / 10, 1, 0], grounded_after=True)
                for i in range(15)
            ],
        )

    @staticmethod
    def source() -> dict[str, Any]:
        return dict(
            cases=[
                dict(
                    id="legacy_16__jump",
                    scheme="legacy_16",
                    trial_mode="jump",
                    start=[1, 2, 3],
                    target_feet=[4, 5, 6],
                    yaw=0,
                    target_radius=1.6,
                    target_height_tolerance=0.18,
                    duration=2,
                    kind="run_up",
                    geometry={"frozen": True},
                )
            ]
        )

    def test_exact_three_early_timings_no_reverse_brake(self):
        self.assertEqual(TIMES, (0.15, 1 / 6, 11 / 60))
        for time in TIMES:
            events = timeline(time)
            self.assertEqual(
                next(e["at"] for e in events if "Space" in e["keys"]), time
            )
            self.assertFalse(any("S" in e["keys"] for e in events))
            self.assertLess(time, 0.216667)
        with self.assertRaisesRegex(ValueError, "unknown"):
            timeline(0.2)

    def test_prefix_is_actual_horizontal_path_before_takeoff(self):
        row = self.row()
        self.assertAlmostEqual(prefix(row, 0.15)["grounded_distance_m"], 0.8)
        row["trace"][4]["grounded_after"] = False
        with self.assertRaisesRegex(ValueError, "supported"):
            prefix(row, 0.15)

    def make_payload(self, row):
        source = self.source()
        original = copy.deepcopy(source)
        with (
            patch("mirage_legacy_early.source_data", return_value=source),
            patch("mirage_legacy_early.verify_prior", return_value={}),
            patch(
                "mirage_legacy_early.checked",
                return_value=({}, {"legacy_16__later0__no_jump": row}),
            ),
            patch("mirage_legacy_early.sha", return_value="0" * 64),
        ):
            result = payload(
                Path("source"), Path("prior"), Path("out"), Path("project")
            )
        self.assertEqual(source, original)
        return result, original["cases"][0]

    def test_grid_preserves_all_route_geometry_and_paired_control_times(self):
        data, parent = self.make_payload(self.row())
        self.assertEqual(len(data["cases"]), 9)
        for point in data["cases"]:
            for field in (
                "start",
                "target_feet",
                "yaw",
                "target_radius",
                "target_height_tolerance",
                "duration",
                "kind",
                "geometry",
            ):
                self.assertEqual(point[field], parent[field])
        for index in range(3):
            points = {
                p["trial_mode"]: p for p in data["cases"] if p["variant"] == index
            }
            for mode in ("no_jump", "walk"):
                for a, b in zip(
                    points["jump"]["native_timeline"], points[mode]["native_timeline"]
                ):
                    self.assertEqual(a["at"], b["at"])
                    self.assertEqual(
                        [k for k in a["keys"] if k != "Space"],
                        [k for k in b["keys"] if k != "Shift"],
                    )

    def test_no_short_run_can_be_silently_granted_the_runup_contract(self):
        row = self.row()
        for point in row["trace"]:
            point["position"][0] *= 0.1
        with self.assertRaisesRegex(ValueError, "distance"):
            self.make_payload(row)

    def test_mutated_frozen_grid_is_rejected_before_selection(self):
        with (
            patch("mirage_legacy_early.payload", return_value={"expected": True}),
            patch("mirage_legacy_early.read", return_value={"forged": True}),
        ):
            with self.assertRaisesRegex(ValueError, "grid changed"):
                verify(Path("source"), Path("prior"), Path("out"), Path("project"))


if __name__ == "__main__":
    unittest.main()
