"""Reject ambiguous source contracts and retain native channels and parameters."""

import importlib.util
import json
import sys
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import audit_source_material_contracts as audit
import prepare_source_modulate as modulate

SPEC = importlib.util.spec_from_file_location(
    "alpha_fixture", Path(__file__).with_name("test_source_decals.py")
)
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)


class ModulateContractTests(unittest.TestCase):
    def setUp(self):
        self.fixture = FIXTURE.SourceDecalInstallTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        f = self.fixture
        f.scene["materials"][0]["extras"]["vmat"]["IntParams"] = {"F_BLEND_MODE": 3}

    def install(self):
        f = self.fixture
        f.visual.write_text(json.dumps(f.scene), encoding="utf-8")
        return modulate.install(
            f.visual, f.repo, json.loads(f.receipt.read_text(encoding="utf-8"))
        )

    def test_retains_entire_source_contract_and_original_texture_bytes(self):
        f = self.fixture
        native = f.scene["materials"][0]["extras"]["vmat"]
        before = f.old.read_bytes()
        result = self.install()
        entry = result["materials"][0]
        self.assertEqual(entry["native_material"], native)
        self.assertEqual(f.old.read_bytes(), before)
        target = f.repo / entry["texture"].removeprefix("res://")
        self.assertEqual(target.read_bytes(), f.decoded.read_bytes())
        self.assertEqual(entry["provenance"]["alpha_extrema"], [0, 128])
        self.assertFalse(entry["render_rules"]["depth_write"])
        self.assertFalse(entry["render_rules"]["casts_shadow"])
        with self.assertRaises(FileExistsError):
            self.install()

    def test_unimplemented_source_feature_fails_before_any_output(self):
        f = self.fixture
        f.scene["materials"][0]["extras"]["vmat"]["IntParams"]["F_LIT"] = 1
        with self.assertRaisesRegex(ValueError, "Unsupported Mod2x flag"):
            self.install()
        self.assertFalse((f.folder / "source-modulate").exists())

    def test_changed_native_decode_is_rejected(self):
        Image.new("RGBA", (2, 2), (0, 0, 0, 128)).save(self.fixture.decoded)
        with self.assertRaisesRegex(ValueError, "Native decode changed"):
            self.install()

    def test_missing_native_and_rgb_drift_are_rejected(self):
        f = self.fixture
        f.receipt.write_text("[]", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Missing verified"):
            self.install()
        Image.new("RGBA", (2, 2), (0, 0, 0, 128)).save(f.decoded)
        f.write_receipt()
        with self.assertRaisesRegex(ValueError, "RGB differs"):
            self.install()
        self.assertFalse((f.folder / "source-modulate.json").exists())


class MaterialInventoryTests(unittest.TestCase):
    def test_source_semantics_survive_even_when_export_loses_extras(self):
        native = {
            "ShaderName": "csgo_character.vfx",
            "IntParams": {"F_CLOTH_SHADING": 1, "F_RENDER_BACKFACES": 1},
            "TextureParams": {"g_tNormal": "original.vtex"},
        }
        row = audit.material_record({"name": "cloth"}, native)
        self.assertEqual(row["native_material"], native)
        self.assertIn("source_backfaces_not_in_export", row["risks"])
        self.assertIn("source_normal_not_in_export", row["risks"])
        self.assertIn("source_parameters_absent_from_runtime_export", row["risks"])
        contract = audit.runtime_contract(
            {"materials": [row], "sha256": "runtime", "source_sha256": "native"}
        )
        entry = contract["materials"][0]
        self.assertEqual(entry["native_material"], native)
        self.assertIn("F_CLOTH_SHADING", entry["pending_features"])
        self.assertEqual(entry["render_contract"], "preserve-exported-pbr-v1")

    def test_missing_source_is_not_reported_as_pass(self):
        row = audit.material_record({"name": "unknown"})
        self.assertIn("no_native_material_contract", row["risks"])
        self.assertEqual(row["acceptance"], "requires_review")

    def test_alpha_mode_and_duplicate_material_identity_require_review(self):
        native = {"IntParams": {"F_ALPHA_TEST": 1, "F_TRANSLUCENT": 1}}
        row = audit.material_record({"alphaMode": "OPAQUE"}, native)
        self.assertIn("alpha_test_not_in_export", row["risks"])
        self.assertIn("translucency_not_in_export", row["risks"])


if __name__ == "__main__":
    unittest.main()
