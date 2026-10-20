"""Native feature masks must be explicit, complete and unambiguous."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_character_shading as shading
import prepare_character_eye_bindings as eyes


class CharacterChannelTests(unittest.TestCase):
    def fixture(self):
        return {
            "assets": {
                "body.glb": {
                    "materials": [
                        {
                            "name": "cloth",
                            "native_material": {
                                "ShaderName": "csgo_character.vfx",
                                "IntParams": {"F_CLOTH_SHADING": 1},
                                "TextureParams": {
                                    "g_tMetalness": "characters/cloth.vtex"
                                },
                                "FloatParams": {"g_flSheenScale": 0.667},
                            },
                        }
                    ]
                }
            }
        }

    def test_parameter_and_native_texture_identity_are_retained(self):
        data = self.fixture()
        result = shading.collect(data)
        self.assertEqual(
            result["cloth"]["bindings"], {"g_tMetalness": "characters/cloth.vtex"}
        )
        self.assertEqual(
            result["cloth"]["native_material"],
            data["assets"]["body.glb"]["materials"][0]["native_material"],
        )

    def test_skin_needs_mask_and_falloff_not_a_tinted_base_map(self):
        data = self.fixture()
        native = data["assets"]["body.glb"]["materials"][0]["native_material"]
        native["IntParams"] = {"F_SUBSURFACE_SCATTERING": 1}
        native["TextureParams"] = {"g_tSssMask": "characters/skin.vtex"}
        with self.assertRaisesRegex(ValueError, "g_tDiffuseFalloff"):
            shading.collect(data)

    def test_retroreflection_requires_original_packed_mask(self):
        data = self.fixture()
        native = data["assets"]["body.glb"]["materials"][0]["native_material"]
        native["IntParams"] = {"F_RETRO_REFLECTIVE": 1}
        self.assertEqual(
            shading.collect(data)["cloth"]["bindings"],
            {"g_tMetalness": "characters/cloth.vtex"},
        )
        native["TextureParams"] = {}
        with self.assertRaisesRegex(ValueError, "g_tMetalness"):
            shading.collect(data)

    def test_hair_requires_sss_mask_and_anisotropic_axes(self):
        data = self.fixture()
        native = data["assets"]["body.glb"]["materials"][0]["native_material"]
        native["IntParams"] = {"F_ANISOTROPIC_HAIR": 1}
        native["TextureParams"] = {"g_tSssMask": "characters/skin.vtex"}
        with self.assertRaisesRegex(ValueError, "g_tAnisoGloss"):
            shading.collect(data)
        native["TextureParams"]["g_tAnisoGloss"] = "characters/axes.vtex"
        self.assertEqual(len(shading.collect(data)["cloth"]["bindings"]), 2)

    def test_eye_color_and_mask_are_both_required(self):
        data = self.fixture()
        native = data["assets"]["body.glb"]["materials"][0]["native_material"]
        native["IntParams"] = {"F_EYEBALLS": 1}
        native["TextureParams"] = {"g_tEyeAlbedo1": "characters/eye.vtex"}
        with self.assertRaisesRegex(ValueError, "g_tEyeMask1"):
            shading.collect(data)
        native["TextureParams"]["g_tEyeMask1"] = "characters/mask.vtex"
        self.assertEqual(len(shading.collect(data)["cloth"]["bindings"]), 2)

    def test_eye_radius_calibration_fits_all_bones_and_rejects_drift(self):
        original = {
            name: [i * 0.03, i * 0.12, (i % 2) * 0.07]
            for i, name in enumerate([*eyes.EYE_BONES, "head", "neck", "spine"])
        }
        converted = {
            name: [-p[0] * 0.91, p[1] * 0.91 + 0.02, -p[2] * 0.91]
            for name, p in original.items()
        }
        result = eyes.calibrate(original, converted)
        self.assertAlmostEqual(result["source_unit_m"], 0.0254 * 0.91)
        self.assertLess(result["max_residual_m"], 1e-10)
        converted["neck"][0] += 0.001
        with self.assertRaisesRegex(ValueError, "differs"):
            eyes.calibrate(original, converted)
        del original["eye_target"]
        with self.assertRaisesRegex(ValueError, "Missing"):
            eyes.calibrate(original, converted)

    def test_conflicting_variant_and_path_escape_fail_closed(self):
        data = self.fixture()
        row = json.loads(json.dumps(data["assets"]["body.glb"]["materials"][0]))
        row["native_material"]["FloatParams"]["g_flSheenScale"] = 2
        data["assets"]["arms.glb"] = {"materials": [row]}
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            shading.collect(data)
        data = self.fixture()
        data["assets"]["body.glb"]["materials"][0]["native_material"]["TextureParams"][
            "g_tMetalness"
        ] = "../escaped.vtex"
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            shading.collect(data)

    def test_changed_installed_model_rejects_before_decoding_or_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            asset = project / "assets/local_reference/characters"
            asset.mkdir(parents=True)
            (asset / "body.glb").write_bytes(b"changed original")
            data = self.fixture()
            data["assets"]["body.glb"]["visual_sha256"] = "incorrect"
            (asset / "source-materials.json").write_text(
                json.dumps(data), encoding="utf-8"
            )
            work = project / "decode"
            with self.assertRaisesRegex(ValueError, "changed since"):
                shading.install(asset, project, project, project / "no-decoder", work)
            self.assertFalse(work.exists())
            self.assertFalse((asset / "source-character-shading.json").exists())


if __name__ == "__main__":
    unittest.main()
