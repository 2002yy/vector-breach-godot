"""Recovered geometry cannot import old controls, cadence, or release authority."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native_route_study import sha
from movement_corridor_provenance import attach, historical_category, load_channels


class CorridorProvenanceTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.point: dict[str, Any] = dict(
            id="ordinary",
            kind="ordinary",
            start=[0, 0.9, 0],
            target_feet=[1, 0, 0],
            yaw=0,
            duration=2,
            target_radius=0.35,
            target_height_tolerance=0.18,
            scheme="current",
            parent_case="ordinary",
            trial_mode="jump",
            native_timeline=[dict(at=0, keys=["Space", "Ctrl"], mouse_dx=0)],
        )
        self.identity = dict(engine_hash="fixture", collision_sha256="fixture")
        self.manifest: dict[str, Any] = dict(
            schema=1, level="fixture", identity=self.identity, cases=[self.point]
        )
        self.path = self.root / "manifest.json"
        self.write(self.path, self.manifest)
        self.reports = {}
        for rate in (60, 120):
            path = self.root / f"{rate}.json"
            data = dict(
                schema=1,
                kind="map_jump_qualification_evidence_v1",
                physics_hz=rate,
                manifest_sha256=sha(self.path),
                level="fixture",
                identity=self.identity,
                points=[dict(case="ordinary", corridor=self.proof(rate))],
            )
            self.write(path, data)
            self.reports[rate] = path

    @staticmethod
    def write(path, data):
        path.write_text(json.dumps(data), encoding="utf-8")

    @staticmethod
    def proof(rate):
        arcs = []
        for lift in (0.0, 0.8, 1.2, 1.7):

            def position(t):
                return [t, 0.94 + 4 * lift * t * (1 - t), 0]

            segments = [
                {
                    "from": position(i / 32),
                    "to": position((i + 1) / 32),
                    "initial_clear": True,
                    "free_fraction": 1.0,
                }
                for i in range(32)
            ]
            arcs.append(dict(lift=lift, steps=32, clear=True, segments=segments))
        return dict(
            rate=rate,
            capsule_radius=0.4,
            capsule_height=1.8,
            foot_clearance=0.04,
            arcs=arcs,
        )

    def load(self):
        return load_channels(self.path, self.reports, "fixture", self.identity)

    def change(self, rate, mutate):
        path = self.reports[rate]
        data = json.loads(path.read_text())
        mutate(data)
        self.write(path, data)

    def test_matching_geometry_preserves_each_rate_proof(self):
        manifest, channels = self.load()
        result = attach(self.point, manifest["cases"], channels)
        self.assertEqual(result, ("ordinary", {r: self.proof(r) for r in (60, 120)}))

    def test_changed_geometry_does_not_borrow_original(self):
        for field, value in (
            ("start", [0.01, 0.9, 0]),
            ("target_feet", [2, 0, 0]),
            ("yaw", 0.1),
            ("duration", 3),
            ("target_radius", 2),
            ("target_height_tolerance", 1),
            ("kind", "edge"),
        ):
            point = dict(self.point, **{field: value})
            self.assertIsNone(attach(point, [self.point], {}), field)

    def test_ambiguous_geometry_rejected(self):
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            attach(self.point, [self.point, self.point], {})

    def test_matching_endpoint_does_not_override_broken_body_proof(self):
        channels = {r: {"ordinary": self.proof(r)} for r in (60, 120)}
        channels[120]["ordinary"]["capsule_height"] = 1.2
        with self.assertRaisesRegex(ValueError, "wrong body shape"):
            attach(self.point, [self.point], channels)

    def test_frozen_manifest_hash_rejected(self):
        self.change(60, lambda d: d.update(manifest_sha256="other"))
        with patch("movement_corridor_provenance.clear_corridor"):
            with self.assertRaisesRegex(ValueError, "scope"):
                self.load()

    def test_map_and_engine_identity_rejected(self):
        self.change(
            120, lambda d: d.update(identity=dict(self.identity, engine_hash="other"))
        )
        with self.assertRaisesRegex(ValueError, "scope"):
            self.load()

    def test_wrong_rate_rejected(self):
        self.change(120, lambda d: d.update(physics_hz=60))
        with patch("movement_corridor_provenance.clear_corridor"):
            with self.assertRaisesRegex(ValueError, "scope"):
                self.load()

    def test_missing_point_rejected(self):
        self.change(120, lambda d: d.update(points=[]))
        with self.assertRaisesRegex(ValueError, "coverage"):
            self.load()

    def test_raw_sweep_summary_cannot_hide_collision(self):
        self.change(
            120,
            lambda d: d["points"][0]["corridor"]["arcs"][0]["segments"][0].update(
                initial_clear=False
            ),
        )
        with self.assertRaisesRegex(ValueError, "forged clear"):
            self.load()

    def test_missing_rate_rejected(self):
        self.reports.pop(120)
        with self.assertRaisesRegex(ValueError, "both"):
            self.load()

    def test_duplicate_rows_rejected(self):
        self.change(60, lambda d: d["points"].append(copy.deepcopy(d["points"][0])))
        with self.assertRaisesRegex(ValueError, "coverage"):
            self.load()

    def test_historical_success_not_current_category_credit(self):
        control = copy.deepcopy(self.point)
        control.update(id="control", trial_mode="no_jump")
        control["native_timeline"][0]["keys"].remove("Space")
        self.manifest["cases"].append(control)
        self.write(self.path, self.manifest)
        for path in self.reports.values():
            self.write(
                path,
                dict(
                    results=[
                        dict(
                            id="ordinary",
                            trace=[
                                dict(
                                    jumped=True,
                                    grounded_after=False,
                                    crouching=True,
                                    capsule_height=1.2,
                                )
                            ],
                        ),
                        dict(id="control", trace=[]),
                    ]
                ),
            )
        with (
            patch("movement_corridor_provenance.check_report"),
            patch(
                "movement_corridor_provenance.outcomes",
                return_value=dict(first_landing=True, supported_arrival=False),
            ),
        ):
            records = historical_category(self.path, self.reports, self.root)
        self.assertTrue(records[0]["observations"]["60"]["crouched_in_air"])
        self.assertFalse(records[0]["current_category_credit"])
        self.assertFalse(records[0]["queued_cadence_present"])
        self.assertFalse(records[0]["paired_standing_walk_present"])

    def test_historical_control_must_match_input_timeline(self):
        control = dict(
            self.point, id="control", trial_mode="no_jump", native_timeline=[]
        )
        self.manifest["cases"].append(control)
        self.write(self.path, self.manifest)
        for path in self.reports.values():
            self.write(path, dict(results=[]))
        with patch("movement_corridor_provenance.check_report"):
            with self.assertRaisesRegex(ValueError, "control mismatch"):
                historical_category(self.path, self.reports, self.root)


if __name__ == "__main__":
    unittest.main()
