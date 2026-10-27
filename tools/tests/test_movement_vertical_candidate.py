"""Execute the actual author candidate physics pipeline, including contacts and volumes."""

import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class VerticalCandidateTests(unittest.TestCase):
    def test_native_pipeline_freeflight_jump_contacts_and_environment(self):
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
                "tools/authoring/test_modern_vertical_quadrature.gd",
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
        self.assertIn("MODERN_VERTICAL_QUADRATURE_OK checks=26", output)
        self.assertNotIn("SCRIPT ERROR:", output)
        self.assertNotIn("\nERROR:", output)


if __name__ == "__main__":
    unittest.main()
