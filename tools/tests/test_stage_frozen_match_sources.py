import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from stage_frozen_match_sources import resource_path, stage


class FrozenMatchSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "project"
        self.build = Path(self.temp.name) / "portable"
        self.level = self.project / "data/levels/inferno-classic-local.json"
        self.level.parent.mkdir(parents=True)
        self.level.write_text(json.dumps({
            "runtime_collision_scene": "res://assets/collision.glb",
            "match_manifest": "res://data/frozen.json",
        }), encoding="utf-8")
        self.source = self.project / "assets/collision.glb"
        self.source.parent.mkdir()
        self.source.write_bytes(b"original collision bytes, distinct from imported scene")
        self.manifest = self.project / "data/frozen.json"
        self.manifest.write_text(json.dumps({
            "schema": 1,
            "collision_path": "res://assets/collision.glb",
            "collision_sha256": hashlib.sha256(self.source.read_bytes()).hexdigest(),
            "level_sha256": {
                "res://data/levels/inferno-classic-local.json":
                    hashlib.sha256(self.level.read_bytes()).hexdigest()
            },
        }), encoding="utf-8")

    def test_portable_copy_preserves_frozen_bytes_and_is_idempotent(self):
        result = stage(self.project, self.build)
        self.assertEqual(len(result["files"]), 1)
        self.assertEqual((self.build / "assets/collision.glb").read_bytes(), self.source.read_bytes())
        self.assertEqual(stage(self.project, self.build), result)

    def test_changed_collision_is_rejected_before_build_writes(self):
        self.source.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "collision hash"):
            stage(self.project, self.build)
        self.assertFalse(self.build.exists())

    def test_changed_level_is_rejected_before_build_writes(self):
        self.level.write_text(self.level.read_text() + " ", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "level hash"):
            stage(self.project, self.build)
        self.assertFalse(self.build.exists())

    def test_existing_conflicting_output_is_preserved(self):
        target = self.build / "assets/collision.glb"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"existing user file")
        with self.assertRaisesRegex(ValueError, "conflicting"):
            stage(self.project, self.build)
        self.assertEqual(target.read_bytes(), b"existing user file")

    def test_uninstalled_optional_maps_skip_but_strict_mode_rejects(self):
        empty = Path(self.temp.name) / "empty"
        empty.mkdir()
        self.assertEqual(stage(empty, self.build)["files"], [])
        with self.assertRaisesRegex(ValueError, "Required local level missing"):
            stage(empty, self.build, require_all=True)

    def test_paths_cannot_escape_project_or_build(self):
        for resource in ["res://../outside.glb", str(self.source)]:
            with self.assertRaises(ValueError):
                resource_path(self.build, resource)


if __name__ == "__main__":
    unittest.main()
