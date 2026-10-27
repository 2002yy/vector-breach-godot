"""Selected-profile manual entry must reject source drift and false acceptance."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import movement_current_observation as observation


class CurrentObservationTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.project = self.directory / "project"
        for filename in (observation.ADAPTER, observation.ENTRY, observation.OBSERVER):
            path = self.project / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("source", encoding="utf-8")
        self.registry_path = self.directory / "registry.json"
        self.registry_path.write_text("{}", encoding="utf-8")
        self.registry = {"sites": []}
        for map_name, level in observation.LEVELS.items():
            profiles = {}
            for scheme in observation.SCHEMES:
                profiles[scheme] = dict(
                    point=dict(
                        scheme=scheme,
                        trial_mode="jump",
                        start=[1, 2, 3],
                        native_timeline=[dict(at=0, keys=[scheme])],
                    ),
                    manifest=dict(
                        level=level,
                        identity={},
                        runtime_sha256={},
                        input_map_sha256="x",
                    ),
                    status="walk_only",
                    source_provider=map_name,
                    source_case=scheme,
                )
            self.registry["sites"].append(
                dict(map=map_name, site="ordinary", profiles=profiles)
            )
        self.mock_verify = patch.object(
            observation, "verify_registry", return_value=self.registry
        )
        self.mock_verify.start()
        self.addCleanup(self.mock_verify.stop)
        self.pack = self.directory / "pack"

    def build(self):
        return observation.build(self.pack, self.registry_path, self.project)

    def test_all_nine_manifests_use_selected_profile_inputs(self):
        original = copy.deepcopy(self.registry)
        lock = self.build()
        self.assertEqual(len(lock["manifests"]), 9)
        result = observation.read(self.pack / "mirage-modern_cs.json")
        self.assertEqual(
            result["cases"][0]["native_timeline"][0]["keys"], ["modern_cs"]
        )
        self.assertEqual(result["cases"][0]["observation_status"], "walk_only")
        self.assertEqual(self.registry, original)
        observation.verify(self.pack, self.project)

    def test_adapter_drift_invalidates_entire_pack(self):
        self.build()
        (self.project / observation.ADAPTER).write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "drift"):
            observation.verify(self.pack, self.project)

    def test_manifest_profile_tampering_and_false_acceptance_rejected(self):
        self.build()
        path = self.pack / "pack.json"
        lock = observation.read(path)
        lock["human_review"] = "passed"
        path.write_text(json.dumps(lock), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "acceptance"):
            observation.verify(self.pack, self.project)

    def test_registry_drift_rejected(self):
        self.build()
        self.registry_path.write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "registry lock drift"):
            observation.verify(self.pack, self.project)

    def test_existing_pack_is_never_overwritten(self):
        self.build()
        with self.assertRaisesRegex(ValueError, "exists"):
            self.build()

    def test_unselected_profile_and_wrong_map_rejected(self):
        for map_name, scheme in (("wrong", "current"), ("dust2", "candidate")):
            with self.assertRaises(ValueError):
                observation.selected_manifest(self.registry, map_name, scheme)

    def test_launcher_verifies_before_spawning_and_no_manual_key_injection(self):
        self.build()
        with (
            patch.object(observation.subprocess, "run") as run,
            patch.object(observation, "validate_receipt"),
        ):
            observation.launch(
                self.pack,
                self.project,
                Path("godot.exe"),
                "dust2",
                "legacy_16",
                120,
                self.directory / "receipt.json",
            )
            command = run.call_args.args[0]
            self.assertIn("--rate=120", command)
            self.assertNotIn("--smoke", command)
            self.assertNotIn("--fixed-fps", command)
        self.registry_path.write_text("changed", encoding="utf-8")
        with patch.object(observation.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                observation.launch(
                    self.pack,
                    self.project,
                    Path("godot.exe"),
                    "dust2",
                    "current",
                    60,
                    self.directory / "receipt.json",
                )
            run.assert_not_called()

    def test_receipt_rejects_cross_profile_truncation_and_nonfinite_velocity(self):
        self.build()
        manifest = self.pack / "dust2-current.json"
        receipt = self.directory / "receipt.json"
        valid: dict[str, Any] = dict(
            attempts=[
                dict(
                    scheme="current",
                    trace=[dict(position=[0, 1, 2], velocity=[1, 0, 0])],
                )
            ]
        )
        with patch.object(observation, "validate_session_receipt", return_value={}):
            for field in ("scheme", "trace_truncated", "velocity"):
                data = copy.deepcopy(valid)
                attempt = data["attempts"][0]
                if field == "scheme":
                    attempt["scheme"] = "legacy_16"
                elif field == "trace_truncated":
                    attempt["trace_truncated"] = True
                else:
                    attempt["trace"][0]["velocity"][0] = float("nan")
                receipt.write_text(json.dumps(data), encoding="utf-8")
                with self.assertRaises(ValueError):
                    observation.validate_receipt(
                        receipt, manifest, self.project, "manual"
                    )


if __name__ == "__main__":
    unittest.main()
