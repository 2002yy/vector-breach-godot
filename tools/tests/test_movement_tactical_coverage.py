"""Guard against false jump coverage and misbound candidate inputs."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import sha
from native_jump_candidates import RUNTIME
from tactical_jump_coverage import classify, inventory, manifest_payload


class TacticalCoverageTests(unittest.TestCase):
    def test_clear_jump_and_negative_controls_qualify(self):
        self.assertEqual(
            classify(
                {60: (True, False), 120: (True, False)},
                {60: True, 120: True},
                {60: False, 120: False},
            ),
            "qualified_jump",
        )

    def test_walking_is_not_jump_coverage(self):
        self.assertEqual(
            classify(
                {60: (True, False), 120: (True, False)},
                {60: True, 120: True},
                {60: True, 120: True},
            ),
            "walk_only",
        )

    def test_frequency_disagreement_does_not_qualify(self):
        self.assertEqual(
            classify(
                {60: (True, False), 120: (True, False)},
                {60: True, 120: False},
                {60: False, 120: False},
            ),
            "route_unproven",
        )

    def test_blocked_body_does_not_qualify_even_with_claimed_arrival(self):
        self.assertEqual(
            classify(
                {60: (False, True), 120: (False, True)},
                {60: True, 120: True},
                {60: False, 120: False},
            ),
            "blocked_direct_route",
        )

    def test_missing_frequency_rejected(self):
        with self.assertRaises(ValueError):
            classify({60: (True, False)}, {60: True}, {60: False})

    def review(self):
        return {
            "points": [
                dict(map=name, case=kind, status="walk_only")
                for name in ("dust2", "mirage", "inferno")
                for kind in (
                    "ordinary",
                    "edge",
                    "critical_landing",
                    "run_up",
                    "crouch_jump",
                )
            ]
        }

    def test_all_walk_inventory_cannot_hide_category_gaps(self):
        rows = inventory(self.review())
        self.assertFalse(any(r["jump_route_covered"] for r in rows))
        self.assertTrue(all(r["mechanics_or_walk_reference_only"] for r in rows))

    def test_duplicate_category_rejected(self):
        review = self.review()
        review["points"][-1] = copy.deepcopy(review["points"][0])
        with self.assertRaises(ValueError):
            inventory(review)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in (
            *RUNTIME,
            "project.godot",
            "tools/authoring/survey_tactical_jumps.gd",
        ):
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")
        self.parent, self.survey = self.root / "parent.json", self.root / "survey.json"
        self.parent.write_text(json.dumps(dict(level="fixture", identity={})))
        self.payload = dict(
            parent_sha256=sha(self.parent),
            identity={},
            formal_qualification=False,
            survey_sha256=sha(self.root / "tools/authoring/survey_tactical_jumps.gd"),
            cases=[
                dict(
                    id="rise",
                    start=[0, 1, 0],
                    target_feet=[0, 1, -3],
                    target_radius=1.6,
                    target_height_tolerance=0.18,
                    yaw=0,
                    duration=2,
                )
            ],
        )
        self.save()

    def save(self):
        self.survey.write_text(json.dumps(self.payload))

    def test_candidates_preserve_frozen_geometry(self):
        manifest = manifest_payload(self.parent, self.survey, self.root)
        for point in manifest["cases"]:
            for key in (
                "start",
                "target_feet",
                "target_radius",
                "target_height_tolerance",
                "yaw",
                "duration",
            ):
                self.assertEqual(point[key], self.payload["cases"][0][key])
        self.assertEqual(
            {p["trial_mode"] for p in manifest["cases"]}, {"jump", "no_jump", "walk"}
        )
        self.assertFalse(manifest["formal_qualification"])

    def test_walking_control_stands_and_never_jumps(self):
        manifest = manifest_payload(self.parent, self.survey, self.root)
        walking = next(p for p in manifest["cases"] if p["trial_mode"] == "walk")
        self.assertTrue(
            all(
                "Shift" in e["keys"]
                and "Ctrl" not in e["keys"]
                and "Space" not in e["keys"]
                for e in walking["native_timeline"]
            )
        )

    def test_parent_identity_drift_rejected(self):
        self.payload["parent_sha256"] = "changed"
        self.save()
        with self.assertRaises(ValueError):
            manifest_payload(self.parent, self.survey, self.root)

    def test_survey_source_drift_rejected(self):
        (self.root / "tools/authoring/survey_tactical_jumps.gd").write_text("new code")
        with self.assertRaises(ValueError):
            manifest_payload(self.parent, self.survey, self.root)


if __name__ == "__main__":
    unittest.main()
