import json
import tempfile
import unittest
from pathlib import Path

from prepare_character_runtime_bundle import digest, prepare


class CharacterRuntimeBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.options = {}
        for role in ["reflection", "lighting", "normalization", "indirect"]:
            folder = self.root / role
            folder.mkdir()
            self.options[role] = folder / (role + ".json")
        reflection = self.options["reflection"].parent / "blocks/reflection.bc6h"
        reflection.parent.mkdir()
        reflection.write_bytes(b"reflection bytes")
        brdf = self.options["normalization"].parent / "brdf-rgba-f32.bin"
        brdf.write_bytes(b"brdf bytes")
        atlas = self.options["lighting"].parent / "atlas.bin"
        atlas.write_bytes(b"probe bytes")
        common = {"level": "map", "source_trace": {"vpkSha256": "a" * 64}}
        self.write(
            "reflection",
            dict(common, file="blocks/reflection.bc6h", sha256=digest(reflection)),
        )
        self.write(
            "normalization",
            dict(common, brdf={"file": brdf.name, "sha256": digest(brdf)}),
        )
        self.write(
            "lighting",
            dict(
                common,
                sources={
                    "probe": {"decoded": {"file": atlas.name, "sha256": digest(atlas)}}
                },
            ),
        )
        self.write(
            "indirect", dict(common, lighting_sha256=digest(self.options["lighting"]))
        )

    def write(self, role, data):
        self.options[role].write_text(json.dumps(data), encoding="utf-8")

    def test_roundtrip_and_original_bytes(self):
        originals = {
            path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()
        }
        output = self.root / "bundle"
        manifest = prepare(output, **self.options)
        self.assertEqual(manifest["level"], "map")
        self.assertEqual(len(manifest["files"]), 7)
        for row in manifest["files"]:
            self.assertEqual(digest(output / row["path"]), row["sha256"])
        for path, data in originals.items():
            self.assertEqual(path.read_bytes(), data)

    def test_refuse_existing_directory(self):
        output = self.root / "bundle"
        output.mkdir()
        sentinel = output / "keep.txt"
        sentinel.write_text("keep", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            prepare(output, **self.options)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_bad_dependency_does_not_publish(self):
        (self.options["lighting"].parent / "atlas.bin").write_bytes(b"wrong")
        output = self.root / "bundle"
        with self.assertRaises(ValueError):
            prepare(output, **self.options)
        self.assertFalse(output.exists())

    def test_mixed_map_does_not_publish(self):
        data = json.loads(self.options["indirect"].read_text())
        data["level"] = "other"
        self.write("indirect", data)
        with self.assertRaises(ValueError):
            prepare(self.root / "bundle", **self.options)
        self.assertFalse((self.root / "bundle").exists())

    def test_path_escape_does_not_publish(self):
        data = json.loads(self.options["reflection"].read_text())
        data["file"] = "../outside.bin"
        self.write("reflection", data)
        with self.assertRaises(ValueError):
            prepare(self.root / "bundle", **self.options)
        self.assertFalse((self.root / "bundle").exists())


if __name__ == "__main__":
    unittest.main()
