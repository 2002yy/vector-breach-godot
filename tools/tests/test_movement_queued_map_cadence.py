"""Observed counters and complete controls are mandatory for queued evidence."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from queued_three_map_audit import (
    CADENCE_PROBES,
    PROBES,
    QUEUE_PROBES,
    check_cadence,
    payload,
)


class QueuedMapCadenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in (*PROBES, *QUEUE_PROBES, *CADENCE_PROBES):
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")
        self.source = self.root / "source.json"
        self.data = dict(
            schema=4,
            formal_qualification=False,
            cases=[
                dict(
                    id=s + "__" + m,
                    parent_case="rim",
                    scheme=s,
                    trial_mode=m,
                    start=[0, 1, 0],
                    target_feet=[0, 1, -3],
                    target_radius=1.6,
                    native_timeline=[dict(at=0, keys=["W"])],
                )
                for s in ("current", "legacy_16", "modern_cs")
                for m in ("jump", "no_jump", "walk")
            ],
        )
        self.save()

    def save(self):
        self.source.write_text(json.dumps(self.data))

    def test_complete_paired_matrix_without_geometry_or_input_changes(self):
        result = payload(self.source, self.root, self.root / "reject.json")
        originals = {p["id"]: p for p in self.data["cases"]}
        self.assertEqual(len(result["cases"]), 18)
        for point in result["cases"]:
            for key in ("start", "target_feet", "target_radius", "native_timeline"):
                self.assertEqual(point[key], originals[point["source_case"]][key])
            self.assertEqual(point["enforce_cadence"], point["queued_input"])
        self.assertFalse(result["formal_qualification"])
        self.assertFalse(result["native_acceptance"])

    def test_missing_control_rejected(self):
        self.data["cases"].pop()
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root, self.root / "reject.json")

    def test_duplicate_source_id_rejected(self):
        self.data["cases"][1]["id"] = self.data["cases"][0]["id"]
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root, self.root / "reject.json")

    def test_camera_only_source_rejected(self):
        self.data["camera_only"] = True
        self.save()
        with self.assertRaises(ValueError):
            payload(self.source, self.root, self.root / "reject.json")

    def fixture(self):
        point = dict(queued_input=True, probe_sha256={"probe": "sha"})
        row = dict(
            queued_input=True,
            trace=[
                dict(
                    probe_sha256={"probe": "sha"},
                    time=0,
                    input={"jump": False},
                    jump_requested_time=-1,
                    cadence=dict(
                        tick=0,
                        violation=False,
                        process_delta=-1,
                        prequeued=False,
                        inline_events=1,
                    ),
                ),
                dict(
                    time=1 / 60,
                    input={"jump": True},
                    jump_requested_time=1 / 60,
                    cadence=dict(
                        tick=1,
                        violation=False,
                        process_delta=1,
                        prequeued=True,
                        inline_events=0,
                    ),
                ),
            ],
        )
        return row, point

    def test_initial_inline_setup_allowed_only_initial_tick(self):
        row, point = self.fixture()
        check_cadence(row, point)

    def test_repeated_process_frame_rejected_even_with_false_violation_claim(self):
        row, point = self.fixture()
        row["trace"][1]["cadence"]["process_delta"] = 0
        with self.assertRaises(ValueError):
            check_cadence(row, point)

    def test_multiple_process_frames_rejected(self):
        row, point = self.fixture()
        row["trace"][1]["cadence"]["process_delta"] = 2
        with self.assertRaises(ValueError):
            check_cadence(row, point)

    def test_missing_prequeue_rejected(self):
        row, point = self.fixture()
        row["trace"][1]["cadence"]["prequeued"] = False
        with self.assertRaises(ValueError):
            check_cadence(row, point)

    def test_inline_event_fallback_rejected(self):
        row, point = self.fixture()
        row["trace"][1]["cadence"]["inline_events"] = 1
        with self.assertRaises(ValueError):
            check_cadence(row, point)

    def test_delayed_jump_rejected(self):
        row, point = self.fixture()
        row["trace"][1]["jump_requested_time"] = 0
        with self.assertRaises(ValueError):
            check_cadence(row, point)

    def test_probe_drift_rejected(self):
        row, point = self.fixture()
        row["trace"][0]["probe_sha256"]["probe"] = "different"
        with self.assertRaises(ValueError):
            check_cadence(row, point)

    def test_generation_preserves_source(self):
        before = self.source.read_bytes()
        payload(self.source, self.root, self.root / "reject.json")
        self.assertEqual(before, self.source.read_bytes())


if __name__ == "__main__":
    unittest.main()
