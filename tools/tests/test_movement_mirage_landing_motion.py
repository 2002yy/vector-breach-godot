"""Check common-state identity and midpoint/snap receipts without map replays."""

import copy
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mirage_landing_motion import END, build_cases, payload, state, validate


class MirageLandingMotionTests(unittest.TestCase):
    def fixture(self):
        states = {r: dict(position=[0, 2, 0], velocity=[0, -4, -2]) for r in (60, 120)}
        matrix: dict[str, Any] = dict(
            cases=build_cases(states),
            gravity=20.32,
            file_sha256="matrix",
            probe_sha256="probe",
            identity={},
            scope="test_only_query",
        )
        rows = []
        for point in matrix["cases"]:
            position, velocity = list(point["position"]), list(point["velocity"])
            steps = []
            for dt in point["steps"]:
                velocity[1] -= matrix["gravity"] * dt / 2
                motion = [v * dt for v in velocity]
                steps.append(
                    dict(
                        delta=dt,
                        **{"from": list(position)},
                        motion=motion,
                        hit=False,
                        safe_fraction=1,
                        unsafe_fraction=1,
                        contacts=[],
                        snap_query=dict(
                            ray_hit=True,
                            eligible=True,
                            gap_m=0.425,
                            normal=[0, 1, 0],
                            body="player_collision/floor/RuntimeCollision",
                        ),
                    )
                )
                position = [a + b for a, b in zip(position, motion)]
                velocity[1] -= matrix["gravity"] * dt / 2
            rows.append(
                dict(
                    id=point["id"],
                    steps=steps,
                    initial_overlaps=[],
                    body_origin_unchanged=True,
                )
            )
        report: dict[str, Any] = dict(
            schema=1,
            matrix_sha256="matrix",
            probe_sha256="probe",
            identity={},
            safe_margin=0.001,
            results=rows,
            original_contact_face={},
        )
        return matrix, report

    def test_common_endpoint_not_tick_start(self):
        row = dict(
            trace=[
                dict(
                    time=END - 1 / 120,
                    grounded_after=False,
                    crouching=True,
                    capsule_height=1.2,
                    position=[0, 2, 0],
                    velocity=[0, -4, 0],
                )
            ]
        )
        self.assertEqual(state(row, 120)["state_end_seconds"], END)
        with self.assertRaisesRegex(ValueError, "state missing"):
            state(row, 60)

    def test_grounded_state_rejected(self):
        row: dict[str, Any] = dict(
            trace=[
                dict(
                    time=END - 1 / 60,
                    grounded_after=True,
                    crouching=True,
                    capsule_height=1.2,
                    position=[0, 2, 0],
                    velocity=[0, -4, 0],
                )
            ]
        )
        with self.assertRaisesRegex(ValueError, "airborne"):
            state(row, 60)
        row["trace"][0]["grounded_after"] = False
        row["trace"][0]["velocity"][1] = 0
        with self.assertRaisesRegex(ValueError, "descending"):
            state(row, 60)

    def test_wrong_map_and_disabled_candidate_rejected(self):
        with patch(
            "mirage_landing_motion.read",
            return_value=dict(level="inferno", schema=4, formal_qualification=False),
        ):
            with self.assertRaisesRegex(ValueError, "wrong physical map"):
                payload(Path("unused"), Path("unused"))
        with (
            patch(
                "mirage_landing_motion.read",
                return_value=dict(
                    level="mirage-classic-local", schema=4, formal_qualification=False
                ),
            ),
            patch(
                "mirage_landing_motion.checked",
                return_value=(
                    {
                        "vertical__jump": dict(
                            vertical_enabled=False,
                            quadrature_enabled=True,
                            scheme="modern_cs",
                        )
                    },
                    {},
                ),
            ),
        ):
            with self.assertRaisesRegex(ValueError, "vertical Modern"):
                payload(Path("unused"), Path("unused"))

    def test_midpoint_receipts_and_snap_choices_verified(self):
        matrix, report = self.fixture()
        self.assertEqual(validate(matrix, report)["queries"], 8)

    def test_endpoint_gravity_cannot_replace_midpoint(self):
        matrix, report = self.fixture()
        report["results"][0]["steps"][0]["motion"][1] -= 0.01
        with self.assertRaisesRegex(ValueError, "midpoint"):
            validate(matrix, report)

    def test_overlap_and_body_movement_rejected(self):
        matrix, report = self.fixture()
        for key, value in (
            ("initial_overlaps", ["floor"]),
            ("body_origin_unchanged", False),
        ):
            mutated = copy.deepcopy(report)
            mutated["results"][0][key] = value
            with (
                self.subTest(key=key),
                self.assertRaisesRegex(ValueError, "overlap or body"),
            ):
                validate(matrix, mutated)

    def test_missing_steps_and_forged_snap_rejected(self):
        matrix, report = self.fixture()
        missing = copy.deepcopy(report)
        missing["results"][0]["steps"] = []
        with self.assertRaisesRegex(ValueError, "step count"):
            validate(matrix, missing)
        report["results"][0]["steps"][0]["snap_query"]["eligible"] = False
        with self.assertRaisesRegex(ValueError, "snap eligibility"):
            validate(matrix, report)


if __name__ == "__main__":
    unittest.main()
