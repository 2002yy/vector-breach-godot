"""Short braking must preserve takeoff and bind contacts to original collision."""

import copy
import json
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_edge_landing as fixtures
from modern_brake_window import (
    TICKS,
    contact_proof,
    floor_contacts,
    payload,
    relative_body,
    short_timeline,
)


class ModernBrakeTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.EdgeLandingTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        parent = self.fixture.build()
        for point in parent["cases"]:
            point.update(target_radius=1.6, target_height_tolerance=0.18)
        self.path = self.root / "r18.json"
        self.path.write_text(json.dumps(parent))
        self.points = {p["id"]: p for p in parent["cases"]}
        self.rows = {k: self.contact_row() for k in self.points}
        for name in ("r18-60.json", "r18-120.json"):
            (self.root / name).write_text("{}")
        self.source = dict(
            manifest=str(self.path),
            report60=str(self.root / "r18-60.json"),
            report120=str(self.root / "r18-120.json"),
        )

    def contact_row(self) -> dict[str, Any]:
        return dict(
            settled_start=[0, 1.9, 0],
            landing=dict(
                grounded_after=True,
                contacts=[
                    dict(
                        body="/root/@Node3D@7/map/mesh/RuntimeCollision",
                        normal=[0, 1, 0],
                        position=[0, 1, 0],
                    )
                ],
            ),
        )

    def build(self, takeoff=True):
        with (
            patch("modern_brake_window.checked", return_value=(self.points, self.rows)),
            patch("modern_brake_window.action_gate", return_value=dict(passed=takeoff)),
        ):
            return payload("dust2", self.source, self.root, self.root / "reject.json")

    def test_seven_modern_only_cases_and_short_durations(self):
        points = self.build()["cases"]
        self.assertEqual(len(points), 7)
        self.assertEqual({p["scheme"] for p in points}, {"modern_cs"})
        self.assertEqual(
            {
                p["reverse_reference_ticks"]
                for p in points
                if "reverse_reference_ticks" in p
            },
            set(TICKS),
        )
        for point in points:
            if "reverse_reference_ticks" in point:
                events = point["native_timeline"]
                self.assertEqual(events[2]["keys"], ["S"])
                self.assertEqual(events[3]["keys"], [])
                self.assertAlmostEqual(
                    events[3]["at"] - events[2]["at"],
                    point["reverse_reference_ticks"] / 60,
                )
                self.assertLess(events[3]["at"] - events[2]["at"], 0.1)

    def test_original_goals_controls_and_input_prefix_stay_exact(self):
        before = copy.deepcopy(self.points)
        for point in self.build()["cases"]:
            original = self.points[point["source_case"]]
            for field in (
                "start",
                "target_feet",
                "target_radius",
                "target_height_tolerance",
                "yaw",
                "geometry",
            ):
                self.assertEqual(point[field], original[field])
            self.assertEqual(
                point["native_timeline"][:2], original["native_timeline"][:2]
            )
            if point["air_control_variant"] in ("baseline", "reverse_010"):
                self.assertEqual(point["native_timeline"], original["native_timeline"])
        self.assertEqual(self.points, before)

    def test_unknown_duration_is_rejected(self):
        for ticks in (0, 6, True, 0.5):
            with self.assertRaisesRegex(ValueError, "unfrozen reverse duration"):
                short_timeline({}, ticks)

    def test_parent_or_probe_drift_is_rejected(self):
        (self.root / "probe.gd").write_text("changed")
        with self.assertRaisesRegex(ValueError, "author probe drift"):
            self.build()
        parent = json.loads(self.path.read_text())
        parent["stage"] = "unfrozen"
        self.path.write_text(json.dumps(parent))
        with self.assertRaisesRegex(ValueError, "wrong braking parent"):
            self.build()

    def test_controls_without_real_takeoff_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "controls require real takeoff"):
            self.build(False)

    def test_old120_outcomes_do_not_choose_short_inputs(self):
        before = self.build()
        (self.root / "r18-120.json").write_text('{"different":"outcomes"}')
        after = self.build()
        self.assertEqual(before["cases"], after["cases"])
        self.assertNotEqual(
            before["source_report120_sha256"], after["source_report120_sha256"]
        )

    def proof_point(self):
        return dict(
            original_collision_roots=["map"],
            target_feet=[0, 0, 0],
            target_height_tolerance=0.18,
        )

    def test_contact_group_height_and_normal_are_reported(self):
        result = contact_proof(self.proof_point(), self.contact_row())
        self.assertEqual(result["bodies"], ["map/mesh/RuntimeCollision"])
        self.assertEqual(result["minimum_normal_y"], 1)
        self.assertEqual(result["target_plane_error_m"], 1)
        self.assertTrue(result["matches_initial_height"])
        self.assertFalse(result["within_target_height"])

    def test_helper_or_foreign_root_cannot_become_map_contact(self):
        point = self.proof_point()
        point["original_collision_roots"] = ["different-map"]
        with self.assertRaisesRegex(ValueError, "outside original collision root"):
            contact_proof(point, self.contact_row())

    def test_dynamic_instance_prefix_is_not_part_of_collision_identity(self):
        self.assertEqual(
            relative_body("/root/@Node3D@99/map/mesh/RuntimeCollision"),
            relative_body("/root/@Node3D@7/map/mesh/RuntimeCollision"),
        )
        for body in (
            "map/mesh/RuntimeCollision",
            "/root/node/map/../RuntimeCollision",
            "/root/node/map/mesh/HelperBody",
        ):
            with self.assertRaises(ValueError):
                relative_body(body)

    def test_nonfinite_or_nonunit_contact_is_rejected(self):
        for field, value in (("normal", [0, 2, 0]), ("position", [0, float("nan"), 0])):
            row = self.contact_row()
            row["landing"]["contacts"][0][field] = value
            with self.assertRaisesRegex(ValueError, "invalid collision contact"):
                floor_contacts(row)

    def test_wall_normal_or_unsupported_landing_is_not_floor_proof(self):
        row = self.contact_row()
        row["landing"]["contacts"][0]["normal"] = [1, 0, 0]
        with self.assertRaisesRegex(ValueError, "no floor normal"):
            floor_contacts(row)
        row = self.contact_row()
        row["landing"]["grounded_after"] = False
        with self.assertRaisesRegex(ValueError, "lacks support"):
            floor_contacts(row)

    def test_missing_landing_does_not_fabricate_contact(self):
        self.assertEqual(contact_proof({}, dict(landing={})), dict(observed=False))

    def test_multiple_heights_are_reported_without_visual_identity_claim(self):
        row = self.contact_row()
        extra = copy.deepcopy(row["landing"]["contacts"][0])
        extra["position"][1] = 1.2
        row["landing"]["contacts"].append(extra)
        result = contact_proof(self.proof_point(), row)
        self.assertAlmostEqual(result["height_span_m"], 0.2)
        self.assertAlmostEqual(result["target_plane_error_m"], 1.1)
        self.assertIn("not_visual_prop", result["scope"])


if __name__ == "__main__":
    unittest.main()
