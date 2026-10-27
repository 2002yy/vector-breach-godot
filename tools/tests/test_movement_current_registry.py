"""Current registry cannot inflate jump coverage with walking or mixed targets."""

import copy
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import SCHEMES
from movement_current_registry import (
    JUMP_KINDS,
    KINDS,
    LEVELS,
    build_registry,
    select_categories,
    selected_controls,
    verify_registry,
)


class CurrentRegistryTests(unittest.TestCase):
    def sites(self) -> list[dict[str, Any]]:
        point = dict(
            start=[0, 0.9, 0],
            yaw=0,
            target_feet=[0, 1, -1],
            target_radius=0.35,
            target_height_tolerance=0.18,
            duration=1.5,
        )
        return [
            dict(
                map=name,
                kind=kind,
                site=kind + "__b",
                profiles={
                    scheme: dict(
                        point=copy.deepcopy(point),
                        category_action_passed=True,
                        body_envelope_available=True,
                        paired_controls_available=True,
                        first_landings={"60": True, "120": True},
                        status="qualified_jump" if kind in JUMP_KINDS else "walk_only",
                    )
                    for scheme in SCHEMES
                },
            )
            for name in LEVELS
            for kind in KINDS
        ]

    def test_nine_jump_categories_and_six_walk_categories(self):
        selected, archive, categories = select_categories(self.sites())
        self.assertEqual((len(selected), len(archive), len(categories)), (15, 0, 15))
        self.assertEqual(sum(c["jump_required"] for c in categories), 9)
        self.assertEqual(sum(c["status"] == "walk_only" for c in categories), 6)

    def test_duplicate_uses_lexical_order_not_input_order(self):
        sites = self.sites()
        earlier = copy.deepcopy(sites[0])
        earlier["site"] = "critical_landing__a"
        selected, archive, _ = select_categories(sites + [earlier])
        self.assertEqual(selected[0]["site"], earlier["site"])
        self.assertEqual(archive[0]["site"], sites[0]["site"])

    def test_weaker_lexical_first_does_not_replace_strong(self):
        sites = self.sites()
        weaker = copy.deepcopy(sites[0])
        weaker["site"] = "a"
        weaker["profiles"]["current"]["paired_controls_available"] = False
        selected, _, _ = select_categories(sites + [weaker])
        self.assertEqual(selected[0]["site"], sites[0]["site"])

    def test_one_failed_rate_keeps_category_unproven(self):
        sites = self.sites()
        sites[0]["profiles"]["legacy_16"]["first_landings"]["120"] = False
        self.assertEqual(select_categories(sites)[2][0]["status"], "unproven")

    def test_incomplete_rate_evidence_is_not_vacuously_qualified(self):
        for landings in ({}, {"60": True}, {"60": True, "120": True, "240": True}):
            with self.subTest(landings=landings):
                sites = self.sites()
                sites[0]["profiles"]["current"]["first_landings"] = landings
                self.assertEqual(select_categories(sites)[2][0]["status"], "unproven")

    def control_cases(self):
        point = self.sites()[0]["profiles"]["current"]["point"]
        point.update(
            id="queued__current__jump",
            parent_case="frozen-parent",
            kind="critical_landing",
            scheme="current",
            queued_input=True,
            trial_mode="jump",
            native_timeline=[dict(at=0, keys=["W", "Space"])],
        )
        controls = [
            dict(
                point,
                id=f"queued__current__{mode}",
                trial_mode=mode,
                native_timeline=[dict(at=0, keys=keys)],
            )
            for mode, keys in (("no_jump", ["W"]), ("walk", ["W", "Shift"]))
        ]
        return point, controls

    def test_controls_do_not_borrow_identical_native_or_other_parent_case(self):
        point, controls = self.control_cases()
        other_family = [
            dict(p, id="native__" + p["id"], queued_input=False) for p in controls
        ]
        other_parent = [
            dict(p, id="other__" + p["id"], parent_case="other") for p in controls
        ]
        self.assertEqual(
            selected_controls(point, controls + other_family + other_parent),
            {p["trial_mode"]: p["id"] for p in controls},
        )

    def test_controls_reject_missing_or_same_family_duplicate(self):
        point, controls = self.control_cases()
        for cases in (controls[:1], controls + [dict(controls[0], id="duplicate")]):
            with self.subTest(cases=cases):
                with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
                    selected_controls(point, cases)

    def test_control_id_cannot_hide_timeline_or_kind_mismatch(self):
        point, controls = self.control_cases()
        for changes in (
            dict(kind="ordinary"),
            dict(native_timeline=[dict(at=0, keys=["S"])]),
            dict(scheme="modern_cs"),
        ):
            with self.subTest(changes=changes):
                with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
                    selected_controls(
                        point, [dict(controls[0], **changes), controls[1]]
                    )

    def test_no_cross_profile_target_borrowing(self):
        sites = self.sites()
        sites[0]["profiles"]["modern_cs"]["point"]["target_radius"] = 1.5
        with self.assertRaisesRegex(ValueError, "geometry differs"):
            select_categories(sites)

    def test_experimental_scheme_rejected(self):
        sites = self.sites()
        sites[0]["profiles"]["modern_support_candidate"] = copy.deepcopy(
            sites[0]["profiles"]["modern_cs"]
        )
        with self.assertRaisesRegex(ValueError, "formal schemes"):
            select_categories(sites)

    def test_walking_cannot_be_promoted_to_jump_route(self):
        sites = self.sites()
        sites[3]["profiles"]["current"]["status"] = "qualified_jump"
        category = select_categories(sites)[2][3]
        self.assertEqual(category["status"], "unproven")
        self.assertFalse(category["jump_required"])

    def test_missing_map_category_rejected(self):
        with self.assertRaisesRegex(ValueError, "no source"):
            select_categories(self.sites()[:-1])

    def test_registry_recomputed_before_acceptance_and_frozen(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "registry.json"
            value = dict(config={"schema": 1}, source_lock={})
            with patch("movement_current_registry.compose", return_value=value):
                build_registry(path, value["config"], Path(directory))
                self.assertEqual(verify_registry(path, Path(directory)), value)
            with patch(
                "movement_current_registry.compose",
                return_value=dict(value, human_acceptance=True),
            ):
                with self.assertRaisesRegex(ValueError, "registry changed"):
                    verify_registry(path, Path(directory))


if __name__ == "__main__":
    unittest.main()
