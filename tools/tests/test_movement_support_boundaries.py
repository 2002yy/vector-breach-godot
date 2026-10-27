"""Real tiny-world support regressions included by CI's test_m*.py discovery."""

import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SupportBoundaryTests(unittest.TestCase):
    def test_real_steep_pose_lifecycle_and_environment_boundaries(self):
        candidates = [
            os.environ.get("GODOT_EXE", ""),
            os.environ.get("GODOT_BIN", ""),
            "D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe",
        ]
        executable = next(
            (
                str((ROOT / p).resolve())
                for p in candidates
                if p and (ROOT / p).is_file()
            ),
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
                "1000",
                "-s",
                "tools/authoring/test_support_boundaries.gd",
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
        self.assertIn("SUPPORT_BOUNDARIES_OK checks=124", output)
        self.assertNotIn("SCRIPT ERROR:", output)
        self.assertNotIn("\nERROR:", output)


if __name__ == "__main__":
    unittest.main()
