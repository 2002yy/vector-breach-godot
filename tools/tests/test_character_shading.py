"""Native feature masks must be explicit, complete and unambiguous."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_character_shading as shading


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
