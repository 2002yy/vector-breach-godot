"""Real equipment observation must preserve source locks and honest evidence gates."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import movement_weapon_observation as observation


class WeaponObservationTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.project = self.directory / "project"
        self.source = self.directory / "source"
        self.source.mkdir()
        (self.source / "pack.json").write_text("{}", encoding="utf-8")
        for dependency in observation.DEPENDENCIES:
            path = self.project / dependency
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("source", encoding="utf-8")
        for name, level in observation.LEVELS.items():
            for scheme in observation.SCHEMES:
                manifest = dict(
                    stage="latest_source_manual_observation",
                    human_review="pending",
                    observation_scheme=scheme,
                    formal_qualification=False,
                    level=level,
                    runtime_sha256={"res://old.gd": "old"},
                    cases=[
                        dict(parent_case=name, native_timeline=[dict(keys=[scheme])])
                    ],
                )
                (self.source / f"{name}-{scheme}.json").write_text(
                    json.dumps(manifest), encoding="utf-8"
                )
        self.pack = self.directory / "pack"
        self.receipt = self.directory / "receipt.json"
        self.current_verify = patch.object(observation, "verify_current")
        self.current_verify.start()
        self.addCleanup(self.current_verify.stop)

    def build(self) -> dict[str, Any]:
        return observation.build(self.pack, self.source, self.project)

    @staticmethod
    def sample(
        weapon="sniper", scoped=False, walking=False, crouching=False
    ) -> dict[str, Any]:
        return dict(
            walk_requested=walking,
            velocity=[3, 0, 4],
            jumped=False,
            weapon_context=dict(
                weapon_id=weapon,
                slot=2 if weapon == "knife" else 0,
                scoped=scoped,
                walking=walking,
                crouching=crouching,
                equipped="knife" if weapon == "knife" else "firearm",
                speed_limit=6.2,
                horizontal_speed=5.0,
                camera_fov=28.0 if scoped else 75.0,
                camera_base_fov=75.0,
            ),
        )

    def write_samples(self, samples):
        self.receipt.write_text(
            json.dumps(dict(attempts=[dict(trace=samples)])), encoding="utf-8"
        )

    def validate(self, *, smoke=False, mode="headless_collision_logic_smoke", rate=60):
        return observation.validate_receipt(
            self.receipt,
            self.pack / "dust2-current.json",
            self.project,
            mode,
            smoke,
            rate,
        )

    def test_all_nine_preserve_own_references_and_lock_real_dependencies(self):
        source_before = observation.read(self.source / "mirage-modern_cs.json")
        lock = self.build()
        self.assertEqual(len(lock["manifests"]), 9)
        result = observation.read(self.pack / "mirage-modern_cs.json")
        self.assertEqual(result["cases"], source_before["cases"])
        self.assertEqual(result["observation_scheme"], "modern_cs")
        self.assertEqual(result["runtime_sha256"]["res://old.gd"], "old")
        for dependency in observation.DEPENDENCIES:
            self.assertEqual(
                result["runtime_sha256"]["res://" + dependency],
                observation.sha(self.project / dependency),
            )
        self.assertEqual(
            observation.read(self.source / "mirage-modern_cs.json"), source_before
        )
        observation.verify(self.pack, self.project)

    def test_pack_refuses_overwrite_internal_output_and_source_drift(self):
        self.build()
        with self.assertRaisesRegex(ValueError, "exists"):
            self.build()
        with self.assertRaisesRegex(ValueError, "external"):
            observation.build(self.project / "bad", self.source, self.project)
        (self.source / "pack.json").write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "source pack drift"):
            observation.verify(self.pack, self.project)

    def test_missing_manifest_and_false_acceptance_rejected(self):
        self.build()
        path = self.pack / "pack.json"
        lock = observation.read(path)
        del lock["manifests"]["inferno-current.json"]
        path.write_text(json.dumps(lock), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            observation.verify(self.pack, self.project)
        lock["human_review"] = "passed"
        path.write_text(json.dumps(lock), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "invalid"):
            observation.verify(self.pack, self.project)

    def test_dependency_drift_refuses_pack_and_receipt_before_audit(self):
        self.build()
        (self.project / "scripts/combat/WeaponSystem.gd").write_text(
            "changed", encoding="utf-8"
        )
        with self.assertRaisesRegex(ValueError, "drift"):
            observation.verify(self.pack, self.project)
        self.write_samples([self.sample()])
        with patch.object(observation, "audit_receipt") as audit:
            with self.assertRaisesRegex(ValueError, "dependency drift"):
                self.validate()
            audit.assert_not_called()

    def test_restored_fov_equipment_slot_and_actual_speed_are_required(self):
        for weapon in ("sniper", "rifle", "knife"):
            sample = self.sample(weapon)
            observation.validate_context(sample["weapon_context"], sample)
        invalid = (
            ("camera_fov", 50.0),
            ("camera_base_fov", float("nan")),
            ("slot", True),
            ("equipped", "knife"),
            ("horizontal_speed", 6.0),
            ("speed_limit", 0),
            ("scoped", 1),
            ("walking", True),
        )
        for key, value in invalid:
            with self.subTest(key=key):
                sample = self.sample()
                sample["weapon_context"][key] = value
                with self.assertRaises(ValueError):
                    observation.validate_context(sample["weapon_context"], sample)

    def test_real_scope_requires_sniper_with_zoomed_fov(self):
        valid = self.sample(scoped=True)
        observation.validate_context(valid["weapon_context"], valid)
        for changes in (dict(weapon_id="rifle"), dict(camera_fov=75.0)):
            sample = copy.deepcopy(valid)
            sample["weapon_context"].update(changes)
            with self.assertRaisesRegex(ValueError, "scope"):
                observation.validate_context(sample["weapon_context"], sample)

    def test_receipt_uses_strict_audit_at_requested_rate_and_never_rates_human(self):
        self.build()
        self.write_samples([self.sample()])
        with patch.object(observation, "audit_receipt", return_value={}) as audit:
            result = self.validate(rate=120)
            self.assertEqual(audit.call_args.args[-1], 120)
            self.assertEqual(result["human_review"], "pending")
            self.assertFalse(result["formal_release_ready"])
        with patch.object(
            observation,
            "audit_receipt",
            side_effect=ValueError("global frame rollback"),
        ):
            with self.assertRaisesRegex(ValueError, "rollback"):
                self.validate()

    def smoke_samples(self):
        samples = [
            self.sample(scoped=scoped, walking=walk, crouching=crouch)
            for walk, crouch in ((False, False), (True, False), (False, True))
            for scoped in (False, True)
        ]
        samples += [self.sample("rifle"), self.sample("knife"), self.sample()]
        samples[0]["jumped"] = True
        return samples

    def test_smoke_requires_scope_postures_switch_return_motion_and_jump(self):
        self.build()
        valid = self.smoke_samples()
        with patch.object(observation, "audit_receipt", return_value={}):
            self.write_samples(valid)
            self.validate(smoke=True)
            cases = [valid[:2] + valid[-3:], valid[:-1]]
            no_jump = copy.deepcopy(valid)
            for sample in no_jump:
                sample["jumped"] = False
            cases.append(no_jump)
            no_motion = copy.deepcopy(valid)
            for sample in no_motion:
                sample["velocity"] = [0, 0, 0]
                sample["weapon_context"]["horizontal_speed"] = 0
            cases.append(no_motion)
            for samples in cases:
                self.write_samples(samples)
                with self.assertRaises(ValueError):
                    self.validate(smoke=True)

    def test_manual_cannot_be_relabelled_as_smoke_coverage(self):
        self.build()
        self.write_samples(self.smoke_samples())
        with patch.object(observation, "audit_receipt", return_value={}):
            with self.assertRaisesRegex(ValueError, "manual"):
                self.validate(smoke=True, mode="windowed_manual_unreviewed")

    def test_launch_validates_before_spawn_and_manual_has_no_injection(self):
        self.build()
        with (
            patch.object(observation.subprocess, "run") as run,
            patch.object(observation, "validate_receipt"),
        ):
            observation.launch(
                self.pack,
                self.project,
                Path("godot.exe"),
                "inferno",
                "modern_cs",
                120,
                self.receipt,
                "manual",
            )
            args = run.call_args.args[0]
            self.assertIn("--rate=120", args)
            self.assertNotIn("--smoke", args)
            self.assertNotIn("--render-smoke", args)
        (self.project / observation.ENTRY).write_text("changed", encoding="utf-8")
        with patch.object(observation.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "drift"):
                observation.launch(
                    self.pack,
                    self.project,
                    Path("godot.exe"),
                    "inferno",
                    "current",
                    60,
                    self.receipt,
                    "smoke",
                )
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
