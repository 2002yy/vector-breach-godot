import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

AUTHORING = Path(__file__).parents[1] / "authoring"
sys.path.insert(0, str(AUTHORING))
SPEC = importlib.util.spec_from_file_location(
    "complete_stage", AUTHORING / "stage_complete_playtest.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CompleteStageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.old = Path(self.temp.name) / "old"
        self.new = Path(self.temp.name) / "new"
        self.old.mkdir()
        self.new.mkdir()
        self.files = {}
        for name in [
            "角色环境候选.cmd",
            "assets/local_reference/dustline/de_dust2_original.glb",
            *[
                f"candidate-inputs/{key}/bundle.json"
                for key in ("dust2", "mirage", "inferno")
            ],
        ]:
            self.files[name] = self.put(self.old, name, b"support")
        (self.old / "build-info.json").write_text(
            json.dumps(dict(files=self.files)), encoding="utf8"
        )
        self.receipt: dict = dict(
            runtime_source_head="a" * 40,
            runtime_source_sha256="b" * 64,
            runtime_sources={"project.godot": "c" * 64},
            artifacts={
                name: self.put(self.new, name, b"fresh") for name in MODULE.RUNTIME
            },
        )

    def put(self, root, name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())

    def test_complete_support_copied_without_overwriting_runtime(self):
        plan = MODULE.prepare(self.old, self.new, self.receipt)
        MODULE.stage(self.new, plan)
        self.assertEqual((self.new / "VectorBreach.pck").read_bytes(), b"fresh")
        info = json.loads((self.new / "build-info.json").read_text(encoding="utf8"))
        self.assertEqual(info["runtime_source_head"], "a" * 40)
        self.assertFalse(info["activation_allowed"])
        guidance = (self.new / "试玩说明.txt").read_text(encoding="utf8")
        self.assertIn("a" * 40, guidance)
        self.assertNotIn("c9b6d868", guidance)
        self.assertNotIn("298", guidance)
        self.assertNotIn("2026-10-26", guidance)

    def test_tampered_support_rejected_before_copy(self):
        (self.old / "角色环境候选.cmd").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            MODULE.prepare(self.old, self.new, self.receipt)
        self.assertFalse((self.new / "build-info.json").exists())

    def test_missing_runtime_rejected(self):
        self.receipt["artifacts"].pop("VectorBreach.pck")
        with self.assertRaisesRegex(ValueError, "runtime"):
            MODULE.prepare(self.old, self.new, self.receipt)

    def test_extra_old_file_rejected(self):
        (self.new / "old.pck").touch()
        with self.assertRaisesRegex(ValueError, "only the three"):
            MODULE.prepare(self.old, self.new, self.receipt)

    def test_no_overwrite_on_second_stage(self):
        plan = MODULE.prepare(self.old, self.new, self.receipt)
        MODULE.stage(self.new, plan)
        with self.assertRaisesRegex(ValueError, "exists"):
            MODULE.stage(self.new, plan)
