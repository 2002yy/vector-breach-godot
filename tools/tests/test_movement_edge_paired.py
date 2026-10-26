"""Braking controls preserve timeline/geometry and cannot borrow forward walking."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from edge_paired_qualification import (
    PROBES,
    REFERENCES,
    control_timeline,
    payload,
    retain_walkability,
)
from build_native_route_study import SCHEMES
from movement_evidence_bank import paired_timeline


class EdgePairedTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for p in PROBES:
            path = self.root / p
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        self.original = [
            dict(at=0, keys=["W"], mouse_dx=0),
            dict(at=0.2, keys=["W", "Space"], mouse_dx=0),
            dict(at=0.2 + 1 / 60, keys=["S"], mouse_dx=0),
            dict(at=0.3, keys=[], mouse_dx=0),
        ]

    def test_jump_inputs_preserved(self):
        self.assertEqual(control_timeline(self.original, "jump"), self.original)

    def test_no_jump_preserves_switch_times_and_reverse(self):
        result = control_timeline(self.original, "no_jump")
        self.assertEqual([e["at"] for e in result], [e["at"] for e in self.original])
        self.assertEqual(result[2]["keys"], ["S"])
        self.assertFalse(any("Space" in e["keys"] for e in result))
        self.assertIn("Space", self.original[1]["keys"])

    def test_standing_walk_strips_crouch_and_jump(self):
        self.original[1]["keys"].append("Ctrl")
        result = control_timeline(self.original, "walk")
        self.assertTrue(
            all(
                "Shift" in e["keys"]
                and "Ctrl" not in e["keys"]
                and "Space" not in e["keys"]
                for e in result
            )
        )
        self.assertIn("Ctrl", self.original[1]["keys"])

    def test_unknown_mode_rejected(self):
        with self.assertRaisesRegex(ValueError, "mode"):
            control_timeline(self.original, "other")

    def test_braking_failure_cannot_turn_known_walking_into_jump_necessity(self):
        paired = dict(status="qualified_jump", jump_route_passed=True)
        result = retain_walkability(
            paired,
            {60: dict(no_jump=True, walk=False), 120: dict(no_jump=True, walk=False)},
        )
        self.assertEqual(result["paired_input_route_status"], "qualified_jump")
        self.assertEqual(result["geometry_role"], "walk_only")
        self.assertFalse(result["jump_route_passed"])
        self.assertFalse(result["jump_necessity_accepted"])

    def test_one_rate_walk_context_does_not_erase_pending(self):
        result = retain_walkability(
            dict(status="route_unproven", jump_route_passed=False),
            {60: dict(no_jump=True), 120: dict(no_jump=False)},
        )
        self.assertEqual(result["status"], "route_unproven")

    def sources(self):
        point: dict[str, Any] = dict(
            kind="edge",
            trial_mode="jump",
            scheme="current",
            start=[0, 0.9, 0],
            yaw=0,
            target_feet=[0, -1, -2],
            target_radius=1.6,
            target_height_tolerance=0.18,
            duration=2,
            native_timeline=self.original,
            probe_sha256={},
        )
        providers = {}
        allpoints = {}
        for scheme, (family, case) in REFERENCES.items():
            allpoints[case] = dict(copy.deepcopy(point), scheme=scheme, id=case)
            path = self.root / (family + ".json")
            data = dict(
                schema=4,
                identity={},
                runtime_sha256={},
                input_map_sha256="fixture",
                cases=[],
            )
            path.write_text(json.dumps(data), encoding="utf-8")
            for rate in (60, 120):
                (self.root / f"{family}-{rate}.json").write_text("{}")
            providers[family + "/dust2"] = dict(
                manifest=str(path),
                report60=str(self.root / f"{family}-60.json"),
                report120=str(self.root / f"{family}-120.json"),
            )
        return dict(providers=providers), allpoints

    def test_three_profiles_and_two_controls_each(self):
        config, points = self.sources()
        with patch("edge_paired_qualification.checked", return_value=(points, {})):
            data = payload("dust2", config, self.root, self.root / "rejected.json")
        self.assertEqual(len(data["cases"]), 9)
        self.assertEqual({p["scheme"] for p in data["cases"]}, set(SCHEMES))
        for scheme in SCHEMES:
            cases = {p["trial_mode"]: p for p in data["cases"] if p["scheme"] == scheme}
            for mode in ("no_jump", "walk"):
                self.assertTrue(paired_timeline(cases["jump"], cases[mode], mode))

    def test_different_profile_goal_cannot_share_body_proof(self):
        config, points = self.sources()
        points["modern_cs__brake_2"]["target_radius"] = 2
        with patch("edge_paired_qualification.checked", return_value=(points, {})):
            with self.assertRaisesRegex(ValueError, "geometries"):
                payload("dust2", config, self.root, self.root / "reject.json")

    def test_role_relabel_rejected(self):
        config, points = self.sources()
        points["legacy_16__reverse_010"]["kind"] = "ordinary"
        with patch("edge_paired_qualification.checked", return_value=(points, {})):
            with self.assertRaisesRegex(ValueError, "relabelled"):
                payload("dust2", config, self.root, self.root / "reject.json")


if __name__ == "__main__":
    unittest.main()
