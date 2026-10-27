"""Complete observed body segments are required before any clearance statement."""

import copy
import os
from pathlib import Path
import subprocess
import sys
import unittest
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from observed_inferno_corridor import IDS, check_result_ids, check_segments, poses


class ObservedInfernoTests(unittest.TestCase):
    def test_duplicate_extra_result_is_rejected(self):
        report = dict(results=[dict(id=key) for key in IDS])
        check_result_ids(report)
        report["results"].append(dict(id=IDS[0]))
        with self.assertRaisesRegex(ValueError, "count differs"):
            check_result_ids(report)

    @staticmethod
    def trace() -> dict[str, Any]:
        rows = [
            dict(
                time=i / 60,
                position=[0, i, 0],
                capsule_height=1.8,
                jumped=i == 1,
                grounded_after=i != 1,
                stages=[],
            )
            for i in range(3)
        ]
        return dict(trace=rows, landing=rows[-1])

    def test_previous_and_first_landing_pose_are_kept(self):
        path = poses(self.trace())
        self.assertEqual(path[0]["label"], "before_takeoff")
        self.assertEqual(path[-1]["position"], [0, 2, 0])

    def test_initial_pose_missing_is_rejected(self):
        row = self.trace()
        row["trace"][0]["jumped"] = True
        row["trace"][1]["jumped"] = False
        with self.assertRaisesRegex(ValueError, "previous pose"):
            poses(row)

    def test_stage_teleports_are_swept_not_skipped(self):
        row = self.trace()
        row["trace"][1]["stages"] = [
            dict(
                stage="pre_step",
                before=dict(position=[0, 0, 0]),
                after=dict(position=[0, 0.4, 0]),
            )
        ]
        path = poses(row)
        self.assertIn([0, 0.4, 0], [p["position"] for p in path])

    def test_missing_initial_or_final_segment_rejected(self):
        case = dict(poses=poses(self.trace()))
        segment = dict(
            initial_overlaps=0,
            endpoint_overlaps=0,
            free_fraction=1,
            clear=True,
            height=1.8,
            height_transition=False,
        )
        rows: dict[str, Any] = dict(
            clear=True,
            segments=[
                dict(segment, **{"from": a["position"], "to": b["position"]})
                for a, b in zip(case["poses"], case["poses"][1:])
            ],
        )
        self.assertTrue(check_segments(case, rows))
        for index in (0, -1):
            bad = copy.deepcopy(rows)
            bad["segments"].pop(index)
            with self.assertRaisesRegex(ValueError, "complete segment"):
                check_segments(case, bad)

    def test_height_transition_cannot_claim_clearance(self):
        case = dict(
            poses=[
                dict(position=[0, 1, 0], height=1.8),
                dict(position=[0, 2, 0], height=1.2),
            ]
        )
        row = dict(
            clear=True,
            segments=[
                dict(
                    initial_overlaps=0,
                    endpoint_overlaps=0,
                    free_fraction=1,
                    clear=True,
                    height=1.8,
                    height_transition=True,
                    **{"from": [0, 1, 0], "to": [0, 2, 0]},
                )
            ],
        )
        with self.assertRaisesRegex(ValueError, "clearance differs"):
            check_segments(case, row)

    def test_forged_capsule_height_is_rejected(self):
        case = dict(
            poses=[
                dict(position=[0, 1, 0], height=1.8),
                dict(position=[0, 2, 0], height=1.8),
            ]
        )
        row = dict(
            clear=True,
            segments=[
                dict(
                    initial_overlaps=0,
                    endpoint_overlaps=0,
                    free_fraction=1,
                    clear=True,
                    height=1.2,
                    height_transition=False,
                    **{"from": [0, 1, 0], "to": [0, 2, 0]},
                )
            ],
        )
        with self.assertRaisesRegex(ValueError, "dimensions differ"):
            check_segments(case, row)

    def test_native_full_capsule_wall_support_and_height(self):
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
        if not executable:
            self.skipTest("Godot unavailable")
        result = subprocess.run(
            [
                executable,
                "--headless",
                "--path",
                str(ROOT),
                "--quit-after",
                "120",
                "-s",
                "tools/authoring/test_observed_path_sweep.gd",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("OBSERVED_PATH_SWEEP_OK checks=5", output)
        self.assertNotIn("SCRIPT ERROR", output)


if __name__ == "__main__":
    unittest.main()
