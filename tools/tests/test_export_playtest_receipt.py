import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

AUTHORING = Path(__file__).parents[1] / "authoring"
sys.path.insert(0, str(AUTHORING))
SPEC = importlib.util.spec_from_file_location(
    "export_receipt", AUTHORING / "export_playtest_receipt.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ExportReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in MODULE.ARTIFACTS:
            (self.root / name).write_bytes(name.encode())
        self.before = {"runtime_source_head": "a" * 40}
        self.steps = [{"exit_code": 0}] * 4

    def test_three_artifacts_bound(self):
        result = MODULE.collect(self.root, self.before, self.before, self.steps)
        self.assertEqual(set(result["artifacts"]), set(MODULE.ARTIFACTS))
        self.assertFalse(result["activation_allowed"])

    def test_changed_source_rejected(self):
        with self.assertRaisesRegex(ValueError, "Source changed"):
            MODULE.collect(self.root, self.before, {}, self.steps)

    def test_incomplete_steps_rejected(self):
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            MODULE.collect(self.root, self.before, self.before, self.steps[:3])

    def test_missing_or_empty_artifact_rejected(self):
        (self.root / "VectorBreach.pck").unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            MODULE.collect(self.root, self.before, self.before, self.steps)
        (self.root / "VectorBreach.pck").touch()
        with self.assertRaisesRegex(ValueError, "Empty"):
            MODULE.collect(self.root, self.before, self.before, self.steps)

    def test_dry_run_has_no_side_effects(self):
        destination = self.root / "new-export"
        with patch.object(MODULE, "snapshot", return_value=self.before):
            result = MODULE.export(self.root / "repo", Path("godot"), destination, True)
        self.assertFalse(destination.exists())
        self.assertFalse(result["executed"])
        self.assertEqual(len(result["commands"]), 4)
        self.assertIn("--main-pack", result["commands"][-1])

    def test_existing_destination_rejected(self):
        with self.assertRaisesRegex(ValueError, "fresh directory"):
            MODULE.export(self.root / "repo", Path("godot"), self.root, True)
