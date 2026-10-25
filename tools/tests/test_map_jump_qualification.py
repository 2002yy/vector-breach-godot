"""Adversarial qualification gates on a fully arriving synthetic corpus."""

import copy
import hashlib
import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from map_jump_qualification import validate_review, validate_revision

MAPS = ("dust2", "mirage", "inferno")
KINDS = ("ordinary", "critical_landing", "edge", "run_up", "crouch_jump")


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / "frozen"
        self.directory.mkdir()
        self.manifests, self.digests = {}, {}
        self.review = {"schema": 2, "points": []}
        self.documents = {}
        for name in MAPS:
            cases = [{"id": kind, "kind": kind, "start": [0, 0.9, 0],
                      "target_feet": [1, 0, 0], "duration": 0.2,
                      "timeline": [{"at": 0, "direction": [0, -1]},
                                   {"at": 0.05, "jump": True}]} for kind in KINDS]
            manifest = {"schema": 1, "level": "synthetic-" + name, "identity": {"collision_sha256": name},
                        "cases": cases}
            path = self.directory / (name + "-manifest.json")
            path.write_text(json.dumps(manifest), encoding="utf-8")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.manifests[name], self.digests[name] = manifest, digest
            refs = []
            for rate in (60, 120):
                common = {"schema": 1, "level": manifest["level"],
                          "identity": manifest["identity"], "manifest_sha256": digest,
                          "physics_hz": rate}
                channels = dict(common, kind="map_jump_qualification_evidence_v1", points=[])
                results = []
                for point in cases:
                    controls = []
                    for mode in ("no_jump", "walk"):
                        timeline = copy.deepcopy(point["timeline"])
                        for event in timeline:
                            event.update(jump=False, walk=mode == "walk")
                        trace = [{"time": i / rate, "jumped": False} for i in range(int(0.2 * rate))]
                        controls.append({"id": point["id"], "scheme": "current", "mode": mode,
                                         "start_valid": True, "jumped": False, "target_reached": False,
                                         "applied_timeline": timeline, "trace": trace})
                    channels["points"].append({"case": point["id"], "corridor": self.corridor(point),
                                               "controls": controls})
                    for scheme in ("current", "legacy_16", "modern_cs"):
                        results.append({"id": point["id"], "scheme": scheme,
                            "target_reached": True, "reason": "reached", "start_valid": True,
                            "jumped": True, "airborne": True, "landed": True,
                            "support": [{"body": "synthetic-original-solid"}],
                            "supported_by_frozen_collision": True,
                            "trace": [{"jumped": True}], "landing_distance": 0,
                            "landing_height_error": 0})
                for suffix, data in (("channel", channels), ("jump", dict(common, results=results))):
                    file = (self.directory / f"{name}-{rate}.json" if suffix == "jump"
                            else self.root / f"{name}-{suffix}-{rate}.json")
                    relative = file.relative_to(self.root).as_posix()
                    self.documents[relative] = data
                    self.write(relative)
                    refs.append({"file": relative, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
                (self.directory / f"{name}-{rate}.json").write_text(json.dumps(dict(common, results=results)), encoding="utf-8")
            for point in cases:
                self.review["points"].append({"map": name, "case": point["id"],
                    "level": manifest["level"], "manifest_sha256": digest,
                    "status": "qualified_jump", "reason": "synthetic golden trace",
                    "evidence": copy.deepcopy(refs)})
        (self.directory / "freeze.json").write_text(json.dumps({n: {"sha256": h} for n, h in self.digests.items()}), encoding="utf-8")

    @staticmethod
    def corridor(point):
        height = 1.2 if point["kind"] == "crouch_jump" else 1.8
        arcs = []
        for lift in (0.0, 0.8, 1.2, 1.7):
            def position(t):
                return [t, height / 2 + 0.04 + 4 * lift * t * (1 - t), 0]
            segments = [{"from": position(i / 32), "to": position((i + 1) / 32),
                         "initial_clear": True, "free_fraction": 1.0, "normal": [0, 0, 0]}
                        for i in range(32)]
            arcs.append({"lift": lift, "clear": True, "steps": 32, "segments": segments})
        return {"capsule_radius": 0.4, "capsule_height": height, "foot_clearance": 0.04, "arcs": arcs}

    def write(self, name, rebind=False):
        path = self.root / name
        path.write_text(json.dumps(self.documents[name]), encoding="utf-8")
        if rebind:
            for point in self.review["points"]:
                for ref in point["evidence"]:
                    if ref["file"] == name:
                        ref["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()

    def validate(self, review=None):
        return validate_review(self.review if review is None else review, self.directory,
            self.manifests, self.digests, lambda p: json.loads(p.read_text(encoding="utf-8")))

    def test_complete_bound_corpus_accepted(self):
        self.assertTrue(self.validate()["eligible"])

    def test_aggregate_complete_cannot_certify_all_arrivals(self):
        with self.assertRaises(ValueError):
            self.validate({"complete": True})

    def test_missing_point_rejected(self):
        self.review["points"].pop()
        with self.assertRaises(ValueError): self.validate()

    def test_duplicate_point_rejected(self):
        self.review["points"][1] = copy.deepcopy(self.review["points"][0])
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_manifest_rejected(self):
        self.review["points"][0]["manifest_sha256"] = "stale"
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_map_rejected(self):
        self.review["points"][0]["level"] = "other-map"
        with self.assertRaises(ValueError): self.validate()

    def test_unbound_modified_evidence_rejected(self):
        self.documents["dust2-channel-60.json"]["level"] = "other-map"
        self.write("dust2-channel-60.json")
        with self.assertRaises(ValueError): self.validate()

    def test_rehashed_wrong_scope_rejected(self):
        self.documents["dust2-channel-60.json"]["level"] = "other-map"
        self.write("dust2-channel-60.json", True)
        with self.assertRaises(ValueError): self.validate()

    def test_missing_rate_rejected(self):
        self.review["points"][0]["evidence"].pop()
        with self.assertRaises(ValueError): self.validate()

    def test_path_escape_rejected(self):
        self.review["points"][0]["evidence"][0]["file"] = "../../outside.json"
        with self.assertRaises(ValueError): self.validate()

    def test_no_jump_failure_cannot_hide_a_jump(self):
        self.documents["dust2-channel-60.json"]["points"][0]["controls"][0]["trace"][0]["jumped"] = True
        self.write("dust2-channel-60.json", True)
        with self.assertRaises(ValueError): self.validate()

    def test_body_sweep_cannot_skip_space(self):
        self.documents["dust2-channel-60.json"]["points"][0]["corridor"]["arcs"][0]["segments"][0]["to"] = [99, 99, 99]
        self.write("dust2-channel-60.json", True)
        with self.assertRaises(ValueError): self.validate()

    def test_claimed_status_must_match_evidence(self):
        self.review["points"][0]["status"] = "walk_only"
        with self.assertRaises(ValueError): self.validate()

    def test_actual_walk_control_is_not_jump_qualification(self):
        for rate in (60, 120):
            name = f"dust2-channel-{rate}.json"
            row = self.documents[name]["points"][0]["controls"][0]
            row.update(target_reached=True, support=[{"body": "synthetic-original-solid"}],
                       supported_by_frozen_collision=True, target_entry={"grounded_after": True})
            self.write(name, True)
        self.review["points"][0]["status"] = "walk_only"
        self.assertEqual(self.validate()["validated_points"][0]["status"], "walk_only")

    def test_cli_complete_bypass_fails_even_when_all_arrive(self):
        review = self.root / "review.json"
        review.write_text('{"complete":true}', encoding="utf-8")
        script = Path(__file__).resolve().parents[1] / "validate_map_jump_audit.py"
        result = subprocess.run([sys.executable, str(script), str(self.directory), "--review",
            str(review), "--out", str(self.root / "out.json"), "--require-acceptance"], capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads((self.root / "out.json").read_text())["release_ready"])

    def test_cli_all_bound_evidence_can_pass(self):
        review = self.root / "review.json"
        review.write_text(json.dumps(self.review), encoding="utf-8")
        script = Path(__file__).resolve().parents[1] / "validate_map_jump_audit.py"
        result = subprocess.run([sys.executable, str(script), str(self.directory), "--review",
            str(review), "--out", str(self.root / "out.json"), "--require-acceptance"], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def block_corridor(self, wall):
        for rate in (60, 120):
            name = f"dust2-channel-{rate}.json"
            for arc in self.documents[name]["points"][0]["corridor"]["arcs"]:
                arc["clear"] = False
                arc["segments"] = arc["segments"][:1]
                arc["segments"][0].update(free_fraction=0.25,
                                           normal=[-1, 0, 0] if wall else [0, 1, 0])
            self.write(name, True)

    def test_blocked_point_cannot_be_released(self):
        self.block_corridor(True)
        for rate in (60, 120):
            name = f"frozen/dust2-{rate}.json"
            self.documents[name]["results"][0].update(target_reached=False, reason="outside_target")
            self.write(name, True)
        self.review["points"][0]["status"] = "blocked_direct_route"
        self.assertFalse(self.validate()["eligible"])

    def test_unproven_corridor_cannot_be_released(self):
        self.block_corridor(False)
        self.review["points"][0]["status"] = "route_unproven"
        self.assertFalse(self.validate()["eligible"])

    def test_wide_goal_success_cannot_hide_blocked_corridor(self):
        self.block_corridor(True)
        for rate in (60, 120):
            name = f"dust2-channel-{rate}.json"
            row = self.documents[name]["points"][0]["controls"][0]
            row.update(target_reached=True, support=[{"body": "synthetic"}],
                       supported_by_frozen_collision=True, target_entry={"grounded_after": True})
            self.write(name, True)
        self.review["points"][0]["status"] = "route_unproven"
        self.assertFalse(self.validate()["eligible"])

    def test_all_walk_only_cannot_certify_jumping(self):
        for name, data in self.documents.items():
            if "channel" not in name:
                continue
            for point in data["points"]:
                point["controls"][0].update(target_reached=True, support=[{"body": "synthetic"}],
                    supported_by_frozen_collision=True, target_entry={"grounded_after": True})
            self.write(name, True)
        for point in self.review["points"]:
            point["status"] = "walk_only"
        self.assertFalse(self.validate()["eligible"])

    def revision(self):
        child_dir = self.root / "v2"
        child_dir.mkdir()
        review_path = self.root / "review.json"
        review_path.write_text(json.dumps(self.review), encoding="utf-8")
        freeze = {"schema": 2, "maps": {}}
        for name, parent in self.manifests.items():
            child = {"schema": 2, "revision": "movement4-r1-qualified-v2", "level": parent["level"], "identity": parent["identity"],
                "cases": parent["cases"], "parent_manifest_sha256": self.digests[name],
                "qualification_sha256": hashlib.sha256(review_path.read_bytes()).hexdigest()}
            path = child_dir / f"{name}-manifest.json"
            path.write_text(json.dumps(child), encoding="utf-8")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            freeze["maps"][name] = {"sha256": digest}
            for rate in (60, 120):
                data = copy.deepcopy(self.documents[f"frozen/{name}-{rate}.json"])
                data["manifest_sha256"] = digest
                (child_dir / f"{name}-{rate}.json").write_text(json.dumps(data), encoding="utf-8")
        (child_dir / "freeze.json").write_text(json.dumps(freeze), encoding="utf-8")
        return child_dir, review_path

    def validate_child(self, child, review):
        return validate_revision(child, review, self.manifests, self.digests, self.validate(),
            lambda p: json.loads(p.read_text(encoding="utf-8")))

    def test_new_revision_requires_new_bound_matrix(self):
        child, review = self.revision()
        self.assertEqual(self.validate_child(child, review)["trials"], 90)

    def test_parent_matrix_cannot_certify_new_revision(self):
        child, review = self.revision()
        (child / "dust2-60.json").write_bytes((self.directory / "dust2-60.json").read_bytes())
        with self.assertRaises(ValueError): self.validate_child(child, review)

    def test_rehashed_new_inputs_cannot_reuse_old_qualification(self):
        child, review = self.revision()
        path = child / "dust2-manifest.json"
        data = json.loads(path.read_text())
        data["cases"][0]["timeline"][1]["at"] = 0.1
        path.write_text(json.dumps(data), encoding="utf-8")
        freeze = json.loads((child / "freeze.json").read_text())
        freeze["maps"]["dust2"]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        (child / "freeze.json").write_text(json.dumps(freeze), encoding="utf-8")
        with self.assertRaises(ValueError): self.validate_child(child, review)

    def test_optimized_python_still_rejects_complete_bypass(self):
        review = self.root / "review.json"
        review.write_text('{"complete":true}', encoding="utf-8")
        script = Path(__file__).resolve().parents[1] / "validate_map_jump_audit.py"
        result = subprocess.run([sys.executable, "-O", str(script), str(self.directory), "--review",
            str(review), "--out", str(self.root / "out.json"), "--require-acceptance"], capture_output=True)
        self.assertEqual(result.returncode, 1)

    def test_freezer_refuses_to_overwrite_parent(self):
        review = self.root / "review.json"
        review.write_text(json.dumps(self.review), encoding="utf-8")
        original = (self.directory / "dust2-manifest.json").read_bytes()
        script = Path(__file__).resolve().parents[1] / "freeze_qualified_map_jumps.py"
        result = subprocess.run([sys.executable, str(script), str(self.directory),
            str(review), str(self.directory)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.directory / "dust2-manifest.json").read_bytes(), original)
