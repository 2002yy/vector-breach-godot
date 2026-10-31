"""Reject missing, escaped and inconsistent local gameplay dependencies."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).parents[1] / "authoring/snapshot_match_dependencies.py"
SPEC = importlib.util.spec_from_file_location("dependency_snapshot", TOOL)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DependencySnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.level = "res://data/levels/test.json"
        self.manifest = "res://data/levels/match-local/test.json"
        self.source = "res://assets/collision.glb"
        self.compiled = "res://.godot/imported/collision.scn"
        self.write(self.source, b"collision")
        self.write(self.compiled, b"compiled")
        self.write(self.source + ".import", '[remap]\npath="' + self.compiled + '"\n')
        self.write(
            self.level,
            json.dumps(
                dict(
                    id="test",
                    match_manifest=self.manifest,
                    runtime_collision_scene=self.source,
                )
            ),
        )
        self.payload = dict(
            schema=1,
            collision_path=self.source,
            collision_sha256=self.sha(self.source),
            level_sha256={self.level: self.sha(self.level)},
            layout=dict(
                navigationGraph=dict(points=[1], links=[1]),
                objectives=[1, 2],
                matchSpawns=dict(T=[1] * 5, CT=[1] * 5),
            ),
        )
        self.write(self.manifest, json.dumps(self.payload))
        self.level_patch = patch.object(MODULE, "LEVELS", ("test",))
        self.level_patch.start()
        self.addCleanup(self.level_patch.stop)

    def write(self, resource, data):
        path = self.root / resource[6:]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode())

    def sha(self, resource):
        return hashlib.sha256((self.root / resource[6:]).read_bytes()).hexdigest()

    def test_complete_closure_has_raw_import_compiled_and_absent_cache(self):
        result = MODULE.snapshot(self.root)
        self.assertEqual(len(result["files"]), 5)
        self.assertIn(self.compiled, result["files"])
        self.assertEqual(
            result["maps"]["test"]["cache_status"], "absent_runtime_fallback"
        )

    def test_missing_compiled_is_rejected(self):
        (self.root / self.compiled[6:]).unlink()
        with self.assertRaises(FileNotFoundError):
            MODULE.snapshot(self.root)

    def test_raw_collision_mutation_rejected(self):
        self.write(self.source, b"different")
        with self.assertRaisesRegex(ValueError, "collision SHA"):
            MODULE.snapshot(self.root)

    def test_level_mutation_rejected(self):
        self.write(self.level, (self.root / self.level[6:]).read_text() + " ")
        with self.assertRaisesRegex(ValueError, "level SHA"):
            MODULE.snapshot(self.root)

    def test_compiled_traversal_rejected(self):
        self.write(
            self.source + ".import",
            '[remap]\npath="res://.godot/imported/../../outside.scn"\n',
        )
        with self.assertRaisesRegex(ValueError, "unsafe"):
            MODULE.snapshot(self.root)

    def test_wrong_manifest_identity_rejected(self):
        self.payload["collision_path"] = "res://wrong.glb"
        self.write(self.manifest, json.dumps(self.payload))
        with self.assertRaisesRegex(ValueError, "identity"):
            MODULE.snapshot(self.root)

    def test_partial_cache_rejected(self):
        cache = (
            "res://assets/local_reference/collision_cache/"
            + hashlib.sha256(self.source.encode()).hexdigest()
            + ".res"
        )
        self.write(cache, b"cache")
        with self.assertRaises(FileNotFoundError):
            MODULE.snapshot(self.root)

    def test_stale_cache_receipt_rejected(self):
        cache = (
            "res://assets/local_reference/collision_cache/"
            + hashlib.sha256(self.source.encode()).hexdigest()
            + ".res"
        )
        self.write(cache, b"cache")
        self.write(cache + ".json", "{}")
        with self.assertRaisesRegex(ValueError, "cache SHA"):
            MODULE.snapshot(self.root)


if __name__ == "__main__":
    unittest.main()
