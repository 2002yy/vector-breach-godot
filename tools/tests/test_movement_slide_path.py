"""Slide travel is ordered physical displacement; requested remainders are not paths."""

import copy
import os
from pathlib import Path
import subprocess
import sys
import unittest
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from inferno_slide_path import check_anchor, reconstruct


class SlidePathTests(unittest.TestCase):
    @staticmethod
    def receipt() -> dict[str, Any]:
        return dict(
            stage="fixture",
            start=[0, 0, 0],
            end=[1, 0, -2],
            position_delta=[1, 0, -2],
            last_motion=[0, 0, -1],
            slide_count=1,
            movements=[
                dict(
                    index=0,
                    travel=[1, 0, -1],
                    remainder=[100, 200, 300],
                    depth=0.001,
                    contacts=[
                        dict(
                            body="/root/fixture",
                            shape=0,
                            normal=[-1, 0, 0],
                            position=[1.4, 0, -1],
                        )
                    ],
                )
            ],
        )

    def test_collision_then_clear_tail_is_reconstructed(self):
        result = reconstruct(self.receipt())
        self.assertTrue(result["movement_chain_reconciled"])
        self.assertEqual(result["points"], [[0, 0, 0], [1, 0, -1], [1, 0, -2]])
        self.assertFalse(result["geometric_clearance_proven"])

    def test_last_collision_travel_is_not_counted_twice(self):
        receipt = self.receipt()
        receipt.update(
            end=[1, 0, -1], position_delta=[1, 0, -1], last_motion=[1, 0, -1]
        )
        result = reconstruct(receipt)
        self.assertEqual(result["tail_kind"], "no_terminal_tail")
        self.assertEqual(len(result["points"]), 2)

    def test_requested_remainder_never_becomes_traveled_point(self):
        a = self.receipt()
        b = copy.deepcopy(a)
        b["movements"][0]["remainder"] = [-500, 900, 3]
        self.assertEqual(reconstruct(a)["points"], reconstruct(b)["points"])

    def test_unreconciled_motion_remains_incomplete(self):
        receipt = self.receipt()
        receipt["last_motion"] = [0, 0, 0]
        result = reconstruct(receipt)
        self.assertFalse(result["movement_chain_reconciled"])
        self.assertEqual(result["tail_kind"], "unreconciled_terminal_displacement")

    def test_wrong_endpoint_or_collision_order_is_rejected(self):
        for field in ("endpoint", "order"):
            receipt = self.receipt()
            if field == "endpoint":
                receipt["end"][0] += 1
            else:
                receipt["movements"][0]["index"] = 1
            with self.subTest(field=field), self.assertRaises(ValueError):
                reconstruct(receipt)

    def test_nonfinite_displacement_cannot_be_reconciled(self):
        receipt = self.receipt()
        receipt["last_motion"][0] = float("nan")
        with self.assertRaisesRegex(ValueError, "finite"):
            reconstruct(receipt)

    def test_capture_endpoint_must_match_observed_stage(self):
        receipt = self.receipt()
        receipt["stage"] = "before_snap"
        frame: dict[str, Any] = dict(
            slide_path=receipt,
            stages=[dict(stage="snap", before=dict(position=[1, 0, -2]))],
        )
        check_anchor(frame)
        frame["stages"][0]["before"]["position"][0] += 1
        with self.assertRaisesRegex(ValueError, "endpoint"):
            check_anchor(frame)

    def test_airborne_origin_is_bound_to_previous_physics_endpoint(self):
        receipt = self.receipt()
        receipt["stage"] = "before_camera"
        frame = dict(slide_path=receipt, stages=[], position=receipt["end"])
        check_anchor(frame, [0, 0, 0])
        with self.assertRaisesRegex(ValueError, "previous physics endpoint"):
            check_anchor(frame, [1, 0, 0])

    def test_native_diagonal_wall_and_terminal_collision(self):
        paths = [
            os.environ.get("GODOT_EXE", ""),
            os.environ.get("GODOT_BIN", ""),
            "D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe",
        ]
        executable = next(
            (str((ROOT / p).resolve()) for p in paths if p and (ROOT / p).is_file()),
            None,
        )
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
                "tools/authoring/test_slide_path_receipt.gd",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=45,
        )
        output = result.stdout + "\n" + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("SLIDE_PATH_RECEIPT_OK checks=8", output)
        self.assertNotIn("SCRIPT ERROR:", output)
        self.assertNotIn("\nERROR:", output)


if __name__ == "__main__":
    unittest.main()
