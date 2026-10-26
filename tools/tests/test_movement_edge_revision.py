"""Bounded edge replacement must retain failed points and predeclare selection."""

import copy
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_ordinary_edge as fixtures
from edge_drop_revision import LIMIT, choose, grid_payload, selected_payload, shortlist


class EdgeRevisionTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.OrdinaryEdgeTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root, self.source = self.fixture.root, self.fixture.source
        self.records: list[dict[str, Any]] = [
            dict(
                node=i,
                feet=[i * 2, 0, 0],
                direction=[0, 0, -1],
                near_feet=[i * 2, -1, -1],
                target_feet=[i * 2, -1, -3],
                height_change=-1,
            )
            for i in range(12)
        ]
        self.save()

    def save(self):
        self.source.write_text(
            json.dumps(
                dict(
                    level="fixture",
                    identity={},
                    cases=self.fixture.parents,
                    survey=dict(drops=self.records),
                )
            )
        )

    def build(self):
        return grid_payload(self.source, self.root, self.root / "rejected.json")

    def test_bounded_current_only_complete_controls(self):
        result = self.build()
        self.assertEqual(len(result["cases"]), LIMIT * 3)
        self.assertEqual({p["scheme"] for p in result["cases"]}, {"current"})
        self.assertFalse(result["formal_qualification"])
        self.assertEqual(
            {p["trial_mode"] for p in result["cases"]}, {"jump", "no_jump", "walk"}
        )

    def test_shortlist_deduplicates_position_and_heading_without_reordering(self):
        duplicate = copy.deepcopy(self.records[0])
        duplicate["target_feet"][2] = -1.6
        records = [self.records[0], duplicate, self.records[1]]
        self.assertEqual([i for i, _ in shortlist(records)], [0, 2])

    def test_initial_failed_point_not_removed_by_outcome_based_filter(self):
        self.assertEqual(self.build()["cases"][0]["survey_index"], 0)

    def test_preserves_record_geometry_and_original_input_times(self):
        before = self.source.read_bytes()
        for p in self.build()["cases"]:
            record = self.records[p["survey_index"]]
            self.assertEqual(p["start"], [record["feet"][0], 0.91, 0])
            self.assertEqual(p["target_feet"], record["target_feet"])
            self.assertEqual(p["geometry"], record)
            self.assertEqual([e["at"] for e in p["native_timeline"]], [0, 0.25, 0.35])
        self.assertEqual(before, self.source.read_bytes())

    def test_non_drop_or_empty_survey_rejected(self):
        self.records[0]["height_change"] = 1
        self.save()
        with self.assertRaises(ValueError):
            self.build()
        with self.assertRaises(ValueError):
            shortlist([])

    def test_selection_uses_first_actual_drop_with_successful_action(self):
        grid = self.build()
        rows = {p["id"]: dict(candidate=p["parent_case"]) for p in grid["cases"]}
        with (
            patch("edge_drop_revision.action_gate", return_value={"passed": True}),
            patch(
                "edge_drop_revision.edge_context",
                side_effect=lambda point, control: control["candidate"] != "drop_00",
            ),
        ):
            selected, observations = choose(grid, rows)
        self.assertEqual(selected, "drop_01")
        self.assertEqual(len(observations), LIMIT)
        self.assertFalse(observations[0]["drop"])

    def test_drop_without_takeoff_cannot_be_selected(self):
        grid = self.build()
        rows = {p["id"]: {} for p in grid["cases"]}
        with (
            patch("edge_drop_revision.action_gate", return_value={"passed": False}),
            patch(
                "edge_drop_revision.edge_context",
                return_value=True,
            ),
        ):
            selected, _ = choose(grid, rows)
        self.assertIsNone(selected)

    def selected(self, choice):
        grid = self.root / "grid.json"
        report = self.root / "report.json"
        grid.write_text(json.dumps(self.build()))
        report.write_text("{}")
        with (
            patch("edge_drop_revision.checked", return_value=({}, {})),
            patch("edge_drop_revision.choose", return_value=(choice, [])),
        ):
            return selected_payload(grid, report, self.root)

    def test_exhausted_map_has_no_replay_cases_and_preserves_null_selection(self):
        result = self.selected(None)
        self.assertEqual(result["cases"], [])
        self.assertIsNone(result["selected"])

    def test_selected_point_expands_all_profiles_without_changing_geometry(self):
        result = self.selected("drop_01")
        self.assertEqual(len(result["cases"]), 9)
        self.assertEqual(
            {p["scheme"] for p in result["cases"]},
            {"current", "legacy_16", "modern_cs"},
        )
        self.assertTrue(all(p["survey_index"] == 1 for p in result["cases"]))


if __name__ == "__main__":
    unittest.main()
