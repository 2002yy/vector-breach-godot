"""Native alpha installation must preserve RGB and reject ambiguous inputs."""

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

SPEC = importlib.util.spec_from_file_location(
    "source_decals", Path(__file__).resolve().parents[1] / "prepare_source_decals.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SourceDecalInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.folder = self.repo / "assets/local_reference/map"
        self.folder.mkdir(parents=True)
        self.old = self.folder / "color.png"
        Image.new("RGB", (2, 2), (128, 64, 32)).save(self.old)
        self.decoded = self.repo / "native.png"
        native = Image.new("RGBA", (2, 2), (128, 64, 32, 128))
        native.putpixel((0, 0), (128, 64, 32, 0))
        native.save(self.decoded)
        self.vtex = self.repo / "native.vtex_c"
        self.vtex.write_bytes(b"decoder source fixture")
        self.visual = self.folder / "map.gltf"
        self.scene = {
            "asset": {"version": "2.0"},
            "images": [{"uri": "color.png"}],
            "textures": [{"source": 0}],
            "materials": [
                {
                    "name": "sign",
                    "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}},
                    "extras": {
                        "vmat": {
                            "ShaderName": "csgo_static_overlay.vfx",
                            "IntParams": {"F_BLEND_MODE": 1},
                            "FloatParams": {"g_flOpacityScale": 0.9},
                            "TextureParams": {"g_tColor": "materials/sign.vtex"},
                        }
                    },
                }
            ],
        }
        self.receipt = self.repo / "decode-receipt.json"
        self.write_receipt()

    def write_receipt(self):
        self.receipt.write_text(
            json.dumps(
                [
                    {
                        "native_available": True,
                        "old_png": str(self.old),
                        "texture": "materials/sign.vtex",
                        "decoded_png": str(self.decoded),
                        "decoded_sha256": MODULE.sha(self.decoded),
                        "native_source": str(self.vtex),
                    }
                ]
            ),
            encoding="utf-8",
        )

    def install(self, use_decoded=True):
        self.visual.write_text(json.dumps(self.scene), encoding="utf-8")
        args = [
            "install",
            "--visual",
            str(self.visual),
            "--expected-sha256",
            MODULE.sha(self.visual),
        ]
        if use_decoded:
            args += ["--decoded-receipt", str(self.receipt)]
        with (
            patch.object(
                MODULE, "__file__", str(self.repo / "tools/prepare_source_decals.py")
            ),
            patch.object(sys, "argv", args),
        ):
            MODULE.main()

    def test_native_alpha_keeps_original_rgb_and_file_bytes(self):
        before = self.old.read_bytes()
        self.install()
        self.assertEqual(self.old.read_bytes(), before)
        manifest = json.loads((self.folder / "source-decal-alpha.json").read_text())
        entry = manifest["materials"][0]
        output = self.repo / entry["texture"].removeprefix("res://")
        with Image.open(output) as image:
            self.assertEqual(image.getchannel("A").getextrema(), (0, 128))
        self.assertEqual(entry["opacity_multiplier"], 0.9)
        self.assertEqual(manifest["inputs"][0]["decoded_sha256"], MODULE.sha(output))

    def test_rgb_change_and_same_name_blend_conflict_leave_no_output(self):
        Image.new("RGBA", (2, 2), (0, 0, 0, 128)).save(self.decoded)
        self.write_receipt()
        with self.assertRaisesRegex(ValueError, "RGB differs"):
            self.install()
        self.assertFalse((self.folder / "source-decals").exists())
        native = Image.new("RGBA", (2, 2), (128, 64, 32, 128))
        native.putpixel((0, 0), (128, 64, 32, 0))
        native.save(self.decoded)
        self.write_receipt()
        variant = json.loads(json.dumps(self.scene["materials"][0]))
        variant["extras"]["vmat"]["IntParams"]["F_BLEND_MODE"] = 2
        self.scene["materials"].append(variant)
        with self.assertRaisesRegex(ValueError, "same-name"):
            self.install()
        self.assertFalse((self.folder / "source-decal-alpha.json").exists())

    def test_existing_rgba_is_retained_with_explicit_provenance(self):
        self.old.write_bytes(self.decoded.read_bytes())
        before = hashlib.sha256(self.old.read_bytes()).hexdigest()
        self.install(use_decoded=False)
        manifest = json.loads((self.folder / "source-decal-alpha.json").read_text())
        self.assertEqual(
            manifest["materials"][0]["texture"],
            "res://assets/local_reference/map/color.png",
        )
        self.assertIn("not reacquired", manifest["inputs"][0]["alpha_source"])
        self.assertEqual(MODULE.sha(self.old), before)
        self.assertFalse((self.folder / "source-decals").exists())


if __name__ == "__main__":
    unittest.main()
