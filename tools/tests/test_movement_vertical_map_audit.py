"""Vertical candidate matrix isolates the new rule and rejects mismatched evidence."""

import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from vertical_candidate_map_audit import (
    LEVELS,
    MODES,
    PROBES,
    check_vertical_receipt,
    delta_summary,
    payload,
    selected_source,
)


class VerticalMapAuditTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in PROBES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture", encoding="utf-8")

    @staticmethod
    def source() -> dict[str, Any]:
        return dict(
            schema=4,
            formal_qualification=False,
            level=LEVELS["mirage"],
            cases=[
                dict(
                    id="candidate__" + mode,
                    scheme="modern_cs",
                    queued_input=True,
                    quadrature_enabled=True,
                    trial_mode=mode,
                    start=[0, 1, 0],
                    target_feet=[0, 1, -2],
                    yaw=0,
                    duration=2,
                    target_radius=0.3,
                    target_height_tolerance=0.18,
                    native_timeline=[
                        dict(
                            at=0,
                            keys=["W", "Space"]
                            if mode == "jump"
                            else ["W", "Shift"]
                            if mode == "walk"
                            else ["W"],
                            mouse_dx=0,
                        )
                    ],
                    probe_sha256={},
                )
                for mode in MODES
            ],
        )

    def test_wrong_map_cannot_be_relabelled(self):
        with self.assertRaisesRegex(ValueError, "map label"):
            selected_source(self.source(), "inferno")

    def test_every_control_required(self):
        source = self.source()
        source["cases"].pop()
        with self.assertRaisesRegex(ValueError, "complete"):
            selected_source(source, "mirage")

    def test_horizontal_off_cannot_be_vertical_baseline(self):
        source = self.source()
        source["cases"][0]["quadrature_enabled"] = False
        with self.assertRaisesRegex(ValueError, "horizontal-on"):
            selected_source(source, "mirage")

    def test_source_control_geometry_and_timeline_stay_paired(self):
        for mutation in ("geometry", "timeline"):
            source = self.source()
            if mutation == "geometry":
                source["cases"][1]["target_feet"][0] = 1
            else:
                source["cases"][1]["native_timeline"][0]["at"] = 0.1
            with (
                self.subTest(mutation=mutation),
                self.assertRaisesRegex(ValueError, "paired"),
            ):
                selected_source(source, "mirage")

    def test_payload_varies_only_vertical_rule_and_preserves_source(self):
        directory = self.root / "sources/mirage"
        directory.mkdir(parents=True)
        source = self.source()
        path = directory / "matrix-v1.json"
        path.write_text(json.dumps(source), encoding="utf-8")
        for rate in (60, 120):
            (directory / f"{rate}.json").write_text("{}", encoding="utf-8")
        result = payload(
            "mirage", self.root / "sources", self.root, self.root / "rejected.json"
        )
        self.assertEqual(len(result["cases"]), 6)
        self.assertTrue(all(p["quadrature_enabled"] for p in result["cases"]))
        self.assertEqual(sum(p["vertical_enabled"] for p in result["cases"]), 3)
        self.assertEqual(json.loads(path.read_text()), source)
        for point in result["cases"]:
            original = next(
                p for p in source["cases"] if p["id"] == point["source_case"]
            )
            self.assertEqual(point["native_timeline"], original["native_timeline"])
            self.assertEqual(point["start"], original["start"])

    @staticmethod
    def receipt() -> dict[str, Any]:
        return dict(
            velocity=[0, 4.8, 0],
            jumped=False,
            grounded_before=False,
            grounded_after=False,
            vertical=dict(
                enabled=True,
                phase="postkick",
                delta=1 / 60,
                gravity=12,
                start_velocity_y=5,
                motion_velocity_y=4.9,
                endpoint_velocity_y=4.8,
            ),
        )

    def test_half_kicks_and_persisted_velocity_verified(self):
        check_vertical_receipt(self.receipt(), True, 60)
        for field in ("motion_velocity_y", "endpoint_velocity_y"):
            sample = self.receipt()
            sample["vertical"][field] += 0.1
            with (
                self.subTest(field=field),
                self.assertRaisesRegex(ValueError, "differs"),
            ):
                check_vertical_receipt(sample, True, 60)

    def test_collision_reset_preserves_observed_endpoint(self):
        sample = self.receipt()
        sample["vertical"].update(phase="collision_reset", endpoint_velocity_y=0)
        sample["velocity"][1] = 0
        check_vertical_receipt(sample, True, 60)

    def test_phase_cannot_bypass_physics_state_or_jump_receipt(self):
        for kind in ("grounded", "floor", "jump"):
            sample = self.receipt()
            if kind == "grounded":
                sample["vertical"]["phase"] = "grounded"
            elif kind == "floor":
                sample["grounded_after"] = True
            else:
                sample["jumped"] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                check_vertical_receipt(sample, True, 60)

    def test_landing_times_use_physics_end_not_start_labels(self):
        rows = {
            r: dict(
                landing=dict(time=t, position=[0, 0, 0]),
                trace=[dict(position=[0, 1, 0], jumped=False)],
            )
            for r, t in ((60, 0.5), (120, 0.5))
        }
        self.assertAlmostEqual(
            delta_summary(rows)["landing_physics_end_delta_seconds"], 1 / 120
        )

    def test_common_air_states_compare_equal_endpoints(self):
        rows = {}
        for rate in (60, 120):
            trace = []
            for i in range(rate // 2):
                end = (i + 1) / rate
                trace.append(
                    dict(
                        time=i / rate,
                        jumped=i == 0,
                        grounded_after=False,
                        position=[0, 1 + 5 * end - 6 * end**2, 0],
                        velocity=[0, 5 - 12 * end, 0],
                    )
                )
            rows[rate] = dict(trace=trace, landing=dict(time=0.5, position=[0, 0, 0]))
        common = delta_summary(rows)["common_air_end_states"]
        self.assertEqual(len(common), 3)
        for values in common.values():
            self.assertAlmostEqual(values["y_delta_m"], 0)
            self.assertAlmostEqual(values["vertical_velocity_delta_mps"], 0)


if __name__ == "__main__":
    unittest.main()
