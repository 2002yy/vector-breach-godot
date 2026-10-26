"""Coverage cannot mix sites, borrow controls, or turn automatic receipts human."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import sha
from movement_evidence_bank import (
    OBSERVER,
    Sources,
    coverage,
    manual_plan,
    paired_timeline,
    profile_evidence,
    validate_manual_plan,
    validate_session_receipt,
)

SCHEMES = ("current", "legacy_16", "modern_cs")


class EvidenceBankTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / OBSERVER).parent.mkdir(parents=True)
        (self.root / OBSERVER).write_text("fixture observer")

    def point(self) -> dict[str, Any]:
        return dict(
            id="jump",
            kind="critical_landing",
            scheme="current",
            start=[0, 0.9, 0],
            yaw=0,
            target_feet=[0, 0, -1],
            target_radius=0.35,
            target_height_tolerance=0.18,
            duration=2,
            native_timeline=[
                dict(at=0, keys=["W"], mouse_dx=0),
                dict(at=0.1, keys=["W", "Space", "Ctrl"], mouse_dx=0),
            ],
        )

    def controls(self, point):
        result = {}
        for mode in ("no_jump", "walk"):
            p = copy.deepcopy(point)
            p["trial_mode"] = mode
            for e in p["native_timeline"]:
                e["keys"] = [
                    k
                    for k in e["keys"]
                    if k != "Space" and not (mode == "walk" and k == "Ctrl")
                ]
                if mode == "walk":
                    e["keys"].append("Shift")
            result[mode] = p
        return result

    def evidence(self, body=True, walking=False, change_control=False):
        p = self.point()
        p.update(complete=True, status="qualified_jump")
        if body:
            p["corridor"] = {}
        cp = self.controls(p)
        if change_control:
            cp["no_jump"]["native_timeline"][0]["keys"] = ["S"]
        rows = {r: dict(first=True, arrive=True) for r in (60, 120)}
        controls = {
            r: {m: dict(first=False, arrive=walking) for m in cp} for r in (60, 120)
        }
        with (
            patch("movement_evidence_bank.action_gate", return_value=dict(passed=True)),
            patch(
                "movement_evidence_bank.outcomes",
                side_effect=lambda _, row: dict(
                    first_landing=row["first"], supported_arrival=row["arrive"]
                ),
            ),
            patch("movement_evidence_bank.clear_corridor", return_value=(True, False)),
        ):
            return profile_evidence(p, rows, controls, cp)

    def test_matching_no_jump_and_standing_walk_are_paired(self):
        p = self.point()
        for mode, c in self.controls(p).items():
            self.assertTrue(paired_timeline(p, c, mode))

    def test_different_control_direction_or_goal_cannot_be_borrowed(self):
        p = self.point()
        c = self.controls(p)["no_jump"]
        c["target_radius"] = 1.6
        self.assertFalse(paired_timeline(p, c, "no_jump"))
        self.assertEqual(self.evidence(change_control=True)["status"], "route_unproven")

    def test_missing_body_envelope_does_not_trust_complete_or_status(self):
        r = self.evidence(body=False)
        self.assertTrue(r["action_passed"])
        self.assertFalse(r["jump_route_passed"])
        self.assertEqual(r["status"], "route_unproven")

    def test_paired_body_first_landing_and_failed_walk_can_qualify_route(self):
        self.assertEqual(self.evidence()["status"], "qualified_jump")

    def test_actual_walking_prevents_jump_required_route(self):
        r = self.evidence(walking=True)
        self.assertTrue(r["walking_observed_both_rates"])
        self.assertEqual(r["status"], "walk_only")

    def test_unpaired_walking_remains_observed_but_not_formally_qualified(self):
        r = self.evidence(walking=True, change_control=True)
        self.assertTrue(r["walking_observed_both_rates"])
        self.assertFalse(r["paired_controls_available"])
        self.assertEqual(r["status"], "route_unproven")

    def test_coverage_requires_three_profiles_on_same_frozen_site(self):
        profiles = {
            s: dict(category_action_passed=True, jump_route_passed=True)
            for s in SCHEMES
        }
        split = [
            dict(map="dust2", kind="critical_landing", profiles={s: p})
            for s, p in profiles.items()
        ]
        self.assertFalse(any(c["jump_route_covered"] for c in coverage(split)))
        full = [dict(map="dust2", kind="critical_landing", profiles=profiles)]
        c = next(
            c
            for c in coverage(full)
            if c["map"] == "dust2" and c["kind"] == "critical_landing"
        )
        self.assertTrue(c["action_covered"] and c["jump_route_covered"])
        self.assertEqual(len(coverage(full)), 15)

    def test_source_map_label_cannot_reuse_another_level(self):
        path = self.root / "manifest.json"
        path.write_text(
            json.dumps(
                dict(
                    level="inferno-classic-local",
                    identity={},
                    input_map_sha256="i",
                    runtime_sha256={},
                )
            )
        )
        source = dict(
            map="dust2", manifest=str(path), report60="unused60", report120="unused120"
        )
        with patch("movement_evidence_bank.checked", return_value=({}, {})):
            with self.assertRaisesRegex(ValueError, "map label differs"):
                Sources({"p": source}, self.root).load("p")

    def test_manual_plan_is_pending_and_cannot_be_external_complete(self):
        plan = manual_plan({"map": "hash"}, "observer")
        self.assertFalse(plan["formal_release_ready"])
        plan["complete"] = True
        with self.assertRaisesRegex(ValueError, "falsely accepted"):
            validate_manual_plan(plan, {"map": "hash"}, "observer")

    def session_fixture(self) -> tuple[Path, dict[str, Any]]:
        manifest = dict(
            identity=dict(engine_hash="engine"),
            runtime_sha256={},
            input_map_sha256="input",
            cases=[dict(parent_case="site")],
        )
        path = self.root / "manual.json"
        path.write_text(json.dumps(manifest))
        data = dict(
            manifest_sha256=sha(path),
            observer_sha256=sha(self.root / OBSERVER),
            identity=manifest["identity"],
            runtime_sha256={},
            input_map_sha256="input",
            engine_hash="engine",
            session_mode="headless_collision_logic_smoke",
            human_review="pending",
            formal_release_ready=False,
            attempts=[
                dict(
                    case="site",
                    scheme="current",
                    human_review="pending",
                    trace=[
                        dict(
                            physics_frame=1,
                            crouch_requested=True,
                            walk_requested=False,
                            grounded_before=True,
                            grounded=False,
                            capsule_height=1.2,
                        )
                    ],
                )
            ],
        )
        return path, data

    def validate(self, path, data):
        receipt = self.root / "receipt.json"
        receipt.write_text(json.dumps(data))
        return validate_session_receipt(
            receipt, path, self.root, "headless_collision_logic_smoke"
        )

    def test_automatic_receipt_records_posture_and_stays_pending(self):
        path, data = self.session_fixture()
        r = self.validate(path, data)
        self.assertEqual(r["samples"], 1)
        self.assertEqual(r["human_review"], "pending")
        self.assertFalse(r["formal_release_ready"])

    def test_missing_pose_or_fake_human_acceptance_is_rejected(self):
        path, data = self.session_fixture()
        data["attempts"][0]["trace"][0].pop("walk_requested")
        with self.assertRaises((KeyError, ValueError)):
            self.validate(path, data)
        path, data = self.session_fixture()
        data["human_review"] = "pass"
        with self.assertRaisesRegex(ValueError, "falsely accepted"):
            self.validate(path, data)

    def test_wrong_manifest_or_observer_identity_is_rejected(self):
        path, data = self.session_fixture()
        data["observer_sha256"] = "old"
        with self.assertRaisesRegex(ValueError, "identity drift"):
            self.validate(path, data)
        path, data = self.session_fixture()
        path.write_text(path.read_text() + " ")
        with self.assertRaisesRegex(ValueError, "identity drift"):
            self.validate(path, data)

    def test_unordered_frames_or_invalid_pose_cannot_be_a_receipt(self):
        path, data = self.session_fixture()
        trace = data["attempts"][0]["trace"]
        trace.append(copy.deepcopy(trace[0]))
        with self.assertRaisesRegex(ValueError, "unordered"):
            self.validate(path, data)
        path, data = self.session_fixture()
        data["attempts"][0]["trace"][0]["capsule_height"] = float("nan")
        with self.assertRaisesRegex(ValueError, "posture"):
            self.validate(path, data)


if __name__ == "__main__":
    unittest.main()
