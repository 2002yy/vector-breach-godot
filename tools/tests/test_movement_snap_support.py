"""Execute the actual author candidate physics pipeline, including contacts and volumes."""

import os
import subprocess
import unittest
import copy
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]


sys.path.insert(0, str(ROOT / "tools"))
from snap_support_candidate import check_receipts


class SnapSupportCandidateTests(unittest.TestCase):
    def test_native_engine_support_and_landed_event_pipeline(self):
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
                "360",
                "-s",
                "tools/authoring/test_modern_snap_support.gd",
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
        self.assertIn("MODERN_SNAP_SUPPORT_OK checks=28", output)
        self.assertNotIn("SCRIPT ERROR:", output)
        self.assertNotIn("\nERROR:", output)

    @staticmethod
    def rows() -> dict[str, Any]:
        return dict(
            trace=[
                dict(
                    support=dict(enabled=True, attempted=False),
                    grounded_before=False,
                    grounded_after=False,
                    landing_events=0,
                ),
                dict(
                    support=dict(
                        enabled=True,
                        attempted=True,
                        position_before=[0, 1.3, 0],
                        position_after=[0, 0.9, 0],
                        grounded_before=False,
                        grounded_after=True,
                        floor_normal=[0, 1, 0],
                    ),
                    grounded_before=False,
                    grounded_after=True,
                    landing_events=1,
                    position=[0, 0.9, 0],
                ),
                dict(
                    support=dict(enabled=True, attempted=False),
                    grounded_before=True,
                    grounded_after=True,
                    landing_events=1,
                ),
            ]
        )

    def test_real_support_transition_and_single_event_accepted(self):
        check_receipts(self.rows(), True)

    def test_duplicate_or_missing_landed_event_rejected(self):
        for count in (0, 2):
            row = copy.deepcopy(self.rows())
            row["trace"][1]["landing_events"] = count
            with self.assertRaisesRegex(ValueError, "landed event"):
                check_receipts(row, True)

    def test_fake_support_or_nonwalkable_normal_rejected(self):
        for mutation in ("state", "normal", "position"):
            row = copy.deepcopy(self.rows())
            receipt = row["trace"][1]["support"]
            if mutation == "state":
                receipt["grounded_after"] = False
            elif mutation == "normal":
                receipt["floor_normal"] = [1, 0, 0]
            else:
                receipt["position_after"] = receipt["position_before"]
            with self.assertRaises(ValueError):
                check_receipts(row, True)

    def test_support_receipt_is_bound_to_actual_body_position(self):
        row = self.rows()
        row["trace"][1]["position"] = [0, 1.1, 0]
        with self.assertRaisesRegex(ValueError, "actual body position"):
            check_receipts(row, True)


if __name__ == "__main__":
    unittest.main()
