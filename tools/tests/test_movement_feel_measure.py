import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import movement_feel_measure as measure


def sample(tick, name="run", rate=60) -> dict[str, Any]:
    moving = tick > round(rate * 0.25) and name not in ("jump", "crouch_jump")
    direction = [0, -1] if moving else [0, 0]
    velocity = [0, 0, -5.0 if moving else 0.0]
    if name in ("release", "reverse") and tick > round(rate * 1.75):
        direction = [0, 1] if name == "reverse" else [0, 0]
        velocity[2] = 1.0 if name == "reverse" else 0.0
    jump_tick = round(rate * 0.5) + 2
    jumped = name in ("jump", "crouch_jump") and tick == jump_tick
    foot = (
        1.0
        if name in ("jump", "crouch_jump") and jump_tick <= tick < jump_tick + 10
        else 0.0
    )
    return dict(
        tick=tick,
        delta=1 / rate,
        direction=direction,
        position=[0, foot + 0.9, -tick * 5 / rate],
        velocity=velocity,
        foot_y=foot,
        foot_before=0.0,
        jump_requested=jumped,
        jumped=jumped,
        grounded_before=True,
        grounded=foot == 0.0,
        crouching=name in ("crouch", "crouch_jump") and tick > round(rate * 0.25),
        walking=name == "walk" and tick > round(rate * 0.25),
        weapon_id="sniper" if name.startswith("awp") else "rifle",
        scoped=name == "awp_scoped",
        fov=28.0 if name == "awp_scoped" else 75.0,
        speed_limit=5.0,
    )


def report() -> dict[str, Any]:
    return dict(
        schema=1,
        kind="synthetic_flat_real_player_measurement",
        physics_rate=60,
        input_mode="synthetic_action_press_parent_physics",
        human_review="pending",
        formal_release_ready=False,
        foot_definition="collision_shape_global_y_minus_half_current_capsule_height",
        airtime_definition="end_of_first_grounded_sample_minus_start_of_jump_sample",
        fixture=dict(floor_size=[200, 1, 200], floor_top_y=0.0),
        source_lock={name: "fake" for name in measure.SOURCES},
        rows=[
            dict(
                scheme=scheme,
                case=name,
                trace=[
                    sample(i, name)
                    for i in range(1, 241 if name in ("release", "reverse") else 151)
                ],
            )
            for scheme in measure.SCHEMES
            for name in measure.CASES
        ],
    )


class MovementFeelMeasureTests(unittest.TestCase):
    def test_valid_report_has_actual_speed_and_no_human_pass(self):
        result = measure.validate(report())
        self.assertEqual(len(result["rows"]), 27)
        self.assertEqual(result["rows"][0]["metrics"]["measured_speed_mps"], 5.0)
        self.assertFalse(result["formal_release_ready"])
        self.assertEqual(result["human_review"], "pending")

    def test_missing_source_is_rejected(self):
        data = report()
        data["source_lock"].pop("scripts/player/ClassicMovementRules.gd")
        with self.assertRaisesRegex(ValueError, "source identity"):
            measure.validate(data)

    def test_mixed_rate_is_rejected(self):
        data = report()
        data["rows"][0]["trace"][10]["delta"] = 1 / 120
        with self.assertRaisesRegex(ValueError, "clock"):
            measure.validate(data)

    def test_missing_or_duplicate_tick_is_rejected(self):
        data = report()
        data["rows"][0]["trace"][10]["tick"] = 10
        with self.assertRaisesRegex(ValueError, "unordered"):
            measure.validate(data)

    def test_frozen_input_changes_are_rejected(self):
        data = report()
        data["rows"][0]["trace"][20]["direction"] = [1, 0]
        with self.assertRaisesRegex(ValueError, "direction drift"):
            measure.validate(data)

    def test_scope_truth_and_fov_are_checked(self):
        data = report()
        data["rows"][8]["trace"][10]["fov"] = 75.0
        with self.assertRaisesRegex(ValueError, "FOV"):
            measure.validate(data)

    def test_jump_height_uses_pre_takeoff_feet_and_includes_landing_tick(self):
        row = report()["rows"][5]
        result = measure.metrics(row, 60)
        self.assertEqual(result["height_m"], 1.0)
        self.assertAlmostEqual(result["airtime_s"], 11 / 60)

    def test_jump_without_support_or_landing_is_rejected(self):
        row = report()["rows"][5]
        row["trace"][31]["grounded_before"] = False
        with self.assertRaisesRegex(ValueError, "unsupported"):
            measure.metrics(row, 60)
        row = report()["rows"][5]
        for s in row["trace"][32:]:
            s["grounded"] = False
        with self.assertRaisesRegex(ValueError, "did not land"):
            measure.metrics(row, 60)

    def test_unstable_stop_initial_speed_is_not_a_comparison(self):
        row = report()["rows"][3]
        row["trace"][100]["velocity"][2] = -4.0
        with self.assertRaisesRegex(ValueError, "stable moving"):
            measure.metrics(row, 60)

    def test_nonsteady_speed_cannot_be_called_maximum(self):
        row = report()["rows"][0]
        row["trace"][-1]["velocity"][2] = -4.0
        with self.assertRaisesRegex(ValueError, "steady state"):
            measure.metrics(row, 60)

    def test_derived_metrics_are_recomputed_not_trusted(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            data = report()
            (directory / "raw.json").write_text(json.dumps(data), encoding="utf-8")
            (directory / "metrics.json").write_text("{}", encoding="utf-8")
            with patch.object(measure, "sha", return_value="fake"):
                with self.assertRaisesRegex(ValueError, "derived metrics"):
                    measure.verify_directory(directory, directory)


if __name__ == "__main__":
    unittest.main()
