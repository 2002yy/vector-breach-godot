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
from validate_mirage_input_study import PHYSICS_FIELDS
from tactical_jump_coverage import (
    approach_payload,
    classify,
    inventory,
    manifest_payload,
    matrix_payload,
    require_unchanged_current,
)


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

    def source_manifest(self):
        source = self.root / "current-source.json"
        payload = manifest_payload(self.parent, self.survey, self.root)
        for point in payload["cases"]:
            point["geometry"] = {"direction": [0, 0, -1]}
            point["corridor"] = {"old": True}
        source.write_text(json.dumps(payload))
        return source, payload

    def test_matrix_covers_three_profiles_and_all_controls(self):
        source, _ = self.source_manifest()
        matrix = matrix_payload(source)
        self.assertEqual(len(matrix["cases"]), 9)
        self.assertEqual(
            {(p["scheme"], p["trial_mode"]) for p in matrix["cases"]},
            {
                (s, m)
                for s in ("current", "legacy_16", "modern_cs")
                for m in ("jump", "no_jump", "walk")
            },
        )
        self.assertEqual(matrix["source_manifest_sha256"], sha(source))

    def test_matrix_changes_only_identity_and_profile(self):
        source, payload = self.source_manifest()
        originals = {p["id"]: p for p in payload["cases"]}
        for point in matrix_payload(source)["cases"]:
            original = originals[point["id"].removeprefix(point["scheme"] + "__")]
            self.assertEqual(
                {k: v for k, v in point.items() if k not in ("id", "scheme")},
                {k: v for k, v in original.items() if k not in ("id", "scheme")},
            )

    def test_mixed_profile_source_rejected(self):
        source, payload = self.source_manifest()
        payload["cases"][0]["scheme"] = "modern_cs"
        source.write_text(json.dumps(payload))
        with self.assertRaises(ValueError):
            matrix_payload(source)

    def test_missing_control_rejected(self):
        source, payload = self.source_manifest()
        payload["cases"].pop()
        source.write_text(json.dumps(payload))
        with self.assertRaises(ValueError):
            matrix_payload(source)

    def test_duplicate_source_identifier_rejected(self):
        source, payload = self.source_manifest()
        payload["cases"][1]["id"] = payload["cases"][0]["id"]
        source.write_text(json.dumps(payload))
        with self.assertRaises(ValueError):
            matrix_payload(source)

    def test_matrix_cannot_gain_formal_authority(self):
        source, payload = self.source_manifest()
        payload["formal_qualification"] = True
        source.write_text(json.dumps(payload))
        with self.assertRaises(ValueError):
            matrix_payload(source)

    def test_new_approach_drops_stale_corridor_and_preserves_goal(self):
        source, payload = self.source_manifest()
        for point in approach_payload(source)["cases"]:
            self.assertNotIn("corridor", point)
            self.assertAlmostEqual(
                point["start"][2], payload["cases"][0]["start"][2] + 1.2
            )
            for key in (
                "target_feet",
                "target_radius",
                "target_height_tolerance",
                "yaw",
                "duration",
            ):
                self.assertEqual(point[key], payload["cases"][0][key])

    def test_approach_walking_control_never_jumps_or_crouches(self):
        source, _ = self.source_manifest()
        for point in approach_payload(source)["cases"]:
            if point["trial_mode"] == "walk":
                self.assertTrue(
                    all(
                        "Shift" in e["keys"]
                        and "Space" not in e["keys"]
                        and "Ctrl" not in e["keys"]
                        for e in point["native_timeline"]
                    )
                )

    def test_generation_does_not_rewrite_source(self):
        source, _ = self.source_manifest()
        before = source.read_bytes()
        matrix_payload(source)
        approach_payload(source)
        self.assertEqual(source.read_bytes(), before)

    def test_current_yaw_drift_rejected(self):
        before = {
            "trace": [
                {
                    **{k: 0 for k in PHYSICS_FIELDS},
                    "yaw": 0.0,
                    "native_command": {"keys": ["W"]},
                }
            ]
        }
        after = copy.deepcopy(before)
        after["trace"][0]["yaw"] = 0.01
        with self.assertRaises(ValueError):
            require_unchanged_current(before, after)

    def test_current_key_drift_rejected(self):
        before = {
            "trace": [
                {
                    **{k: 0 for k in PHYSICS_FIELDS},
                    "yaw": 0.0,
                    "native_command": {"keys": ["W"]},
                }
            ]
        }
        after = copy.deepcopy(before)
        after["trace"][0]["native_command"]["keys"] = ["A"]
        with self.assertRaises(ValueError):
            require_unchanged_current(before, after)


if __name__ == "__main__":
    unittest.main()
