"""Import conversion must preserve same-basename backups and preflight inputs."""

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "configure_imports",
    Path(__file__).resolve().parents[1] / "configure_official_texture_imports.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ImportConfigurationTests(unittest.TestCase):
    def fixture(self, root):
        visual = root / "visual/map.gltf"
        visual.parent.mkdir()
        imports = []
        hashes = {}
        for directory in ["a", "b"]:
            source = visual.parent / directory / "shared.png"
            source.parent.mkdir()
            source.write_bytes(directory.encode())
            hashes[f"{directory}/shared.png"] = hashlib.sha256(
                source.read_bytes()
            ).hexdigest()
            metadata = source.with_name(source.name + ".import")
            metadata.write_text(
                f'uid="{directory}"\ncompress/mode=0\ncompress/high_quality=false\nmipmaps/generate=false\n',
                encoding="utf-8",
            )
            imports.append(metadata)
        visual.write_text(
            json.dumps({"images": [{"uri": uri} for uri in hashes]}), encoding="utf-8"
        )
        visual.with_suffix(".receipt.json").write_text(
            json.dumps({"copied_dependency_sha256": hashes}), encoding="utf-8"
        )
        return visual, imports

    def test_same_names_preserve_two_distinct_backups(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visual, imports = self.fixture(root)
            previous = [path.read_bytes() for path in imports]
            with patch.object(
                sys,
                "argv",
                [
                    "configure",
                    "--visual",
                    str(visual),
                    "--backup-dir",
                    str(root / "backup"),
                ],
            ):
                MODULE.main()
            for index, directory in enumerate(["a", "b"]):
                self.assertEqual(
                    (root / f"backup/{directory}/shared.png.import").read_bytes(),
                    previous[index],
                )
                self.assertIn(
                    "compress/mode=2", imports[index].read_text(encoding="utf-8")
                )
                self.assertIn(
                    "mipmaps/generate=true", imports[index].read_text(encoding="utf-8")
                )
                self.assertEqual(
                    (visual.parent / directory / "shared.png").read_bytes(),
                    directory.encode(),
                )

    def test_invalid_later_input_leaves_first_import_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visual, imports = self.fixture(root)
            previous = imports[0].read_bytes()
            imports[1].write_text("invalid import metadata", encoding="utf-8")
            with patch.object(
                sys,
                "argv",
                [
                    "configure",
                    "--visual",
                    str(visual),
                    "--backup-dir",
                    str(root / "backup"),
                ],
            ):
                with self.assertRaises(ValueError):
                    MODULE.main()
            self.assertEqual(imports[0].read_bytes(), previous)
            self.assertFalse((root / "backup").exists())


if __name__ == "__main__":
    unittest.main()
