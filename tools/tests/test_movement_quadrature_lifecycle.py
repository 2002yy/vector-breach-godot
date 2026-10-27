"""Run native lifecycle transitions in CI and check common-end residual attribution."""

import os
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from modern_quadrature_residual import end_state, observe


class QuadratureLifecycleTests(unittest.TestCase):
    @staticmethod
    def rows():
        rows: dict[int, Any] = {}
        for rate, land_tick in ((60, 24), (120, 45)):
            trace = []
            for i in range(land_tick + 1):
                end = (i + 1) / rate
                trace.append(
                    dict(
                        time=i / rate,
                        position=[2 * end, 1 + 10 * end - 10 * end * end, 0],
                        velocity=[2, 10 - 20 * end, 0],
                        jumped=i == 0,
                        grounded_after=i == land_tick,
                        stages=[],
                        contacts=[],
                    )
                )
            landing = trace[-1]
            landing["contacts"] = [
                dict(
                    body="/root/Session/player_collision/Group/RuntimeCollision",
                    normal=[0, 1, 0],
                    position=[0, 0, 0],
                )
            ]
            rows[rate] = dict(trace=trace, landing=landing)
        return rows

    def test_same_horizontal_speed_explains_different_landing_endpoints(self):
        result = observe(self.rows())
        self.assertTrue(result["same_air_speed"])
        self.assertAlmostEqual(result["horizontal_residual_m"], 0)
        self.assertAlmostEqual(
            result["same_speed_time_contribution_m"], 2 * (25 / 60 - 46 / 120)
        )
        self.assertFalse(result["precision_equivalence_accepted"])

    def test_common_end_state_is_not_same_start_tick(self):
        rows = self.rows()
        left = end_state(rows[60], 60, 0.1)
        right = end_state(rows[120], 120, 0.1)
        self.assertNotEqual(left["time"], right["time"])
        self.assertEqual(left["position"], right["position"])
        with self.assertRaisesRegex(ValueError, "endpoint"):
            end_state(rows[60], 60, 0.101)

    def test_missing_or_different_jump_request_rejected(self):
        rows = self.rows()
        rows[120]["trace"][0]["jumped"] = False
        with self.assertRaisesRegex(ValueError, "single jump"):
            observe(rows)

    def test_equal_speed_turn_rejects_scalar_time_attribution(self):
        rows = self.rows()
        rows[120]["trace"][1]["velocity"] = [0, 9, 2]
        with self.assertRaisesRegex(ValueError, "constant horizontal velocity"):
            observe(rows)

    def test_native_lifecycle_resets_without_intermediate_simulation(self):
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
            self.skipTest("Godot runtime unavailable; CI supplies GODOT_BIN")
        result = subprocess.run(
            [
                executable,
                "--headless",
                "--path",
                str(ROOT),
                "--quit-after",
                "120",
                "-s",
                "tools/authoring/test_modern_quadrature_lifecycle.gd",
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
        self.assertIn("MODERN_QUADRATURE_LIFECYCLE_OK checks=22", output)
        self.assertNotIn("SCRIPT ERROR:", output)
        self.assertNotIn("\nERROR:", output)


if __name__ == "__main__":
    unittest.main()
