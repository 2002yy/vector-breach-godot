"""Freeze specific action inputs and reject category claims without physical context."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from native_jump_candidates import GEOMETRY, RUNTIME, outcomes
from ordinary_edge_actions import (
    CADENCE_PROBES,
    PROBES,
    QUEUE_PROBES,
    edge_context,
    payload,
)


class OrdinaryEdgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for relative in (
            *RUNTIME,
            *PROBES,
            *QUEUE_PROBES,
            *CADENCE_PROBES,
            "project.godot",
        ):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        self.parents: list[dict[str, Any]] = [
            dict(
                id=kind,
                kind=kind,
                start=[0, 0.9, 0],
                target_feet=[0, 0, -2],
                yaw=0,
                duration=2,
                target_radius=0.35,
                target_height_tolerance=0.18,
                geometry=dict(feet=[0, 0, 0], near_feet=[0, -1, -1]),
                timeline=[
                    dict(at=0, direction=[0, 0] if kind == "ordinary" else [0, -1]),
                    dict(at=0.25, jump=True),
                    dict(at=0.35, jump=False),
                ],
            )
            for kind in ("ordinary", "edge")
        ]
        self.source = self.root / "source.json"
        self.save()

    def save(self):
        self.source.write_text(
            json.dumps(dict(level="fixture", identity={}, cases=self.parents))
        )

    def build(self):
        return payload(self.source, self.root, self.root / "rejected.json")

    def test_matrix_has_all_profiles_and_two_distinct_controls(self):
        manifest = self.build()
        self.assertEqual(len(manifest["cases"]), 18)
        self.assertEqual(len({p["id"] for p in manifest["cases"]}), 18)
        self.assertFalse(manifest["formal_qualification"])
        self.assertFalse(manifest["native_acceptance"])

    def test_freeze_preserves_source_geometry_and_timing(self):
        before = self.source.read_bytes()
        for point in self.build()["cases"]:
            parent = next(p for p in self.parents if p["id"] == point["parent_case"])
            self.assertEqual(
                [point[k] for k in GEOMETRY], [parent[k] for k in GEOMETRY]
            )
            self.assertEqual(point["geometry"], parent["geometry"])
            self.assertEqual(
                [e["at"] for e in point["native_timeline"]], [0, 0.25, 0.35]
            )
        self.assertEqual(before, self.source.read_bytes())

    def test_stationary_ordinary_cannot_silently_use_runup(self):
        self.parents[0]["timeline"][0]["direction"] = [0, -1]
        self.save()
        with self.assertRaises(ValueError):
            self.build()

    def test_duplicate_or_missing_source_category_rejected(self):
        self.parents[1] = copy.deepcopy(self.parents[0])
        self.save()
        with self.assertRaises(ValueError):
            self.build()

    def test_controls_remove_jump_and_walk_adds_shift(self):
        for point in self.build()["cases"]:
            if point["trial_mode"] != "jump":
                self.assertFalse(
                    any("Space" in e["keys"] for e in point["native_timeline"])
                )
            if point["trial_mode"] == "walk":
                self.assertTrue(
                    all("Shift" in e["keys"] for e in point["native_timeline"])
                )

    def control(self) -> dict[str, Any]:
        return dict(
            start_valid=True,
            settled_start=[0, 0.9, 0],
            trace=[
                dict(
                    position=[0, 0.9, 0],
                    velocity=[0, 0, 0],
                    grounded_before=True,
                    grounded_after=True,
                    jumped=False,
                    input=dict(jump=False),
                ),
                dict(
                    position=[0, -0.1, -1],
                    velocity=[0, -2, 0],
                    grounded_before=False,
                    grounded_after=False,
                    jumped=False,
                    input=dict(jump=False),
                ),
            ],
        )

    def test_edge_label_requires_actual_unjumped_loss_of_support_and_drop(self):
        row = self.control()
        self.assertTrue(edge_context(self.parents[1], row))
        row["trace"][1]["grounded_after"] = True
        self.assertFalse(edge_context(self.parents[1], row))

    def test_labelled_edge_without_height_drop_does_not_qualify(self):
        row = self.control()
        row["trace"][1]["position"][1] = 0.8
        self.assertFalse(edge_context(self.parents[1], row))

    def test_jump_contaminated_edge_control_rejected(self):
        row = self.control()
        row["trace"][1]["jumped"] = True
        with self.assertRaises(ValueError):
            edge_context(self.parents[1], row)

    def test_positive_walk_arrival_is_control_success_not_missing_jump(self):
        for mode in ("no_jump", "walk"):
            point = dict(self.parents[0], trial_mode=mode, target_feet=[0, 0, 0])
            sample = dict(
                position=[0, 0.9, 0], grounded_after=True, jumped=False, time=0
            )
            row: dict[str, Any] = dict(
                trace=[sample],
                goal_entry_support=[dict(normal=[0, 1, 0], body="original")],
                target_entry=sample,
                landing=sample,
                start_valid=True,
                support=[{}],
                route_arrival_reached=True,
                target_reached=True,
            )
            self.assertTrue(outcomes(point, row)["supported_arrival"])
            row["trace"][0]["jumped"] = True
            with self.assertRaises(ValueError):
                outcomes(point, row)


if __name__ == "__main__":
    unittest.main()
