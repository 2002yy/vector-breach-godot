"""Run-up replacement choice must require action, landing, corridor and controls."""

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runup_route_revision import LEVELS, choose, grid_payload


class RunupRouteRevisionTests(unittest.TestCase):
    def test_grid_preserves_target_and_uses_new_approach_geometry(self):
        record = dict(
            direction=[1, 0, 0],
            feet=[0, 0, 0],
            target_feet=[3, 1, 0],
            height_change=1,
            node=1,
        )
        source = dict(
            schema=1, level=LEVELS["mirage"], identity={}, survey=dict(rises=[record])
        )
        with (
            patch("runup_route_revision.read", return_value=source),
            patch("runup_route_revision.sha", return_value="0" * 64),
        ):
            grid = grid_payload(
                "mirage", Path("source"), Path("project"), Path("reject")
            )
        self.assertEqual(len(grid["cases"]), 3)
        for point in grid["cases"]:
            self.assertEqual(point["start"], [-0.6, 0.91, 0])
            self.assertEqual(point["target_feet"], [3, 1, 0])
            self.assertEqual(point["geometry"], record)
            self.assertEqual(point["target_radius"], 1.6)
            self.assertEqual(point["target_height_tolerance"], 0.18)

    def test_wrong_map_source_is_rejected(self):
        with patch(
            "runup_route_revision.read", return_value=dict(level=LEVELS["inferno"])
        ):
            with self.assertRaisesRegex(ValueError, "source map differs"):
                grid_payload("mirage", Path("source"), Path("project"), Path("reject"))

    def fixture(self):
        points = [
            dict(id="rise_00__current__" + mode, parent_case="rise_00", trial_mode=mode)
            for mode in ("jump", "no_jump", "walk")
        ]
        rows = {
            p["id"]: dict(ingress_corridor=dict(status="geometric_corridor_found"))
            for p in points
        }
        return dict(cases=points), rows

    def assess(
        self,
        action=True,
        landing=True,
        corridor="geometric_corridor_found",
        walking=False,
    ):
        manifest, rows = self.fixture()
        rows["rise_00__current__jump"]["ingress_corridor"]["status"] = corridor
        with (
            patch("runup_route_revision.runup_gate", return_value=dict(passed=action)),
            patch(
                "runup_route_revision.outcomes",
                side_effect=lambda point, _: dict(
                    first_landing=landing, supported_arrival=walking
                ),
            ),
        ):
            return choose(manifest, rows)

    def test_complete_genuine_candidate_is_selected(self):
        self.assertEqual(self.assess()[0], "rise_00")

    def test_failed_runup_action_cannot_be_selected(self):
        self.assertIsNone(self.assess(action=False)[0])

    def test_failed_first_landing_cannot_be_selected(self):
        self.assertIsNone(self.assess(landing=False)[0])

    def test_unproven_or_blocked_corridor_cannot_be_selected(self):
        for status in ("route_unproven", "blocked_direct_route"):
            with self.subTest(status=status):
                self.assertIsNone(self.assess(corridor=status)[0])

    def test_walking_control_cannot_receive_jump_required_credit(self):
        self.assertIsNone(self.assess(walking=True)[0])

    def test_choice_keeps_every_failed_observation(self):
        selected, records = self.assess(landing=False)
        self.assertIsNone(selected)
        self.assertEqual(len(records), 1)
        self.assertFalse(records[0]["eligible"])


if __name__ == "__main__":
    unittest.main()
