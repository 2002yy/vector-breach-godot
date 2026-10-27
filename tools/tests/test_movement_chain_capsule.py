"""Actual travels/tails stay bound, standing and conservative about recovery."""

import copy
import os
from pathlib import Path
import subprocess
import sys
import unittest
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from inferno_chain_capsule import bound_equal, segments_for


class ChainCapsuleTests(unittest.TestCase):
    @staticmethod
    def row() -> dict[str, Any]:
        receipt = dict(
            stage="before_camera",
            start=[0, 0, 0],
            end=[1, 0, -2],
            position_delta=[1, 0, -2],
            last_motion=[0, 0, -1],
            slide_count=1,
            movements=[
                dict(
                    index=0,
                    travel=[1, 0, -1],
                    remainder=[30, 20, 10],
                    depth=0.001,
                    contacts=[
                        dict(
                            body="/root/wall",
                            shape=0,
                            normal=[-1, 0, 0],
                            position=[1.4, 0, -1],
                        )
                    ],
                )
            ],
        )
        frame = dict(
            slide_path=receipt,
            jumped=True,
            time=0.2,
            position=[1, 0, -2],
            stages=[],
            crouching=False,
            capsule_height=1.8,
        )
        return dict(trace=[frame], settled_start=[0, 0, 0], landing=dict(time=0.2))

    def test_actual_turn_and_terminal_tail_not_remainder(self):
        segments, outside, count = segments_for(self.row())
        self.assertEqual((count, outside), (1, []))
        self.assertEqual(
            [s["kind"] for s in segments],
            ["travel", "last_motion_tail", "comparison_chord"],
        )
        self.assertEqual(segments[0]["to"], segments[1]["from"])
        self.assertEqual(segments[1]["to"], [1, 0, -2])
        self.assertTrue(all(s["recovery_depth"] == 0.001 for s in segments))

    def test_shifted_origin_or_endpoint_rejected(self):
        for field in ("settled_start", "position"):
            row = self.row()
            if field == "settled_start":
                row[field][0] = 5
            else:
                row["trace"][0][field][0] = 5
            with self.subTest(field=field), self.assertRaises(ValueError):
                segments_for(row)

    def test_crouch_or_nonfinite_height_cannot_keep_zero_offset(self):
        for height in (1.2, float("nan"), float("inf")):
            row = self.row()
            row["trace"][0]["capsule_height"] = height
            with (
                self.subTest(height=height),
                self.assertRaisesRegex(ValueError, "standing"),
            ):
                segments_for(row)

    def test_unreconciled_airborne_displacement_not_replaced_by_chord(self):
        row = self.row()
        row["trace"][0]["slide_path"]["last_motion"] = [0, 0, 0]
        with self.assertRaisesRegex(ValueError, "unreconciled airborne"):
            segments_for(row)

    def test_unreconciled_outside_frames_stay_explicit(self):
        row = self.row()
        extra = copy.deepcopy(row["trace"][0])
        extra.update(jumped=False, time=0.3, position=[2, 0, -4])
        extra["slide_path"].update(
            start=[1, 0, -2], end=[2, 0, -4], last_motion=[0, 0, 0]
        )
        row["trace"].append(extra)
        self.assertEqual(segments_for(row)[1], [1])

    def test_godot_json_roundtrip_tolerance_is_bounded_and_finite(self):
        self.assertTrue(bound_equal([1.23456789012345], [1.2345678901234]))
        self.assertFalse(bound_equal([1.0], [1.00001]))
        self.assertFalse(bound_equal([1.0], [float("nan")]))
        self.assertFalse(bound_equal(dict(part=1), dict(part=2)))

    def test_native_thinwall_support_overlap_and_terminal_tail(self):
        candidates = [
            os.environ.get("GODOT_EXE", ""),
            os.environ.get("GODOT_BIN", ""),
            "D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe",
        ]
        executable = next((p for p in candidates if p and Path(p).is_file()), None)
        if executable is None:
            self.skipTest("Godot unavailable; CI supplies GODOT_BIN")
        result = subprocess.run(
            [
                executable,
                "--headless",
                "--path",
                str(ROOT),
                "--quit-after",
                "120",
                "-s",
                "tools/authoring/test_chain_capsule.gd",
            ],
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=45,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("CHAIN_CAPSULE_OK checks=8", output)
        self.assertNotIn("SCRIPT ERROR:", output)


if __name__ == "__main__":
    unittest.main()
