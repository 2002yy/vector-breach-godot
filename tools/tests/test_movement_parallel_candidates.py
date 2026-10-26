"""Candidate inputs preserve controls; position factors and displacement attribution stay separate."""

import copy
import json
import math
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crouch_position_components import payload as component_payload
from modern_ground_quadrature import (
    PROBES,
    check_cache_receipt,
    payload,
    runup_decomposition,
)


class ParallelCandidateTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in PROBES:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture")

    def source(self, camera=False) -> tuple[Path, dict[str, Any]]:
        data = dict(
            schema=4,
            formal_qualification=False,
            camera_only=camera,
            cases=[
                dict(
                    id="original_" + mode,
                    scheme="modern_cs",
                    trial_mode=mode,
                    native_timeline=[dict(at=0, keys=["W"])],
                    probe_sha256={},
                )
                for mode in ("jump", "no_jump", "walk")
            ],
        )
        path = self.root / "source.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path, data

    def test_candidate_is_explicit_and_keeps_baseline(self):
        path, data = self.source()
        result = payload(path, self.root, self.root / "rejected.json")
        self.assertEqual(len(result["cases"]), 6)
        self.assertEqual(sum(p["quadrature_enabled"] for p in result["cases"]), 3)
        self.assertFalse(result["formal_qualification"])
        self.assertEqual(json.loads(path.read_text()), data)

    def test_all_three_control_input_timelines_are_unchanged(self):
        path, data = self.source()
        result = payload(path, self.root, self.root / "rejected.json")
        for p in result["cases"]:
            original = next(o for o in data["cases"] if o["id"] == p["source_case"])
            self.assertEqual(p["native_timeline"], original["native_timeline"])
            self.assertEqual(set(p["probe_sha256"]), {"res://" + f for f in PROBES})

    def test_camera_or_missing_control_cannot_be_parent(self):
        path, data = self.source(True)
        with self.assertRaisesRegex(ValueError, "physical"):
            payload(path, self.root, self.root / "r.json")
        data["camera_only"] = False
        data["cases"].pop()
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "controls"):
            payload(path, self.root, self.root / "r.json")

    def test_horizontal_and_height_factors_do_not_change_velocity_sources(self):
        original = dict(
            states={
                "60": dict(position=[1, 2, 3], velocity=[4, 5, 6]),
                "120": dict(position=[11, 12, 13], velocity=[14, 15, 16]),
            }
        )
        before = copy.deepcopy(original)
        with patch(
            "crouch_position_components.original_payload", return_value=original
        ):
            result = component_payload(Path("fixture"), self.root)
        self.assertEqual(len(result["cases"]), 8)
        point = next(p for p in result["cases"] if p["id"] == "h60_y120_v60")
        self.assertEqual(point["position"], [1, 12, 3])
        self.assertEqual(point["velocity"], [4, 5, 6])
        self.assertEqual(original, before)

    @staticmethod
    def rows():
        return {
            60: dict(
                trace=[
                    dict(
                        time=0,
                        velocity=[-2, 0, 0],
                        position=[-2 / 60, 0, 0],
                        jumped=False,
                    ),
                    dict(time=1 / 60, jumped=True),
                ]
            ),
            120: dict(
                trace=[
                    dict(
                        time=0,
                        velocity=[-1, 0, 0],
                        position=[-1 / 120, 0, 0],
                        jumped=False,
                    ),
                    dict(
                        time=1 / 120,
                        velocity=[-2, 0, 0],
                        position=[-3 / 120, 0, 0],
                        jumped=False,
                    ),
                    dict(time=2 / 120, jumped=True),
                ]
            ),
        }

    def test_known_end_velocity_quadrature_displacement_attribution(self):
        result = runup_decomposition(dict(yaw=math.pi / 2), self.rows())
        self.assertAlmostEqual(result["end_velocity_rule_contribution_m"], 0)
        self.assertAlmostEqual(
            result["displacement_quadrature_contribution_m"], 1 / 120
        )
        self.assertAlmostEqual(result["actual_position_delta_m"], 1 / 120)
        self.assertAlmostEqual(result["residual_m"], 0)

    def test_noncommon_runup_boundary_rejected(self):
        rows = self.rows()
        rows[60]["trace"][1]["time"] = 0.01
        with self.assertRaisesRegex(ValueError, "boundary"):
            runup_decomposition(dict(yaw=0), rows)

    def test_changed_collision_velocity_must_discard_endpoint(self):
        trace = [
            dict(
                velocity=[0.1, 0, 0],
                quadrature=dict(
                    substeps=2,
                    motion_velocity=[1, 0, 0],
                    restored=False,
                    cache_discarded=False,
                ),
            ),
            dict(
                velocity=[0.1, 0, 0],
                quadrature=dict(substeps=0, restored=False, cache_discarded=True),
            ),
        ]
        check_cache_receipt(trace)
        trace[1]["quadrature"]["restored"] = True
        with self.assertRaisesRegex(ValueError, "stale endpoint"):
            check_cache_receipt(trace)

    def test_unchanged_motion_restores_endpoint_on_takeoff(self):
        trace = [
            dict(
                velocity=[1, 0, 0],
                quadrature=dict(
                    substeps=2,
                    motion_velocity=[1, 0, 0],
                    restored=False,
                    cache_discarded=False,
                ),
            ),
            dict(
                velocity=[1, 2, 0],
                quadrature=dict(substeps=0, restored=True, cache_discarded=False),
            ),
        ]
        check_cache_receipt(trace)


if __name__ == "__main__":
    unittest.main()
