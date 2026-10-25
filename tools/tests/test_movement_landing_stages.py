"""Reject observer drift, mislabelled ablations and incomplete reference studies."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from landing_stage_audit import (
    EDGE_PROBES,
    PROBES,
    QUEUE_PROBES,
    edge_payload,
    payload,
    queued_payload,
    stage_changes,
)


class LandingStageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in (*PROBES, *EDGE_PROBES, *QUEUE_PROBES):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        self.source = self.root / "source.json"
        self.data = dict(schema=4, formal_qualification=False, cases=[])
        for parent in ("rim00", "rim01"):
            for scheme in ("current", "legacy_16", "modern_cs"):
                for mode in ("jump", "no_jump", "walk"):
                    self.data["cases"].append(
                        dict(
                            id=f"{parent}__{scheme}__{mode}",
                            parent_case=parent,
                            scheme=scheme,
                            trial_mode=mode,
                            start=[1, 2, 3],
                            target_feet=[1, 3, 5],
                            native_timeline=[dict(at=0, keys=["W"])],
                        )
                    )
        self.save()

    def save(self):
        self.source.write_text(json.dumps(self.data))

    def test_full_reference_and_bounded_ablations(self):
        study = payload(self.source, self.root)
        self.assertEqual(len(study["cases"]), 24)
        self.assertEqual(sum(p["ablation"] == "baseline" for p in study["cases"]), 18)
        self.assertTrue(study["diagnostic_only"])
        self.assertFalse(study["formal_qualification"])

    def test_ablations_never_change_inputs_or_geometry(self):
        originals = {p["id"]: p for p in self.data["cases"]}
        for point in payload(self.source, self.root)["cases"]:
            original = originals[point["source_case"]]
            for key, value in original.items():
                if key != "id":
                    self.assertEqual(point[key], value)

    def test_missing_control_rejected(self):
        self.data["cases"].pop()
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root)

    def test_duplicate_profile_tuple_rejected(self):
        self.data["cases"][1]["trial_mode"] = self.data["cases"][0]["trial_mode"]
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root)

    def test_camera_pose_rejected(self):
        self.data["camera_only"] = True
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root)

    def test_formal_authority_rejected(self):
        self.data["formal_qualification"] = True
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root)

    def stage_fixture(self, ablation="baseline"):
        snapshot = dict(
            position=[0, 1, 0],
            velocity=[0, -1, 0],
            grounded=False,
            floor_normal=[0, 0, 0],
        )
        point = dict(ablation=ablation, probe_sha256={"probe": "sha"})
        stage = dict(
            stage="pre_step",
            enabled=ablation != "no_pre",
            before=snapshot,
            after=copy.deepcopy(snapshot),
        )
        row = dict(
            trace=[dict(time=0.5, probe_sha256={"probe": "sha"}, stages=[stage])]
        )
        return point, row

    def test_disabled_stage_is_noop(self):
        point, row = self.stage_fixture("no_pre")
        self.assertEqual(stage_changes(row, point), [])

    def test_disabled_stage_cannot_move_player(self):
        point, row = self.stage_fixture("no_pre")
        row["trace"][0]["stages"][0]["after"]["position"][1] += 0.01
        with self.assertRaises(ValueError):
            stage_changes(row, point)

    def test_unrespected_switch_rejected(self):
        point, row = self.stage_fixture("no_pre")
        row["trace"][0]["stages"][0]["enabled"] = True
        with self.assertRaises(ValueError):
            stage_changes(row, point)

    def test_duplicate_stage_rejected(self):
        point, row = self.stage_fixture()
        row["trace"][0]["stages"].append(copy.deepcopy(row["trace"][0]["stages"][0]))
        with self.assertRaises(ValueError):
            stage_changes(row, point)

    def test_probe_identity_drift_rejected(self):
        point, row = self.stage_fixture()
        row["trace"][0]["probe_sha256"]["probe"] = "new"
        with self.assertRaises(ValueError):
            stage_changes(row, point)

    def test_airborne_lift_remains_visible(self):
        point, row = self.stage_fixture()
        row["trace"][0]["stages"][0]["after"]["position"][1] += 0.2
        changes = stage_changes(row, point)
        self.assertAlmostEqual(changes[0]["delta_y"], 0.2)
        self.assertFalse(changes[0]["grounded_before"])

    def test_horizontal_stage_change_remains_visible(self):
        point, row = self.stage_fixture()
        row["trace"][0]["stages"][0]["after"]["position"][0] += 0.1
        changes = stage_changes(row, point)
        self.assertAlmostEqual(changes[0]["displacement"], 0.1)

    def test_velocity_only_stage_change_remains_visible(self):
        point, row = self.stage_fixture()
        row["trace"][0]["stages"][0]["after"]["velocity"][1] = 0
        changes = stage_changes(row, point)
        self.assertEqual(changes[0]["velocity_change"], 1)

    def test_immediate_edge_is_diagnostic_not_native_acceptance(self):
        study = edge_payload(self.source, self.root)
        self.assertEqual(len(study["cases"]), 20)
        self.assertEqual(sum(p["immediate_jump"] for p in study["cases"]), 2)
        self.assertFalse(study["native_acceptance"])
        self.assertTrue(study["diagnostic_only"])
        self.assertTrue(all(p["ablation"] == "baseline" for p in study["cases"]))

    def test_source_preserved(self):
        before = self.source.read_bytes()
        payload(self.source, self.root)
        edge_payload(self.source, self.root)
        self.assertEqual(before, self.source.read_bytes())

    def test_queued_mode_keeps_native_keys_and_all_stages(self):
        study = queued_payload(self.source, self.root)
        originals = {p["id"]: p for p in self.data["cases"]}
        self.assertEqual(len(study["cases"]), 20)
        self.assertEqual(sum(p["queued_input"] for p in study["cases"]), 2)
        self.assertFalse(study["native_acceptance"])
        for point in study["cases"]:
            self.assertEqual(
                point["native_timeline"],
                originals[point["source_case"]]["native_timeline"],
            )
            self.assertEqual(point["ablation"], "baseline")
            self.assertNotIn("immediate_jump", point)

    def test_queue_probe_identity_does_not_claim_direct_edge_implementation(self):
        study = queued_payload(self.source, self.root)
        self.assertTrue(study["fixed_fps_diagnostic"])
        for point in study["cases"]:
            self.assertEqual(
                set(point["probe_sha256"]),
                {"res://" + p for p in (*PROBES, *QUEUE_PROBES)},
            )


if __name__ == "__main__":
    unittest.main()
