"""Guard bounded input selection against baseline reuse and changed geometry."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inferno_runup_controls import choose, selected_payload, study_payload


class InfernoRunupControlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source.json"
        self.source_data = dict(
            schema=4,
            formal_qualification=False,
            level="inferno-classic-local",
            cases=[],
        )
        for number in (0, 1):
            for scheme in ("current", "legacy_16", "modern_cs"):
                for mode in ("jump", "no_jump", "walk"):
                    parent = f"runup_{number}"
                    self.source_data["cases"].append(
                        dict(
                            id=f"{scheme}__{parent}__{mode}",
                            parent_case=parent,
                            scheme=scheme,
                            trial_mode=mode,
                            start=[0, 1, 0],
                            target_feet=[0, 1, -3],
                            target_radius=1.6,
                            target_height_tolerance=0.18,
                            yaw=0,
                            duration=2,
                            native_timeline=[
                                dict(at=t, keys=keys, mouse_dx=0)
                                for t, keys in (
                                    (0, ["W"]),
                                    (0.35, ["W", "Space"]),
                                    (0.35 + 2 / 60, ["W", "Space", "Ctrl"]),
                                    (0.45, ["W", "Ctrl"]),
                                    (1.5, ["Ctrl"]),
                                )
                            ],
                            timeline=[
                                dict(at=0, direction=[0, -1]),
                                dict(at=0.35, jump=True),
                                dict(at=0.35 + 2 / 60, crouch=True),
                                dict(at=0.45, jump=False),
                            ],
                        )
                    )
        self.save_source()

    def save_source(self):
        self.source.write_text(json.dumps(self.source_data))

    def outcomes(self, study):
        return {
            p["id"]: dict(
                first_landing=p["trial_mode"] == "jump" and p["variant"] != "baseline",
                supported_arrival=False,
            )
            for p in study["cases"]
        }

    def test_bounded_grid_preserves_all_geometry(self):
        study = study_payload(self.source)
        self.assertEqual(len(study["cases"]), 24)
        self.assertFalse(study["baseline_selection_eligible"])
        for point in study["cases"]:
            for key in (
                "start",
                "target_feet",
                "target_radius",
                "target_height_tolerance",
                "yaw",
                "duration",
            ):
                self.assertEqual(point[key], self.source_data["cases"][0][key])

    def test_earlier_jump_is_declared_absolute_time_not_feedback(self):
        study = study_payload(self.source)
        point = next(
            p
            for p in study["cases"]
            if p["variant"] == "jump_025" and p["trial_mode"] == "jump"
        )
        self.assertAlmostEqual(point["native_timeline"][1]["at"], 0.25)
        self.assertAlmostEqual(point["native_timeline"][2]["at"], 0.25 + 2 / 60)

    def test_simultaneous_crouch_uses_native_keys(self):
        point = next(
            p
            for p in study_payload(self.source)["cases"]
            if p["variant"] == "crouch_with_jump"
        )
        self.assertIn("Ctrl", point["native_timeline"][1]["keys"])

    def test_standing_walk_controls_never_jump_or_crouch(self):
        for point in study_payload(self.source)["cases"]:
            if point["trial_mode"] == "walk":
                self.assertTrue(
                    all(
                        "Shift" in e["keys"]
                        and "Space" not in e["keys"]
                        and "Ctrl" not in e["keys"]
                        for e in point["native_timeline"]
                    )
                )

    def test_known_inconsistent_baseline_is_never_selected(self):
        study = study_payload(self.source)
        results = self.outcomes(study)
        for point in study["cases"]:
            results[point["id"]]["first_landing"] = point["variant"] == "baseline"
        self.assertEqual(choose(study, results), {})

    def test_positive_walking_control_disqualifies_candidate(self):
        study = study_payload(self.source)
        results = self.outcomes(study)
        results["runup_0__jump_025__walk"]["supported_arrival"] = True
        self.assertEqual(choose(study, results)["runup_0"], "crouch_with_jump")

    def test_first_declared_success_is_selected(self):
        study = study_payload(self.source)
        self.assertEqual(
            set(choose(study, self.outcomes(study)).values()), {"jump_025"}
        )

    def selection(self, results=None):
        study = study_payload(self.source)
        path, report = self.root / "study.json", self.root / "report.json"
        path.write_text(json.dumps(study))
        report.write_text("{}")
        with patch(
            "inferno_runup_controls.check_report",
            return_value=results or self.outcomes(study),
        ) as check:
            payload = selected_payload(self.source, path, report, self.root)
            self.assertEqual(check.call_args.args[2], 60)
        return payload

    def test_final_selection_preserves_current_and_legacy_inputs(self):
        result = self.selection()
        originals = {p["id"]: p for p in self.source_data["cases"]}
        for point in result["cases"]:
            if point["scheme"] != "modern_cs":
                self.assertEqual(point, originals[point["id"]])
        self.assertFalse(result["same_inputs_all_profiles"])

    def test_incomplete_selection_cannot_omit_failed_point(self):
        study = study_payload(self.source)
        results = self.outcomes(study)
        for point in study["cases"]:
            if point["parent_case"] == "runup_1":
                results[point["id"]]["first_landing"] = False
        with self.assertRaises(ValueError):
            self.selection(results)

    def test_formal_authority_rejected(self):
        self.source_data["formal_qualification"] = True
        self.save_source()
        with self.assertRaises(ValueError):
            study_payload(self.source)

    def test_wrong_map_rejected(self):
        self.source_data["level"] = "mirage-classic-local"
        self.save_source()
        with self.assertRaises(ValueError):
            study_payload(self.source)

    def test_missing_reference_control_cannot_silently_reduce_matrix(self):
        self.source_data["cases"].pop(0)
        self.save_source()
        with self.assertRaises(ValueError):
            study_payload(self.source)

    def test_camera_only_manifest_cannot_be_used_as_physics_input(self):
        self.source_data["camera_only"] = True
        self.save_source()
        with self.assertRaises(ValueError):
            study_payload(self.source)

    def test_generation_does_not_rewrite_source(self):
        before = self.source.read_bytes()
        study_payload(self.source)
        self.assertEqual(before, self.source.read_bytes())


if __name__ == "__main__":
    unittest.main()
