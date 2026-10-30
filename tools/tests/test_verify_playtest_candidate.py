import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

AUTHORING = Path(__file__).parents[1] / "authoring"
sys.path.insert(0, str(AUTHORING))
SPEC = importlib.util.spec_from_file_location(
    "candidate_gate", AUTHORING / "verify_playtest_candidate.py"
)
assert SPEC and SPEC.loader
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class CandidateGateTests(unittest.TestCase):
    def test_real_git_requires_committed_runtime_and_preserves_test_wip(self):
        repo = self.root / "repo"
        repo.mkdir()

        def git(*args):
            subprocess.check_output(["git", *args], cwd=repo, stderr=subprocess.STDOUT)

        git("init", "-q")
        (repo / "project.godot").write_text("baseline\n", encoding="utf8")
        git("add", "project.godot")
        git(
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "baseline",
        )
        self.assertIn("project.godot", GATE.source_manifest(repo))
        (repo / "project.godot").write_text("changed\n", encoding="utf8")
        with self.assertRaisesRegex(ValueError, "differs from HEAD"):
            GATE.source_manifest(repo)
        git("add", "project.godot")
        # Even if worktree bytes return to HEAD, the changed index must fail.
        (repo / "project.godot").write_text("baseline\n", encoding="utf8")
        with self.assertRaisesRegex(ValueError, "differs from HEAD"):
            GATE.source_manifest(repo)
        git("reset", "-q", "HEAD", "project.godot")
        (repo / "scripts/tests").mkdir(parents=True)
        (repo / "scripts/tests/fixture.gd").write_text("test WIP\n", encoding="utf8")
        git("add", "scripts/tests/fixture.gd")
        self.assertIn("project.godot", GATE.source_manifest(repo))
        (repo / "scripts/new.gd").write_text("production WIP\n", encoding="utf8")
        git("add", "scripts/new.gd")
        with self.assertRaisesRegex(ValueError, "differs from HEAD"):
            GATE.source_manifest(repo)

    def test_untracked_production_module_cannot_be_omitted(self):
        with (
            patch.object(
                GATE.subprocess,
                "check_output",
                side_effect=[b"project.godot\0", b"scripts/ai/NewRule.gd\0"],
            ),
            self.assertRaisesRegex(ValueError, "Untracked runtime source"),
        ):
            GATE.source_manifest(Path("unused"))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.files = {}
        self.source = {"project.godot": "a" * 64}
        self.head = "b" * 40
        self.fingerprint = GATE.manifest_hash(self.source)
        for name in (
            "VectorBreach.exe",
            "VectorBreach.pck",
            "VectorBreach-radar.pck",
            "角色环境候选.cmd",
            "assets/original.glb",
        ):
            self.put(name, b"fixture")
        for map_id in ("dust2", "mirage", "inferno"):
            prefix = f"candidate-inputs/{map_id}/"
            self.put(prefix + "alignment.json", b"{}")
            row = dict(self.files[prefix + "alignment.json"], path="alignment.json")
            self.put(
                prefix + "bundle.json",
                json.dumps(
                    {"inputs": {"alignment": "alignment.json"}, "files": [row]}
                ).encode(),
            )
        self.export = {
            "runtime_source_head": self.head,
            "runtime_sources": self.source,
            "runtime_source_sha256": self.fingerprint,
            "artifacts": {
                name: row
                for name, row in self.files.items()
                if name.startswith("VectorBreach")
            },
        }
        self.write_info()

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        self.files[name] = {
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }

    def write_info(self, **changes):
        info = {
            "runtime_source_head": self.head,
            "runtime_source_sha256": self.fingerprint,
            "files": self.files,
        }
        info.update(changes)
        (self.root / "build-info.json").write_text(json.dumps(info), encoding="utf8")

    def run_gate(self):
        with (
            patch.object(GATE, "source_manifest", return_value=self.source),
            patch.object(
                GATE.subprocess, "check_output", return_value=self.head.encode()
            ),
        ):
            return GATE.verify(
                self.root, self.root, {"files": self.files}, self.export, self.head
            )

    def test_complete_receipt_consistency_not_activation(self):
        self.assertFalse(self.run_gate()["activation_allowed"])

    def test_stale_metadata_rejected(self):
        self.write_info(runtime_source_head="c" * 40)
        with self.assertRaisesRegex(ValueError, "metadata is stale"):
            self.run_gate()

    def test_source_change_after_export_rejected(self):
        self.source["scripts/new.gd"] = "c" * 64
        with self.assertRaisesRegex(ValueError, "fingerprint is stale"):
            self.run_gate()

    def test_support_missing_rejected(self):
        (self.root / "assets/original.glb").unlink()
        with self.assertRaises(FileNotFoundError):
            self.run_gate()

    def test_tampered_payload_rejected(self):
        (self.root / "VectorBreach.pck").write_bytes(b"old")
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.run_gate()

    def test_extra_old_payload_rejected(self):
        (self.root / "old.pck").write_bytes(b"stale")
        with self.assertRaisesRegex(ValueError, "Unlisted"):
            self.run_gate()

    def test_bundle_dependency_omitted_from_plan_rejected(self):
        name = "candidate-inputs/dust2/alignment.json"
        del self.files[name]
        (self.root / name).unlink()
        self.write_info()
        with self.assertRaisesRegex(ValueError, "Unbound bundle dependency"):
            self.run_gate()

    def test_old_export_cannot_claim_current_source(self):
        self.export["runtime_source_head"] = "c" * 40
        with self.assertRaisesRegex(ValueError, "head is stale"):
            self.run_gate()


if __name__ == "__main__":
    unittest.main()
