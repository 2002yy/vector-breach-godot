"""The optional offset must never target an unknown export or ambiguous material."""

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "source_overlay",
    Path(__file__).resolve().parents[1] / "prepare_source_overlay_offsets.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class OverlayInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.visual = self.repo / "assets/local_reference/map/map.gltf"
        self.visual.parent.mkdir(parents=True)

    def write_fixture(self, materials, exporter="Source2Viewer-CLI 20.1", buffers=None):
        scene = {"materials": materials}
        if buffers is not None:
            scene["buffers"] = buffers
        self.visual.write_text(json.dumps(scene), encoding="utf-8")
        self.visual.with_suffix(".receipt.json").write_text(
            json.dumps(
                {
                    "source_exporter": exporter,
                    "output_sha256": hashlib.sha256(
                        self.visual.read_bytes()
                    ).hexdigest(),
                }
            ),
            encoding="utf-8",
        )

    def install(self):
        with (
            patch.object(
                MODULE,
                "__file__",
                str(self.repo / "tools/prepare_source_overlay_offsets.py"),
            ),
            patch.object(sys, "argv", ["prepare", "--visual", str(self.visual)]),
        ):
            MODULE.main()

    def test_registers_upstream_flags_and_preserves_visual(self):
        self.write_fixture(
            [
                {"name": "decal", "extras": {"vmat": {"IntParams": {"F_OVERLAY": 1}}}},
                {
                    "name": "biased",
                    "extras": {"vmat": {"IntParams": {"F_DEPTH_BIAS": 1}}},
                },
                {
                    "name": "static",
                    "extras": {"vmat": {"ShaderName": "csgo_static_overlay.vfx"}},
                },
                {"name": "wall"},
            ]
        )
        before = self.visual.read_bytes()
        self.install()
        result = json.loads(
            (self.visual.parent / "source-overlay-offset.json").read_text()
        )
        self.assertEqual(result["materials"], ["biased", "decal", "static"])
        self.assertEqual(self.visual.read_bytes(), before)
        with self.assertRaises(FileExistsError):
            self.install()

    def test_unknown_exporter_and_same_name_variants_are_rejected(self):
        self.write_fixture([], "future exporter")
        with self.assertRaisesRegex(ValueError, "Unknown exporter"):
            self.install()
        self.write_fixture(
            [
                {"name": "same", "extras": {"vmat": {"IntParams": {"F_OVERLAY": 1}}}},
                {"name": "same"},
            ]
        )
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            self.install()
        self.assertFalse((self.visual.parent / "source-overlay-offset.json").exists())

    def test_external_geometry_requires_matching_dependency_receipt(self):
        buffer = self.visual.parent / "mesh.bin"
        buffer.write_bytes(b"verified original positions")
        self.write_fixture(
            [{"name": "decal", "extras": {"vmat": {"IntParams": {"F_OVERLAY": 1}}}}],
            buffers=[{"uri": "mesh.bin"}],
        )
        with self.assertRaisesRegex(ValueError, "lacks a receipt"):
            self.install()
        receipt_path = self.visual.with_suffix(".receipt.json")
        receipt = json.loads(receipt_path.read_text())
        receipt["copied_dependency_sha256"] = {
            "mesh.bin": hashlib.sha256(buffer.read_bytes()).hexdigest()
        }
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        buffer.write_bytes(b"changed positions")
        with self.assertRaisesRegex(ValueError, "Geometry buffer changed"):
            self.install()
        self.assertFalse((self.visual.parent / "source-overlay-offset.json").exists())
        buffer.write_bytes(b"verified original positions")
        self.install()


if __name__ == "__main__":
    unittest.main()
