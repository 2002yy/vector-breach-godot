"""Profile inputs preserve the route and require every physical selection gate."""

import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runup_profile_inputs import (
    BRAKES,
    MODES,
    SCHEMES,
    choose,
    payload,
    source_data,
    timeline,
)


class ProfileInputTests(unittest.TestCase):
    @staticmethod
    def source():
        return dict(
            cases=[
                dict(
                    id=s + "__jump",
                    scheme=s,
                    trial_mode="jump",
                    kind="run_up",
                    start=[1, 2, 3],
                    target_feet=[4, 5, 6],
                    target_radius=1.6,
                    target_height_tolerance=0.18,
                    duration=2,
                    yaw=0,
                    geometry={"node": 1},
                    timeline=[dict(at=0, direction=[0, -1])],
                )
                for s in SCHEMES
            ]
        )

    def test_grid_changes_inputs_without_changing_target_or_source(self):
        source = self.source()
        saved = copy.deepcopy(source)
        with (
            patch("runup_profile_inputs.source_data", return_value=source),
            patch("runup_profile_inputs.sha", return_value="0" * 64),
        ):
            grid = payload(Path("source"), Path("out"), Path("project"))
        self.assertEqual(len(grid["cases"]), 18)
        self.assertEqual(source, saved)
        for point in grid["cases"]:
            parent = next(p for p in source["cases"] if p["id"] == point["source_case"])
            for field in (
                "start",
                "target_feet",
                "target_radius",
                "target_height_tolerance",
                "duration",
                "yaw",
                "geometry",
            ):
                self.assertEqual(point[field], parent[field])

    def test_walk_and_nojump_keep_event_times_and_direction(self):
        with (
            patch("runup_profile_inputs.source_data", return_value=self.source()),
            patch("runup_profile_inputs.sha", return_value="0" * 64),
        ):
            grid = payload(Path("source"), Path("out"), Path("project"))
        for scheme in SCHEMES:
            for index in range(3):
                points = {
                    p["trial_mode"]: p
                    for p in grid["cases"]
                    if p["scheme"] == scheme and p["variant"] == index
                }
                native = points["jump"]["native_timeline"]
                for mode in ("walk", "no_jump"):
                    for a, b in zip(native, points[mode]["native_timeline"]):
                        self.assertEqual(a["at"], b["at"])
                        self.assertEqual(
                            [k for k in a["keys"] if k != "Space"],
                            [k for k in b["keys"] if k != "Shift"],
                        )

    def test_modern_ground_run_extended_and_braking_bounded(self):
        for scheme, jump in (("legacy_16", 0.2), ("modern_cs", 0.25)):
            for brake in BRAKES:
                events = timeline(scheme, brake)
                self.assertEqual(
                    next(e["at"] for e in events if "Space" in e["keys"]), jump
                )
                self.assertLessEqual(sum(e["keys"] == ["S"] for e in events), 1)
                self.assertEqual(events[-1]["at"], 1.5)
        with self.assertRaisesRegex(ValueError, "unknown"):
            timeline("current", 0)

    def test_wrong_map_source_rejected_before_report_use(self):
        with patch(
            "runup_profile_inputs.read",
            return_value=dict(level="inferno", schema=4, selected="rise_05"),
        ):
            with self.assertRaisesRegex(ValueError, "Mirage"):
                source_data(Path("source"), Path("project"))

    def test_later_legacy_contract_has_three_fixed_times_without_changing_v1(self):
        with (
            patch("runup_profile_inputs.source_data", return_value=self.source()),
            patch("runup_profile_inputs.sha", return_value="0" * 64),
        ):
            original = payload(Path("source"), Path("out"), Path("project"))
            followup = payload(Path("source"), Path("out"), Path("project"), True)
        self.assertEqual(len(original["cases"]), 18)
        self.assertEqual(len(followup["cases"]), 9)
        self.assertEqual({p["scheme"] for p in followup["cases"]}, {"legacy_16"})
        self.assertEqual(
            {p["followup_jump_seconds"] for p in followup["cases"]}, {0.25, 0.3, 0.35}
        )
        for point in followup["cases"]:
            self.assertFalse(any("S" in e["keys"] for e in point["native_timeline"]))
            self.assertEqual(point["target_feet"], [4, 5, 6])
            self.assertEqual(point["start"], [1, 2, 3])
        with self.assertRaisesRegex(ValueError, "follow-up"):
            timeline("modern_cs", 0, 0.3)

    def assess(self, action=True, landing=True, clear=True, walk=False):
        data = dict(
            cases=[
                dict(id=f"{s}__brake{i}__{m}", scheme=s, variant=i, trial_mode=m)
                for s in SCHEMES
                for i in range(3)
                for m in MODES
            ]
        )
        rows = {
            p["id"]: dict(
                ingress_corridor=dict(
                    status="geometric_corridor_found" if clear else "route_unproven"
                )
            )
            for p in data["cases"]
        }
        with (
            patch("runup_profile_inputs.runup_gate", return_value=dict(passed=action)),
            patch(
                "runup_profile_inputs.outcomes",
                return_value=dict(first_landing=landing, supported_arrival=walk),
            ),
        ):
            return choose(data, rows)

    def test_selection_requires_action_landing_corridor_and_controls(self):
        self.assertEqual(self.assess()[0], {s: 0 for s in SCHEMES})
        for kwargs in (
            dict(action=False),
            dict(landing=False),
            dict(clear=False),
            dict(walk=True),
        ):
            with self.subTest(kwargs=kwargs):
                selected, records = self.assess(**kwargs)
                self.assertTrue(all(v is None for v in selected.values()))
                self.assertEqual(len(records), 6)


if __name__ == "__main__":
    unittest.main()
