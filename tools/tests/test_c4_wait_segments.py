import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "wait_segments", Path(__file__).parents[1] / "authoring/analyze_c4_wait_segments.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WaitSegmentsTests(unittest.TestCase):
    def row(self, frame, serial=1, alive=True):
        return dict(
            frame=frame,
            serial=serial,
            round_state="Live",
            c4_state="dropped",
            actors=[dict(team="T", dead=not alive)],
        )

    def test_gap_and_round_split_prevent_inflated_duration(self):
        rows = [self.row(60), self.row(120), self.row(240), self.row(300, 2)]
        self.assertEqual([len(run) for run in MODULE.dropped_runs(rows)], [2, 1, 1])

    def test_no_live_t_and_round_end_are_excluded(self):
        ended = self.row(120)
        ended["round_state"] = "Round End"
        rows = [self.row(60, alive=False), ended, self.row(180)]
        self.assertEqual([len(run) for run in MODULE.dropped_runs(rows)], [1])

    def test_empty_trace_has_no_fabricated_pickup(self):
        result = MODULE.analyze([])
        self.assertEqual(result["sample_count"], 0)
        self.assertIsNone(result["following"])
