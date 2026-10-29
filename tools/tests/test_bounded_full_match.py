import json
from pathlib import Path
import runpy
import tempfile
import unittest

qualify = runpy.run_path(
    str(Path(__file__).parents[1] / "authoring/run_bounded_full_match.py")
)["qualify"]


class BoundedMatchQualificationTests(unittest.TestCase):
    def test_timeout_cannot_reuse_old_complete_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "process.log").write_text(
                "FULL_MATCH_COMPLETE map", encoding="utf8"
            )
            (directory / "result.json").write_text("{}", encoding="utf8")
            self.assertEqual(
                qualify(directory, None, False), (False, "wall_timeout_incomplete")
            )

    def test_engine_error_rejects_zero_exit_and_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "process.log").write_text(
                "SCRIPT ERROR: broken\nFULL_MATCH_COMPLETE map", encoding="utf8"
            )
            self.assertFalse(qualify(directory, 0, False)[0])

    def test_complete_requires_rule_evidence_and_stable_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "process.log").write_text(
                "FULL_MATCH_COMPLETE map", encoding="utf8"
            )
            (directory / "result.json").write_text(
                json.dumps(
                    {
                        "pause_resume_checked": True,
                        "summary_menu_checked": True,
                        "main_scene_context_checked": True,
                        "physics_hz": 60,
                        "round_records": [{"winner": "T"}],
                        "phase": "complete",
                        "team_size": 5,
                        "regulation_rounds": 1,
                        "overtime_rounds": 0,
                    }
                ),
                encoding="utf8",
            )
            self.assertTrue(qualify(directory, 0, False)[0])
            self.assertEqual(
                qualify(directory, 0, False, ("map", "CT", 1701)),
                (False, "requested_match_identity_mismatch"),
            )
            self.assertFalse(qualify(directory, 0, True)[0])
            (directory / "result.json").write_text("{}", encoding="utf8")
            self.assertFalse(qualify(directory, 0, False)[0])
