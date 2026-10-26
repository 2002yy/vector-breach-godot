"""Surface seeds require source bindings and cannot imply gameplay accessibility."""

import copy
import json
import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import test_movement_edge_revision as fixtures
from build_native_route_study import sha
from surface_edge_study import PROBE, make_grid


class SurfaceEdgeTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.EdgeRevisionTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root, self.source = self.fixture.root, self.fixture.source
        (self.root / PROBE).write_text("fixture surface probe")
        self.survey_path = self.root / "surface-survey.json"
        records = copy.deepcopy(self.fixture.records[:2])
        for record in records:
            record.update(
                surface_accessibility="unproven",
                horizontal_sweep=dict(
                    radius=0.4,
                    height=1.8,
                    clearance=0.04,
                    free_fraction=1,
                    distance=1.2,
                ),
            )
        self.survey: dict[str, Any] = dict(
            identity={},
            parent_sha256=sha(self.source),
            survey_sha256=sha(self.root / PROBE),
            formal_qualification=False,
            surface_accessibility="unproven",
            candidates=records,
            diagnostics=dict(columns=20),
            policy=dict(
                column_limit=1024,
                candidate_limit=8,
                offsets=[-2, -1, 0, 1, 2],
                distances=[0.8, 1.2, 1.6],
                goal_ray_up=0.15,
            ),
        )

    def build(self):
        self.survey_path.write_text(json.dumps(self.survey))
        return make_grid(
            self.source, self.survey_path, self.root, self.root / "reject.json"
        )

    def test_complete_controls_and_anchor_is_not_a_navigation_node(self):
        before = self.source.read_bytes()
        result = self.build()
        self.assertEqual(len(result["cases"]), 6)
        self.assertTrue(
            all(
                "source_surface_anchor" in p and "source_nav_node" not in p
                for p in result["cases"]
            )
        )
        self.assertEqual(result["surface_accessibility"], "unproven")
        self.assertEqual(self.source.read_bytes(), before)

    def test_survey_parent_drift_rejected(self):
        self.survey["parent_sha256"] = "wrong"
        with self.assertRaises(ValueError):
            self.build()

    def test_probe_source_drift_rejected(self):
        (self.root / PROBE).write_text("changed probe")
        with self.assertRaises(ValueError):
            self.build()

    def test_aggregate_or_per_surface_accessibility_cannot_be_forged(self):
        self.survey["surface_accessibility"] = "verified"
        with self.assertRaises(ValueError):
            self.build()
        self.survey["surface_accessibility"] = "unproven"
        self.survey["candidates"][0]["surface_accessibility"] = "verified"
        with self.assertRaises(ValueError):
            self.build()

    def test_wrong_capsule_shape_or_blocked_motion_rejected(self):
        for key, value in (("radius", 0.2), ("height", 1.2), ("free_fraction", 0.5)):
            original = self.survey["candidates"][0]["horizontal_sweep"][key]
            self.survey["candidates"][0]["horizontal_sweep"][key] = value
            with self.assertRaises(ValueError):
                self.build()
            self.survey["candidates"][0]["horizontal_sweep"][key] = original

    def test_column_or_candidate_limit_cannot_be_exceeded(self):
        self.survey["diagnostics"]["columns"] = 1025
        with self.assertRaises(ValueError):
            self.build()
        self.survey["diagnostics"]["columns"] = 20
        self.survey["candidates"] *= 5
        with self.assertRaises(ValueError):
            self.build()

    def test_policy_changes_and_empty_survey_rejected(self):
        self.survey["policy"]["goal_ray_up"] = 2.5
        with self.assertRaises(ValueError):
            self.build()
        self.survey["policy"]["goal_ray_up"] = 0.15
        self.survey["candidates"] = []
        with self.assertRaises(ValueError):
            self.build()


if __name__ == "__main__":
    unittest.main()
