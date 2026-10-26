"""A nearby navigation label cannot replace an observed grounded approach."""

import copy
import json
import math
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_surface_ingress as fixtures
from build_native_route_study import sha
from navigation_ingress_study import (
    PROBE,
    approach_gate,
    grid_payload,
    navigation_start,
    score,
)


class NavigationIngressTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.SurfaceIngressTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        parent = self.fixture.build()
        parent["stage"] = "ingress_selected_using60_before_holdout"
        original = parent["cases"][0]
        start, goal = original["start"], original["target_feet"]
        length = math.hypot(goal[0] - start[0], goal[2] - start[2])
        self.node = [
            start[0] - 1.2 * (goal[0] - start[0]) / length,
            start[1],
            start[2] - 1.2 * (goal[2] - start[2]) / length,
        ]
        self.layout = self.root / "data/levels/match-local/dustline.json"
        self.layout.parent.mkdir(parents=True, exist_ok=True)
        self.layout.write_text(
            json.dumps(dict(layout=dict(navigationGraph=dict(points=[self.node]))))
        )
        parent["identity"]["layout_sha256"] = sha(self.layout)
        self.source = self.root / "selected-ingress.json"
        self.source.write_text(json.dumps(parent))
        (self.root / PROBE).write_text("fixture approach probe")

    def build(self):
        return grid_payload(self.source, self.root, self.root / "reject.json")

    def test_ninety_predeclared_cases_and_negative_controls(self):
        points = self.build()["cases"]
        self.assertEqual(len(points), 90)
        self.assertEqual(len({p["id"] for p in points}), 90)
        self.assertEqual(
            {p["scheme"] for p in points}, {"current", "legacy_16", "modern_cs"}
        )
        for point in points:
            self.assertFalse(
                any(
                    "Space" in e["keys"] and e["at"] == 0
                    for e in point["native_timeline"]
                )
            )
            if point["trial_mode"] != "jump":
                self.assertFalse(
                    any("Space" in e["keys"] for e in point["native_timeline"])
                )
            if point["trial_mode"] == "walk":
                self.assertTrue(
                    all("Shift" in e["keys"] for e in point["native_timeline"])
                )

    def test_navigation_node_and_exact_previous_surface_are_preserved(self):
        before = self.source.read_bytes()
        original = json.loads(before)["cases"][0]
        result = self.build()
        for point in result["cases"]:
            self.assertEqual(point["start"], self.node)
            self.assertEqual(point["source_nav_node"], 0)
            self.assertEqual(point["target_feet"], original["target_feet"])
            self.assertEqual(point["target_radius"], original["target_radius"])
            self.assertEqual(point["approach_feet"][0::2], original["start"][0::2])
            self.assertIn("res://" + PROBE, point["probe_sha256"])
        self.assertFalse(result["formal_qualification"])
        self.assertEqual(result["spawn_to_navigation_connectivity"], "unproven")
        self.assertEqual(self.source.read_bytes(), before)

    def test_layout_drift_cannot_change_selected_node_silently(self):
        self.layout.write_text("{}")
        with self.assertRaisesRegex(ValueError, "layout drift"):
            self.build()

    def test_wrong_parent_stage_rejected(self):
        parent = json.loads(self.source.read_text())
        parent["stage"] = "not_selected"
        self.source.write_text(json.dumps(parent))
        with self.assertRaisesRegex(ValueError, "wrong ingress parent"):
            self.build()

    def test_node_policy_never_falls_back_to_nearer_lateral_or_upper_nodes(self):
        points = [
            [0, 0.91, 0.2],
            [0.2, 0.91, 1.1],
            [0, 1.2, 1.1],
            [0, 0.91, 1.8],
            [0, 0.91, 1.2],
        ]
        self.assertEqual(navigation_start(points, [0, 0.91, 0], [0, 1, -1])[0], 4)
        with self.assertRaises(ValueError):
            navigation_start(points[:3], [0, 0.91, 0], [0, 1, -1])

    def approach_fixture(self) -> tuple[dict[str, Any], dict[str, Any]]:
        point = dict(
            start=[0, 0.9, 1.2],
            approach_feet=[0, 0, 0],
            approach_radius=0.12,
            approach_height_tolerance=0.18,
            minimum_approach_travel=0.1,
        )
        row = dict(
            trace=[
                dict(
                    time=i / 60,
                    position=[0, 0.9, z],
                    grounded_after=True,
                    input=dict(jump=False),
                )
                for i, z in enumerate((1.2, 0.6, 0.05))
            ]
        )
        return point, row

    def test_grounded_progress_through_checkpoint_is_required(self):
        point, row = self.approach_fixture()
        result = approach_gate(point, row)
        self.assertTrue(result["passed"])
        self.assertGreater(result["horizontal_travel"], 1)
        self.assertAlmostEqual(result["checkpoint_time"], 2 / 60)

    def test_nearby_start_label_without_progress_does_not_count(self):
        point, row = self.approach_fixture()
        point["start"] = [0, 0.9, 0.05]
        row["trace"] = [row["trace"][-1]] * 3
        self.assertFalse(approach_gate(point, row)["passed"])

    def test_checkpoint_after_jump_is_not_a_grounded_approach(self):
        point, row = self.approach_fixture()
        row["trace"][1]["input"]["jump"] = True
        self.assertFalse(approach_gate(point, row)["passed"])

    def test_falling_or_airborne_shortcut_is_rejected(self):
        point, row = self.approach_fixture()
        row["trace"][1]["grounded_after"] = False
        self.assertFalse(approach_gate(point, row)["passed"])

    def test_checkpoint_requires_height_and_lateral_tolerance(self):
        for position in ([0, 1.2, 0.05], [0.2, 0.9, 0.05]):
            point, row = self.approach_fixture()
            row["trace"][-1]["position"] = position
            self.assertFalse(approach_gate(point, row)["passed"])

    def test_approach_sweep_binds_checkpoint_not_upper_goal(self):
        point, row = self.approach_fixture()
        point["target_feet"] = [0, 0.75, -0.8]
        row["approach_corridor"] = {}
        before = copy.deepcopy(point)
        with (
            patch("navigation_ingress_study.qualify", return_value=dict(passed=True)),
            patch(
                "navigation_ingress_study.clear_corridor", return_value=(True, False)
            ) as check,
        ):
            self.assertTrue(score(point, row, 60)["passed"])
        self.assertEqual(check.call_args.args[0]["target_feet"], point["approach_feet"])
        self.assertEqual(point, before)

    def test_ingress_success_cannot_bypass_approach_or_corridor(self):
        point, row = self.approach_fixture()
        row["approach_corridor"] = {}
        for approach, corridor, ingress in (
            (False, True, True),
            (True, False, True),
            (True, True, False),
        ):
            with (
                patch(
                    "navigation_ingress_study.qualify",
                    return_value=dict(passed=ingress),
                ),
                patch(
                    "navigation_ingress_study.approach_gate",
                    return_value=dict(passed=approach),
                ),
                patch(
                    "navigation_ingress_study.clear_corridor",
                    return_value=(corridor, False),
                ),
            ):
                self.assertFalse(score(point, copy.deepcopy(row), 60)["passed"])


if __name__ == "__main__":
    unittest.main()
