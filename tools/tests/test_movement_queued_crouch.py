"""Crouch labels cannot replace observed posture, cadence or paired standing controls."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import SCHEMES
from queued_crouch_audit import (
    CADENCE_PROBES,
    PROBES,
    QUEUE_PROBES,
    RUNTIME,
    payload,
    posture,
    profile,
)


class QueuedCrouchTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in {
            *RUNTIME,
            *PROBES,
            *QUEUE_PROBES,
            *CADENCE_PROBES,
            "project.godot",
        }:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        self.point: dict[str, Any] = dict(
            id="original",
            kind="crouch_jump",
            trial_mode="jump",
            scheme="current",
            start=[0, 0.9, 0],
            target_feet=[0, 0, -1],
            yaw=0,
            duration=2,
            target_radius=0.35,
            target_height_tolerance=0.18,
            native_timeline=[
                dict(at=0, keys=["W"], mouse_dx=0),
                dict(at=0.2, keys=["W", "Space", "Ctrl"], mouse_dx=0),
            ],
        )
        self.source: dict[str, Any] = dict(
            schema=4,
            formal_qualification=False,
            level="fixture",
            identity={},
            cases=[dict(copy.deepcopy(self.point), scheme=s, id=s) for s in SCHEMES],
        )
        self.path = self.root / "parent.json"

    def build(self):
        self.path.write_text(json.dumps(self.source), encoding="utf-8")
        return payload(self.path, self.root, self.root / "rejected.json")

    @staticmethod
    def row(crouched=True, airborne=True, requested=True):
        return dict(
            trace=[
                dict(
                    crouching=crouched,
                    capsule_height=1.2 if crouched else 1.8,
                    grounded_after=not airborne,
                    input=dict(crouch=requested),
                )
            ]
        )

    def test_jump_preserves_original_inputs_and_geometry(self):
        data = self.build()
        self.assertEqual(len(data["cases"]), 9)
        for point in data["cases"]:
            for key in (
                "start",
                "target_feet",
                "yaw",
                "duration",
                "target_radius",
                "target_height_tolerance",
            ):
                self.assertEqual(point[key], self.point[key])
            self.assertTrue(point["queued_input"] and point["enforce_cadence"])
            if point["trial_mode"] == "jump":
                self.assertEqual(
                    point["native_timeline"], self.point["native_timeline"]
                )

    def test_no_jump_retains_crouch_walk_removes_crouch(self):
        data = self.build()
        for point in data["cases"]:
            keys = [k for e in point["native_timeline"] for k in e["keys"]]
            if point["trial_mode"] == "no_jump":
                self.assertNotIn("Space", keys)
                self.assertIn("Ctrl", keys)
            if point["trial_mode"] == "walk":
                self.assertNotIn("Space", keys)
                self.assertNotIn("Ctrl", keys)
                self.assertTrue(
                    all("Shift" in e["keys"] for e in point["native_timeline"])
                )

    def test_incomplete_or_duplicate_schemes_rejected(self):
        self.source["cases"][2]["scheme"] = "current"
        with self.assertRaisesRegex(ValueError, "three crouch"):
            self.build()

    def test_different_geometry_between_profiles_rejected(self):
        self.source["cases"][2]["target_radius"] = 1.6
        with self.assertRaisesRegex(ValueError, "geometries"):
            self.build()

    def test_camera_source_rejected(self):
        self.source["camera_only"] = True
        with self.assertRaisesRegex(ValueError, "physical"):
            self.build()

    def test_crouch_label_without_crouch_key_rejected(self):
        self.source["cases"][0]["native_timeline"][1]["keys"].remove("Ctrl")
        with self.assertRaisesRegex(ValueError, "jump/crouch"):
            self.build()

    def test_posture_requires_request_and_actual_air_crouch(self):
        self.assertTrue(posture(self.row())["crouched_in_air"])
        self.assertFalse(posture(self.row(airborne=False))["crouched_in_air"])
        self.assertFalse(posture(self.row(requested=False))["crouched_in_air"])
        self.assertFalse(posture(self.row(crouched=False))["crouched_in_air"])

    def test_wrong_capsule_height_rejected(self):
        row = self.row()
        row["trace"][0]["capsule_height"] = 1.8
        with self.assertRaisesRegex(ValueError, "capsule"):
            posture(row)

    def test_nonfinite_or_boolean_height_rejected(self):
        for value in (float("nan"), float("inf"), True):
            row = self.row()
            row["trace"][0]["capsule_height"] = value
            with self.assertRaisesRegex(ValueError, "capsule"):
                posture(row)

    def fixtures(self):
        data = self.build()
        points = {p["trial_mode"]: p for p in data["cases"] if p["scheme"] == "current"}
        controls = {
            r: {m: self.row(False, False, False) for m in ("no_jump", "walk")}
            for r in (60, 120)
        }
        return points, controls

    def test_changed_control_input_rejected(self):
        points, controls = self.fixtures()
        points["walk"]["native_timeline"][0]["at"] = 0.1
        with self.assertRaisesRegex(ValueError, "controls must match"):
            profile(points["jump"], {}, points, controls, {})

    def test_crouched_walk_cannot_be_standing_control(self):
        points, controls = self.fixtures()
        controls[60]["walk"] = self.row()
        with self.assertRaisesRegex(ValueError, "remain standing"):
            profile(
                points["jump"], {r: self.row() for r in (60, 120)}, points, controls, {}
            )

    def test_real_takeoff_without_air_crouch_does_not_qualify_category(self):
        points, controls = self.fixtures()
        with (
            patch(
                "queued_crouch_audit.action_gate",
                side_effect=lambda *_: dict(passed=True),
            ),
            patch(
                "queued_crouch_audit.outcomes",
                return_value=dict(first_landing=True, supported_arrival=False),
            ),
            patch("queued_crouch_audit.clear_corridor", return_value=(True, False)),
        ):
            result = profile(
                points["jump"],
                {r: self.row(False, True, False) for r in (60, 120)},
                points,
                controls,
                {60: {}, 120: {}},
            )
        self.assertFalse(result["category_action_passed"])
        self.assertFalse(result["jump_route_passed"])


if __name__ == "__main__":
    unittest.main()
