"""Bounded-input and same-frame first-support gates, without external map evidence."""

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mirage_support_inputs import (
    MODES,
    payload,
    require_first_support_event,
    versioned_input_set,
    check_named_source,
)
from movement_evidence_bank import LEVELS, geometry_matches, paired_timeline


class MirageSupportInputsTests(unittest.TestCase):
    def make_payload(self, root) -> tuple[dict[str, Any], dict[str, Any]]:
        point = dict(
            start=[0, 1, 0],
            yaw=0,
            target_feet=[0, 0, -3],
            target_radius=1.6,
            target_height_tolerance=0.18,
            duration=2,
            scheme="modern_cs",
            geometry={"frozen": True},
            support_enabled=True,
            vertical_enabled=True,
            quadrature_enabled=True,
        )
        cases: list[dict[str, Any]] = [
            dict(copy.deepcopy(point), id="support__" + m, trial_mode=m) for m in MODES
        ]
        data = dict(cases=cases, formal_qualification=False, level=LEVELS["mirage"])
        (root / "mirage-matrix-v1.json").write_text(json.dumps(data), encoding="utf-8")
        for rate in (60, 120):
            (root / f"mirage-{rate}.json").write_text("{}", encoding="utf-8")
        return data, payload(root, root / "new")

    def test_predeclared_three_variants_and_exact_controls(self):
        with tempfile.TemporaryDirectory() as temp:
            old, new = self.make_payload(Path(temp))
            self.assertEqual(len(new["cases"]), 9)
            self.assertEqual(new["new_trial_limit"], 18)
            for index, ticks in enumerate((1, 2, 3)):
                jump, no_jump, walk = new["cases"][index * 3 : index * 3 + 3]
                self.assertAlmostEqual(
                    jump["native_timeline"][2]["at"], 0.35 + ticks / 60
                )
                self.assertTrue(paired_timeline(jump, no_jump, "no_jump"))
                self.assertTrue(paired_timeline(jump, walk, "walk"))
                self.assertTrue(geometry_matches(jump, old["cases"][0]))
                self.assertEqual(jump["target_radius"], 1.6)
            self.assertNotIn("native_timeline", old["cases"][0])

    def test_mismatched_control_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            _, new = self.make_payload(Path(temp))
            jump, control = new["cases"][:2]
            control["native_timeline"][2]["at"] += 1 / 60
            self.assertFalse(paired_timeline(jump, control, "no_jump"))

    def test_named_map_and_live_producer_identity_required(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            probe = root / "probe.gd"
            probe.write_text("old", encoding="utf-8")
            from build_native_route_study import sha

            data = dict(
                level=LEVELS["mirage"],
                cases=[dict(probe_sha256={"res://probe.gd": sha(probe)})],
            )
            check_named_source(data, "mirage", root)
            with self.assertRaisesRegex(ValueError, "named map"):
                check_named_source(data, "inferno", root)
            probe.write_text("changed", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "probe drift"):
                check_named_source(data, "mirage", root)

    def test_first_support_event_same_frame(self):
        row = dict(landing_events=1, grounded_before=False, grounded_after=True)
        require_first_support_event(row)
        for change in (
            dict(landing_events=0),
            dict(landing_events=2),
            dict(grounded_before=True),
            dict(grounded_after=False),
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                require_first_support_event(dict(row, **change))

    def test_versioned_aggregate_preserves_failure_and_denies_global_authority(self):
        rates = {r: dict(first_landing=True) for r in ("60", "120")}
        old = {name: copy.deepcopy(rates) for name in ("dust2", "inferno")}
        result = versioned_input_set(rates, old)
        self.assertEqual(result["first_landing_count"], 6)
        self.assertFalse(result["formal_release_ready"])
        self.assertFalse(result["original_frozen_input_set_replaced"])
        old["inferno"]["120"]["first_landing"] = False
        self.assertEqual(versioned_input_set(rates, old)["first_landing_count"], 5)
        with self.assertRaises(ValueError):
            versioned_input_set({"60": dict(first_landing=True)}, old)


if __name__ == "__main__":
    unittest.main()
