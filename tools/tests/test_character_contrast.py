"""Native metadata boundaries, preserved inputs and dynamic uniform goldens."""

import json
import math
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_character_contrast as contrast


def texture(rgba=(0.2, 0.3, 0.4, 1.0)):
    data = struct.pack("<HH4fHHHBBIII", 1, 0, *rgba, 16, 8, 1, 1, 1, 0, 0, 0)
    return struct.pack("<IHHII4sII", 68, 12, 1, 8, 1, b"DATA", 8, 40) + data


class ContrastInputTests(unittest.TestCase):
    def test_reads_original_float_color_without_gamma_or_rgb_reconstruction(self):
        result = contrast.read_reflectivity(texture())
        self.assertEqual(result["dimensions"], [16, 8, 1])
        self.assertAlmostEqual(result["reflectivity_rgba"][0], 0.2)
        self.assertAlmostEqual(result["reflectivity_rgba"][2], 0.4)

    def test_rejects_block_bounds_versions_nan_and_volume(self):
        cases = [b"short", texture((math.nan, 0.3, 0.4, 1))]
        for offset, value, fmt in [
            (8, 0xFFFFFF, "I"),
            (20, 2, "I"),
            (24, 4000, "I"),
            (28, 2, "H"),
            (52, 2, "H"),
        ]:
            raw = bytearray(texture())
            struct.pack_into("<" + fmt, raw, offset, value)
            cases.append(raw)
        for raw in cases:
            with self.subTest(raw=bytes(raw[:28])):
                with self.assertRaises(ValueError):
                    contrast.read_reflectivity(raw)

    def test_exposure_and_feature_goldens_include_translucent_disable(self):
        for translucent, flag, expected_enabled in [
            (0, 1, True),
            (0, 0, False),
            (1, 1, False),
        ]:
            native = {
                "IntParams": {
                    "F_TRANSLUCENT": translucent,
                    "F_DISTANCE_CONTRAST_ADJUSTMENT": flag,
                },
                "FloatParams": {"g_fDistanceContrastExposure": 0.8},
            }
            row = contrast.effective_uniforms(native)
            self.assertAlmostEqual(
                row["exposure_effective"], 0.8 if translucent else 0.2
            )
            self.assertEqual(row["material_adjustment"], expected_enabled)
        self.assertAlmostEqual(
            contrast.effective_uniforms({})["exposure_effective"], 0.4
        )
        with self.assertRaises(ValueError):
            contrast.effective_uniforms(
                {"FloatParams": {"g_fDistanceContrastExposure": math.inf}}
            )

    def test_missing_or_changed_models_fail_before_writing_a_contract(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            asset = project / "assets/local_reference/test"
            asset.mkdir(parents=True)
            (asset / "body.glb").write_bytes(b"changed")
            (asset / "source-materials.json").write_text(
                json.dumps({"assets": {"body.glb": {"visual_sha256": "wrong"}}}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "model changed"):
                contrast.install(asset, project, project)
            self.assertFalse((asset / "source-character-contrast-inputs.json").exists())

    def test_color_path_traversal_is_rejected(self):
        native = {
            "ShaderName": "csgo_character.vfx",
            "TextureParams": {"g_tColor": "../outside.vtex"},
        }
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            contrast.collect(
                {
                    "assets": {
                        "body": {
                            "materials": [{"name": "skin", "native_material": native}]
                        }
                    }
                },
                Path.cwd(),
            )

    def test_install_preserves_originals_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            asset = project / "assets/local_reference/test"
            asset.mkdir(parents=True)
            model = asset / "body.glb"
            model.write_bytes(b"original-model")
            native_texture = project / "skin.vtex_c"
            native_texture.write_bytes(texture())
            native = {
                "ShaderName": "csgo_character.vfx",
                "TextureParams": {"g_tColor": "skin.vtex"},
                "FloatParams": {"g_fDistanceContrastExposure": 0.8},
            }
            manifest = asset / "source-materials.json"
            manifest.write_text(
                json.dumps(
                    {
                        "assets": {
                            "body.glb": {
                                "visual_sha256": contrast.sha(model),
                                "materials": [
                                    {"name": "skin", "native_material": native}
                                ],
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            originals = {p: p.read_bytes() for p in (manifest, model, native_texture)}
            result = contrast.install(asset, project, project)
            self.assertEqual(result["materials"][0]["native_material"], native)
            self.assertAlmostEqual(result["materials"][0]["exposure_effective"], 0.2)
            output = asset / "source-character-contrast-inputs.json"
            saved = output.read_bytes()
            with self.assertRaises(FileExistsError):
                contrast.install(asset, project, project)
            self.assertEqual(output.read_bytes(), saved)
            for path, data in originals.items():
                self.assertEqual(path.read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
