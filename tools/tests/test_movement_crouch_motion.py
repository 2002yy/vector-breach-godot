"""Factorial query receipts cannot hide overlap, truncated motion or ambiguous faces."""

import copy
import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crouch_motion_factorial import (
    END,
    GRAVITY,
    build_cases,
    state,
    validate,
    validate_faces,
)


class CrouchMotionTests(unittest.TestCase):
    def setUp(self):
        states = {
            60: dict(position=[0, 3, 0], velocity=[1, 1, 0]),
            120: dict(position=[0.01, 3, 0], velocity=[1, 0.9, 0]),
        }
        self.matrix: dict[str, Any] = dict(
            file_sha256="matrix",
            identity={},
            probe_sha256="probe",
            gravity=GRAVITY,
            cases=build_cases(states),
            scope="fixture",
        )
        rows = []
        for p in self.matrix["cases"]:
            steps = []
            position = list(p["position"])
            velocity = list(p["velocity"])
            for dt in p["steps"]:
                velocity[1] -= GRAVITY * dt
                motion = [v * dt for v in velocity]
                steps.append(
                    dict(
                        delta=dt,
                        from_=position,
                        motion=motion,
                        hit=False,
                        safe_fraction=1,
                        unsafe_fraction=1,
                        contacts=[],
                    )
                )
                steps[-1]["from"] = steps[-1].pop("from_")
                position = [a + b for a, b in zip(position, motion)]
            rows.append(
                dict(
                    id=p["id"],
                    initial_overlaps=[],
                    body_origin_unchanged=True,
                    steps=steps,
                )
            )
        self.report: dict[str, Any] = dict(
            schema=1,
            matrix_sha256="matrix",
            identity={},
            probe_sha256="probe",
            safe_margin=0.001,
            results=rows,
            original_contact_face=dict(matched=False),
        )

    def test_factor_grid_keeps_position_velocity_and_steps_independent(self):
        cases = self.matrix["cases"]
        self.assertEqual(
            len(
                {
                    (p["position_rate"], p["velocity_rate"], tuple(p["steps"]))
                    for p in cases
                }
            ),
            8,
        )
        self.assertTrue(all(abs(sum(p["steps"]) - 1 / 60) < 1e-10 for p in cases))
        self.assertTrue(
            all(p["position"] == [0, 3, 0] for p in cases if p["position_rate"] == 60)
        )

    def test_common_end_state_uses_after_physics_time(self):
        row = dict(
            trace=[
                dict(
                    time=END - 1 / 120,
                    grounded_after=False,
                    crouching=True,
                    capsule_height=1.2,
                    position=[0, 0, 0],
                    velocity=[1, 1, 0],
                )
            ]
        )
        result = state(row, 120)
        self.assertEqual(result["state_end_seconds"], END)
        with self.assertRaisesRegex(ValueError, "common physics"):
            state(row, 60)

    def test_grounded_state_cannot_replace_airborne_boundary(self):
        row = dict(
            trace=[
                dict(
                    time=END - 1 / 60,
                    grounded_after=True,
                    crouching=True,
                    capsule_height=1.2,
                )
            ]
        )
        with self.assertRaisesRegex(ValueError, "airborne"):
            state(row, 60)

    def test_clear_full_grid_stays_nonrelease(self):
        result = validate(self.matrix, self.report)
        self.assertFalse(result["formal_release_ready"])
        self.assertFalse(result["collision_fixed"])

    def test_overlap_or_body_mutation_rejected(self):
        for field, value in (
            ("initial_overlaps", ["wall"]),
            ("body_origin_unchanged", False),
        ):
            report = copy.deepcopy(self.report)
            report["results"][0][field] = value
            with self.assertRaises(ValueError):
                validate(self.matrix, report)

    def test_incomplete_factor_grid_rejected(self):
        self.report["results"].pop()
        with self.assertRaisesRegex(ValueError, "coverage"):
            validate(self.matrix, self.report)

    def test_clear_split_cannot_stop_after_first_half(self):
        self.report["results"][1]["steps"].pop()
        with self.assertRaisesRegex(ValueError, "before horizon"):
            validate(self.matrix, self.report)

    def test_path_or_margin_cannot_change(self):
        self.report["results"][0]["steps"][0]["motion"][0] = 100
        with self.assertRaisesRegex(ValueError, "frozen integration"):
            validate(self.matrix, self.report)
        self.report["safe_margin"] = 0.01
        with self.assertRaisesRegex(ValueError, "margin"):
            validate(self.matrix, self.report)

    def test_scope_hash_mismatch_rejected(self):
        self.report["probe_sha256"] = "other"
        with self.assertRaisesRegex(ValueError, "scope"):
            validate(self.matrix, self.report)

    @staticmethod
    def face() -> dict[str, Any]:
        return dict(
            shape_triangles=dict(
                bound=True,
                shape_faces_sha256="a" * 64,
                triangle_count=2,
                unique=False,
                candidates=[
                    dict(
                        triangle_index=i,
                        normal=[1, 0, 0],
                        distance_m=0.0001,
                        edge_distance_m=0.0001,
                    )
                    for i in (0, 1)
                ],
            )
        )

    def test_ambiguous_contact_does_not_become_unique_triangle(self):
        ray = self.face()
        validate_faces(ray)
        ray["shape_triangles"]["unique"] = True
        with self.assertRaisesRegex(ValueError, "unique"):
            validate_faces(ray)

    def test_triangle_indices_and_contact_radius_checked(self):
        ray = self.face()
        ray["shape_triangles"]["candidates"][0]["triangle_index"] = 2
        with self.assertRaisesRegex(ValueError, "index"):
            validate_faces(ray)
        ray = self.face()
        ray["shape_triangles"]["candidates"][0]["distance_m"] = 0.01
        with self.assertRaisesRegex(ValueError, "neighborhood"):
            validate_faces(ray)


if __name__ == "__main__":
    unittest.main()
