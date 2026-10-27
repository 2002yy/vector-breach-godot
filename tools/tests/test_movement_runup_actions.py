"""A run-up label requires grounded movement and a genuine forward takeoff."""

import json
import math
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runup_action_completion import (
    CADENCE_PROBES,
    LEVELS,
    PROBE,
    PROBES,
    QUEUE_PROBES,
    RUNTIME,
    VARIANTS,
    control_timeline,
    native_timeline,
    payload,
    runup_gate,
    selected_payload,
    with_runup_contract,
)
from native_jump_candidates import GEOMETRY


class RunupActionTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in {
            *RUNTIME,
            *PROBES,
            *QUEUE_PROBES,
            *CADENCE_PROBES,
            PROBE,
            "project.godot",
        }:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture")
        self.point: dict[str, Any] = dict(
            id="run_up",
            kind="run_up",
            start=[0, 0.9, 0],
            target_feet=[0, 1, -2],
            target_radius=1.6,
            target_height_tolerance=0.18,
            duration=2,
            yaw=math.pi / 2,
            timeline=[
                dict(at=0, direction=[0, -1]),
                dict(at=0.35, jump=True),
                dict(at=0.45, jump=False),
                dict(at=1.5, direction=[0, 0]),
            ],
        )

    def test_all_variants_preserve_original_geometry_and_kind(self):
        source = self.root / "manifest.json"
        data = dict(schema=1, level=LEVELS["mirage"], identity={}, cases=[self.point])
        source.write_text(json.dumps(data), encoding="utf-8")
        result = payload("mirage", source, self.root, self.root / "rejected.json")
        self.assertEqual(len(result["cases"]), 27)
        self.assertEqual({p["variant"] for p in result["cases"]}, set(VARIANTS))
        for p in result["cases"]:
            self.assertEqual(p["kind"], "run_up")
            for key in GEOMETRY:
                self.assertEqual(p[key], self.point[key])
        self.assertEqual(json.loads(source.read_text()), data)

    def test_swapped_or_duplicated_map_source_and_grid_are_rejected(self):
        source = self.root / "source.json"
        for name, other in (("mirage", "inferno"), ("inferno", "mirage")):
            with self.subTest(expected=name, supplied=other):
                data = dict(
                    schema=1, level=LEVELS[other], identity={}, cases=[self.point]
                )
                source.write_text(json.dumps(data), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "source map label differs"):
                    payload(name, source, self.root, self.root / "rejected.json")
                grid = self.root / f"{name}-grid-v1.json"
                grid.write_text(json.dumps(data), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "grid map label differs"):
                    selected_payload(name, self.root, self.root)

    def test_controls_keep_direction_and_event_times(self):
        native = native_timeline(self.point, "back250_run150")
        control = control_timeline(native, "no_jump")
        walk = control_timeline(native, "walk")
        self.assertEqual([e["at"] for e in native], [e["at"] for e in control])
        self.assertEqual([e["at"] for e in native], [e["at"] for e in walk])
        self.assertTrue(all("Space" not in e["keys"] for e in control))
        self.assertTrue(all("Shift" in e["keys"] for e in walk))
        self.assertEqual(native[0]["keys"], ["S"])

    def test_unknown_input_variant_rejected(self):
        with self.assertRaises(ValueError):
            native_timeline(self.point, "later_selected")

    def row(self) -> dict[str, Any]:
        samples = [
            dict(
                time=i / 60,
                position=[-0.3 * i, 0.9, 0],
                velocity=[-1, 0, 0],
                grounded_after=True,
                jumped=False,
            )
            for i in range(3)
        ]
        samples.append(
            dict(
                time=0.05,
                position=[-0.65, 1, 0],
                velocity=[-1, 5, 0],
                grounded_after=False,
                jumped=True,
            )
        )
        return dict(trace=samples, settled_start=[0, 0.9, 0])

    def assess(self, row):
        with patch(
            "runup_action_completion.action_gate", return_value=dict(passed=True)
        ):
            return runup_gate(self.point, row, 60)

    def test_real_ground_path_forward_takeoff_meets_action_contract(self):
        result = self.assess(self.row())
        self.assertTrue(result["passed"])
        self.assertAlmostEqual(result["grounded_distance_m"], 0.6)
        self.assertAlmostEqual(result["supported_suffix_seconds"], 0.05)

    def test_holding_forward_against_wall_is_not_runup(self):
        row = self.row()
        for s in row["trace"][:3]:
            s["position"] = [0, 0.9, 0]
        self.assertFalse(self.assess(row)["passed"])

    def test_reverse_takeoff_cannot_count_as_forward_runup(self):
        row = self.row()
        row["trace"][-1]["velocity"][0] = 1
        self.assertFalse(self.assess(row)["passed"])

    def test_earlier_path_cannot_hide_lost_support_before_jump(self):
        row = self.row()
        row["trace"][1]["grounded_after"] = False
        self.assertFalse(self.assess(row)["passed"])

    def test_failed_physical_action_never_receives_category_credit(self):
        with patch(
            "runup_action_completion.action_gate", return_value=dict(passed=False)
        ):
            self.assertFalse(runup_gate(self.point, self.row(), 60)["passed"])

    def test_one_rate_runup_failure_cannot_retain_generic_route_qualification(self):
        profile = dict(status="qualified_jump", jump_route_passed=True)
        for failed_rate in ("60", "120"):
            with self.subTest(failed_rate=failed_rate):
                runup = {
                    rate: dict(passed=rate != failed_rate) for rate in ("60", "120")
                }
                result = with_runup_contract(profile, runup)
                self.assertFalse(result["category_action_passed"])
                self.assertFalse(result["jump_route_passed"])
                self.assertEqual(result["status"], "route_unproven")
        passed = with_runup_contract(
            profile, {rate: dict(passed=True) for rate in ("60", "120")}
        )
        self.assertTrue(passed["category_action_passed"])
        self.assertTrue(passed["jump_route_passed"])
        self.assertEqual(profile, dict(status="qualified_jump", jump_route_passed=True))

    def test_selection_locks_first_passing_input_and_keeps_all_controls(self):
        source = self.root / "source.json"
        source.write_text(
            json.dumps(
                dict(schema=1, level=LEVELS["mirage"], identity={}, cases=[self.point])
            )
        )
        grid = payload("mirage", source, self.root, self.root / "rejected.json")
        (self.root / "mirage-grid-v1.json").write_text(json.dumps(grid))
        (self.root / "mirage-grid-60.json").write_text("{}")
        points = {p["id"]: p for p in grid["cases"]}
        with (
            patch(
                "runup_action_completion.checked",
                return_value=(points, {key: {} for key in points}),
            ),
            patch(
                "runup_action_completion.runup_gate",
                side_effect=lambda p, *_: dict(passed=p["variant"] != "original"),
            ),
        ):
            result = selected_payload("mirage", self.root, self.root)
        self.assertEqual(len(result["cases"]), 9)
        self.assertEqual({p["variant"] for p in result["cases"]}, {"back250_run150"})
        self.assertEqual(
            {p["trial_mode"] for p in result["cases"]}, {"jump", "no_jump", "walk"}
        )


if __name__ == "__main__":
    unittest.main()
