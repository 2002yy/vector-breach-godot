"""Contact localization must respect step-end time, raw normals and immutable inputs."""

import copy
import json
import math
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crouch_frequency_contact import (
    CASE,
    GRAVITY,
    VARIANTS,
    aligned_end_states,
    first_air_contact,
    identical_prefix,
    payload,
)


class ContactFrequencyTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    @staticmethod
    def trace(rate=60, lateral=True) -> dict[str, Any]:
        normal = [0.9925, 0.12222, 0]
        norm = math.sqrt(sum(v * v for v in normal))
        normal = [v / norm for v in normal] if lateral else [0, 1, 0]
        incoming = [-2, 2 - GRAVITY / rate, 0]
        dot = sum(a * b for a, b in zip(incoming, normal))
        outgoing = [v - n * min(dot, 0) for v, n in zip(incoming, normal)]
        sample = dict(
            time=0,
            position=[0, 0, 0],
            velocity=[-2, 2, 0],
            jumped=True,
            grounded_before=True,
            grounded_after=False,
            stages=[],
            contacts=[],
        )
        contact = dict(
            body="/root/Session/collision_root/clip/RuntimeCollision", normal=normal
        )
        hit = dict(
            sample,
            time=1 / rate,
            jumped=False,
            grounded_before=False,
            velocity=[outgoing[0], incoming[1], outgoing[2]],
            contacts=[contact],
        )
        land = dict(
            sample,
            time=2 / rate,
            jumped=False,
            grounded_before=False,
            grounded_after=True,
        )
        return dict(trace=[sample, hit, land], landing=land)

    def test_projection_matches_recorded_horizontal_velocity(self):
        result = first_air_contact(self.trace(), 60, "collision_root")
        self.assertTrue(result["observed"])
        self.assertLess(result["contact_projection_horizontal_error_mps"], 1e-10)
        self.assertLess(
            result["outgoing_horizontal_mps"], result["incoming_horizontal_mps"]
        )
        self.assertEqual(result["tick_start_seconds"], 1 / 60)
        self.assertEqual(result["physics_interval_end_seconds"], 2 / 60)

    def test_floor_contact_is_not_lateral_obstruction(self):
        self.assertFalse(
            first_air_contact(self.trace(lateral=False), 60, "collision_root")[
                "observed"
            ]
        )

    def test_contacts_after_first_landing_do_not_explain_jump(self):
        row = self.trace()
        row["landing"] = row["trace"][0]
        self.assertFalse(first_air_contact(row, 60, "collision_root")["observed"])

    def test_wrong_root_rejected(self):
        with self.assertRaisesRegex(ValueError, "frozen collision root"):
            first_air_contact(self.trace(), 60, "other_root")

    def test_nonunit_or_nonfinite_contact_normal_rejected(self):
        for normal in ([2, 0, 0], [float("nan"), 1, 0]):
            row = self.trace()
            row["trace"][1]["contacts"][0]["normal"] = normal
            with self.assertRaisesRegex(ValueError, "normal"):
                first_air_contact(row, 60, "collision_root")

    def test_multiple_takeoffs_rejected(self):
        row = self.trace()
        row["trace"][1]["jumped"] = True
        with self.assertRaisesRegex(ValueError, "single actual"):
            first_air_contact(row, 60, "collision_root")

    def test_alignment_uses_second_120_sample_at_same_step_end(self):
        def sample(t, p):
            return dict(time=t, position=[p, 0, 0], velocity=[1, 0, 0])

        left = [sample(0, 2), sample(1 / 60, 4)]
        right = [sample(i / 120, i + 1) for i in range(4)]
        result = aligned_end_states(left, right)
        self.assertEqual([r["position_delta_m"] for r in result], [0, 0])
        self.assertEqual([r["end_seconds"] for r in result], [1 / 60, 2 / 60])

    def test_incomplete_or_shifted_clock_alignment_rejected(self):
        row = self.trace()["trace"][:1]
        with self.assertRaisesRegex(ValueError, "lengths"):
            aligned_end_states(row, row)
        right = copy.deepcopy(row) * 2
        with self.assertRaisesRegex(ValueError, "endpoints"):
            aligned_end_states(row, right)

    def test_prefix_checks_physics_before_selected_event(self):
        row = self.trace()
        for s in row["trace"]:
            s.update(input={}, speed_limit=1, crouching=True, capsule_height=1.2)
        other = copy.deepcopy(row)
        other["trace"][2]["position"] = [5, 0, 0]
        self.assertTrue(identical_prefix(row, other, 1 / 60))
        self.assertFalse(identical_prefix(row, other, 2 / 60))

    def source(self, camera=False) -> tuple[Path, dict[str, Any]]:
        point = dict(
            id=CASE,
            scheme="modern_cs",
            trial_mode="jump",
            queued_input=True,
            kind="crouch_jump",
            ablation="baseline",
            native_timeline=[dict(at=0, keys=["W"])],
        )
        data = dict(
            level="inferno-classic-local",
            schema=4,
            formal_qualification=False,
            camera_only=camera,
            cases=[point],
        )
        path = self.root / "source.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path, data

    def test_ablation_keeps_all_input_and_geometry_fields(self):
        path, data = self.source()
        result = payload(path, self.root / "rejected.json")
        self.assertEqual(tuple(p["ablation"] for p in result["cases"]), VARIANTS)
        for point in result["cases"]:
            self.assertEqual(
                point["native_timeline"], data["cases"][0]["native_timeline"]
            )
            self.assertEqual(point["source_case"], CASE)
        self.assertEqual(json.loads(path.read_text()), data)

    def test_camera_source_cannot_be_physical_parent(self):
        path, _ = self.source(True)
        with self.assertRaisesRegex(ValueError, "parent"):
            payload(path, self.root / "rejected.json")


if __name__ == "__main__":
    unittest.main()
