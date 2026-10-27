"""Inferno finite selection cannot combine points or waive physical gates."""

import copy
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inferno_clear_inputs import (
    POINTS,
    VARIANTS,
    artifact_hashes,
    choose,
    payload,
    timeline,
)
from movement_evidence_bank import LEVELS


class InfernoClearInputsTests(unittest.TestCase):
    def source(self) -> dict[str, Any]:
        return dict(
            schema=4,
            level=LEVELS["inferno"],
            cases=[
                dict(
                    id=key + "__current__jump",
                    parent_case=key,
                    trial_mode="jump",
                    scheme="current",
                    start=[1, 2, 3],
                    target_feet=[4, 5, 6],
                    target_radius=1.6,
                    target_height_tolerance=0.18,
                    geometry={"node": i},
                    yaw=0,
                    timeline=[dict(at=0, direction=[0, -1])],
                )
                for i, key in enumerate(POINTS)
            ],
        )

    def grid(self) -> dict[str, Any]:
        with (
            patch("inferno_clear_inputs.read", return_value=self.source()),
            patch("inferno_clear_inputs.checked"),
            patch("inferno_clear_inputs.sha", return_value="0" * 64),
        ):
            return payload(Path("source"), Path("out"), Path("project"))

    def test_grid_is_bounded_to_original_two_points(self):
        data = self.grid()
        self.assertEqual(len(data["cases"]), 54)
        self.assertEqual({p["parent_case"] for p in data["cases"]}, set(POINTS))
        self.assertEqual(len(VARIANTS), 3)

    def test_frozen_geometry_and_target_are_preserved(self):
        for p in self.grid()["cases"]:
            parent = next(
                x
                for x in self.source()["cases"]
                if x["parent_case"] == p["parent_case"]
            )
            for field in (
                "start",
                "target_feet",
                "target_radius",
                "target_height_tolerance",
                "geometry",
                "yaw",
                "timeline",
            ):
                self.assertEqual(p[field], parent[field])

    def test_controls_are_paired_to_all_event_times_and_directions(self):
        data = self.grid()
        for jump in [p for p in data["cases"] if p["trial_mode"] == "jump"]:
            for mode in ("walk", "no_jump"):
                control = next(
                    p
                    for p in data["cases"]
                    if p["id"] == jump["id"].removesuffix("jump") + mode
                )
                for a, b in zip(jump["native_timeline"], control["native_timeline"]):
                    self.assertEqual(a["at"], b["at"])
                    self.assertEqual(
                        [k for k in a["keys"] if k != "Space"],
                        [k for k in b["keys"] if k != "Shift"],
                    )

    def assess(
        self, action=True, landing=True, clear=True, control=False, eligibility=None
    ):
        data = self.grid()
        rows = {
            p["id"]: dict(
                ingress_corridor=dict(
                    status="geometric_corridor_found" if clear else "route_unproven"
                ),
                landing_distance=0,
                landing_height_error=0,
            )
            for p in data["cases"]
        }
        with (
            patch("inferno_clear_inputs.runup_gate", return_value=dict(passed=action)),
            patch(
                "inferno_clear_inputs.outcomes",
                side_effect=lambda p, r: dict(
                    first_landing=landing and (eligibility is None or eligibility(p)),
                    supported_arrival=control,
                ),
            ),
        ):
            return choose(data, rows)

    def test_first_eligible_variant_and_first_common_point(self):
        selected, candidates, observations = self.assess()
        self.assertEqual(selected, POINTS[0])
        assert selected is not None
        assert selected is not None
        self.assertTrue(all(v == 0 for v in candidates[selected].values()))
        self.assertEqual(len(observations), 18)

    def test_no_physical_gate_can_be_waived(self):
        for kwargs in (
            dict(action=False),
            dict(landing=False),
            dict(clear=False),
            dict(control=True),
        ):
            self.assertIsNone(self.assess(**kwargs)[0])

    def test_partial_does_not_borrow_profiles_from_other_point(self):
        selected, candidates, _ = self.assess(
            eligibility=lambda p: (
                (p["parent_case"] == POINTS[0]) == (p["scheme"] == "current")
            )
        )
        self.assertEqual(selected, POINTS[0])
        assert selected is not None
        self.assertEqual(candidates[selected]["current"], 0)
        self.assertIsNone(candidates[selected]["legacy_16"])
        self.assertIsNone(candidates[selected]["modern_cs"])

    def test_complete_later_point_preferred_to_partial_first(self):
        selected, _, _ = self.assess(
            eligibility=lambda p: (
                p["parent_case"] == POINTS[1] or p["scheme"] == "current"
            )
        )
        self.assertEqual(selected, POINTS[1])

    def test_three_input_timings_are_predeclared(self):
        for i, (back, forward, air) in enumerate(VARIANTS):
            events = timeline(i)
            self.assertEqual(events[0]["keys"], ["S"])
            self.assertEqual(events[2]["at"], back + forward)
            self.assertEqual(events[4]["at"], back + forward + air)
            self.assertAlmostEqual(events[5]["at"] - events[4]["at"], 1 / 30)

    def test_source_is_not_mutated(self):
        source = self.source()
        saved = copy.deepcopy(source)
        with (
            patch("inferno_clear_inputs.read", return_value=source),
            patch("inferno_clear_inputs.checked"),
            patch("inferno_clear_inputs.sha", return_value="0" * 64),
        ):
            payload(Path("source"), Path("out"), Path("project"))
        self.assertEqual(source, saved)

    def test_derived_receipts_do_not_change_frozen_source_hashes(self):
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "grid-v1.json").write_text("{}", encoding="utf-8")
            expected = artifact_hashes(directory)
            for name in (
                "validated-summary.json",
                "composite-summary.json",
                "notes.json",
            ):
                (directory / name).write_text("{}", encoding="utf-8")
            self.assertEqual(artifact_hashes(directory), expected)
            (directory / "grid-v1.json").write_text(
                '{"changed":true}', encoding="utf-8"
            )
            self.assertNotEqual(artifact_hashes(directory), expected)


if __name__ == "__main__":
    unittest.main()
