import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "delivery_plan", Path(__file__).parents[1] / "authoring/plan_playtest_delivery.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DeliveryPlanTests(unittest.TestCase):
    def test_missing_new_main_pack_cannot_fall_back_to_old(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "build-info.json").write_text("{}", encoding="utf8")
            receipt = root / "receipt.json"
            receipt.write_text(
                json.dumps(
                    {
                        "graphical": {"three_maps_start_ready_verified": True},
                        "artifacts": {
                            "VectorBreach.exe": {},
                            "VectorBreach-radar.pck": {},
                        },
                    }
                ),
                encoding="utf8",
            )
            output = root / "plan.json"
            with self.assertRaisesRegex(ValueError, "requires EXE, main PCK"):
                MODULE.plan(root, root, receipt, output)
            self.assertFalse(output.exists())

    def test_path_escape_rejected_before_read(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("../secret", "C:/secret", "/secret"):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    MODULE.payload(root, name, {})

    def test_wrong_payload_hash_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "payload").write_bytes(b"original")
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                MODULE.payload(root, "payload", {"sha256": "0" * 64, "bytes": 8})

    def test_existing_output_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root / "plan.json"
            output.write_bytes(b"preserve")
            with self.assertRaises(FileExistsError):
                MODULE.plan(root, root, root / "absent", output)
            self.assertEqual(output.read_bytes(), b"preserve")


if __name__ == "__main__":
    unittest.main()
