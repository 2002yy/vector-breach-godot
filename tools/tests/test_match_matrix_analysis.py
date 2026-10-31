"""Adversarial checks for match evidence qualification and sampled risk summaries."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from typing import Any

AUTHORING = Path(__file__).parents[1] / "authoring"
sys.path.insert(0, str(AUTHORING))
spec = importlib.util.spec_from_file_location(
    "matrix_analysis", AUTHORING / "analyze_match_matrix.py"
)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def sample(frame, serial=1, dropped=True, dead=True, team="T") -> dict[str, Any]:
    return dict(
        frame=frame,
        serial=serial,
        round_state="Live",
        player_dead=dead,
        c4_state="dropped" if dropped else "carried",
        actors=[
            dict(alive=True, team=team, ai=dict(money=800, route_stalled_seconds=0))
        ],
    )


def dependency_fixture() -> dict[str, Any]:
    maps, files = {}, {}
    for level in module.MAP_IDS:
        source = f"res://assets/{level}.glb"
        cache = (
            "res://assets/local_reference/collision_cache/"
            + module.hashlib.sha256(source.encode()).hexdigest()
            + ".res"
        )
        maps[level] = dict(
            source=source,
            manifest=f"res://data/levels/match-local/{level}.json",
            compiled=f"res://.godot/imported/{level}.scn",
        )
        for name in (
            f"res://data/levels/{level}.json",
            maps[level]["manifest"],
            source,
            source + ".import",
            maps[level]["compiled"],
            cache,
            cache + ".json",
        ):
            files[name] = dict(sha256="same", bytes=1)
    return dict(files=files, maps=maps, observed_utc="1970-01-01T00:00:00+00:00")


class MatchMatrixAnalysisTests(unittest.TestCase):
    def test_gaps_and_round_boundaries_split_wait_not_sample_count_as_duration(self):
        report = module.summarize_trace(
            iter(
                [
                    sample(60),
                    sample(120),
                    {"event": "round_ended"},
                    sample(240),
                    sample(300, serial=2),
                    sample(360, serial=2),
                ]
            )
        )
        longest = report["longest_sampled_spans"]["live_dropped_c4"]
        self.assertEqual(longest["samples"], 2)
        self.assertEqual(longest["sampled_span_seconds"], 1)
        self.assertEqual(report["counts"]["sampling_gaps"], 1)

    def test_dead_attackers_do_not_count_as_actionable_dropped_bomb(self):
        row = sample(60)
        row["actors"][0]["alive"] = False
        report = module.summarize_trace([row, sample(120, team="CT")])
        self.assertEqual(report["longest_sampled_spans"]["live_dropped_c4"], {})

    def test_invalid_money_and_backwards_frames_are_rejected(self):
        row = sample(60)
        row["actors"][0]["ai"]["money"] = -1
        with self.assertRaisesRegex(ValueError, "money"):
            module.summarize_trace([row])
        with self.assertRaisesRegex(ValueError, "frames"):
            module.summarize_trace([sample(120), sample(60)])

    def test_economy_means_use_actual_side_not_display_name_or_equal_team_assumption(
        self,
    ):
        row = sample(60)
        row["actors"].extend(
            [
                dict(alive=False, team="T", ai=dict(money=1600)),
                dict(alive=True, team="CT", ai=dict(money=2000)),
            ]
        )
        teams = module.summarize_trace([row])["economy_by_round"]["1"]["first"]
        self.assertEqual(teams["T"], dict(count=2, mean=1200, total=2400))
        self.assertEqual(teams["CT"]["mean"], 2000)

    def test_side_swap_does_not_break_same_squad_win_streak(self):
        rows = [
            dict(winner_squad="player", winner_side="T", reason="BOMB EXPLODED"),
            dict(winner_squad="player", winner_side="CT", reason="TIME"),
            dict(winner_squad="opponent", winner_side="T", reason="ELIMINATION"),
        ]
        report = module.summarize_rounds(rows)
        self.assertEqual(report["longest_same_squad_win_streak"], 2)
        self.assertAlmostEqual(report["timeout_fraction"], 1 / 3)

    def test_truncated_trace_and_mismatched_round_event_do_not_qualify_analysis(self):
        trace = module.summarize_trace([sample(60)])
        result: dict[str, Any] = dict(
            simulated_seconds=120,
            round_records=[dict(round_serial=1, winner_side="CT", reason="TIME")],
        )
        problems = module.trace_coverage(trace, result)
        self.assertIn("final_sample_missing", problems)
        self.assertIn("round_end_events_mismatch", problems)
        result["simulated_seconds"] = 1.5
        trace["round_events"] = [
            dict(event="round_ended", serial=1, winner="CT", reason="TIME")
        ]
        self.assertEqual(module.trace_coverage(trace, result), [])

    def test_complete_receipt_cannot_override_engine_error_or_frozen_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            case = dict(id="test", map="map", side="T", seed=1701)
            sources = {"scripts/test.gd": "abc"}
            frozen = dict(frozen_sources=sources)
            result = dict(
                level_id="map",
                initial_player_team="T",
                seed=1701,
                pause_resume_checked=True,
                summary_menu_checked=True,
                main_scene_context_checked=True,
                physics_hz=60,
                phase="complete",
                team_size=5,
                regulation_rounds=1,
                overtime_rounds=0,
                round_records=[
                    dict(
                        winner_squad="player",
                        winner_side="CT",
                        round_serial=1,
                        reason="TIME",
                    )
                ],
            )
            receipt = dict(
                map="map",
                side="T",
                seed=1701,
                exit_code=0,
                qualified_complete=True,
                settings_unchanged=True,
                settings_before="same",
                settings_after="same",
                source_before=sources,
                source_after=sources,
            )
            (directory / "result.json").write_text(json.dumps(result), encoding="utf8")
            (directory / "trace.jsonl").write_text(
                json.dumps(sample(60)), encoding="utf8"
            )
            (directory / "process.log").write_text(
                "FULL_MATCH_COMPLETE map", encoding="utf8"
            )
            (directory / "run.json").write_text(json.dumps(receipt), encoding="utf8")
            self.assertTrue(
                module.analyze_case(directory, case, frozen)["qualified_complete"]
            )
            altered = copy.deepcopy(frozen)
            altered["frozen_sources"]["scripts/test.gd"] = "different"
            self.assertIn(
                "matrix_source_mismatch",
                module.analyze_case(directory, case, altered)["problems"],
            )
            (directory / "process.log").write_text(
                "ERROR: bad\nFULL_MATCH_COMPLETE map", encoding="utf8"
            )
            self.assertFalse(
                module.analyze_case(directory, case, frozen)["qualified_complete"]
            )

    def test_eighteen_copies_of_one_case_do_not_make_a_matrix(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            case = dict(
                id="missing", map="dustline-depths-original-local", side="T", seed=1701
            )
            frozen = dict(production_head="head", frozen_sources={}, cases=[case] * 18)
            (directory / "matrix-frozen.json").write_text(
                json.dumps(frozen), encoding="utf8"
            )
            report = module.analyze_matrix(directory)
            self.assertFalse(report["complete_18_match_sample"])
            self.assertIn("duplicate_case_id", report["matrix_problems"])

    def test_missing_dependency_baseline_never_qualifies_old_observation(self):
        self.assertEqual(
            module.dependency_coverage(Path("unused"), dict(id="case"), {}),
            ["dependency_baseline_missing_or_invalid"],
        )

    def test_same_file_count_cannot_replace_required_resource(self):
        baseline = dependency_fixture()
        self.assertTrue(module.dependency_closure_valid(baseline))
        removed = next(iter(baseline["files"]))
        baseline["files"]["res://irrelevant.txt"] = baseline["files"].pop(removed)
        self.assertEqual(len(baseline["files"]), 21)
        self.assertFalse(module.dependency_closure_valid(baseline))

    @unittest.skipUnless(
        hasattr(Path(__file__).stat(), "st_birthtime"),
        "birthtime required for local launch proof",
    )
    def test_dependency_gate_rejects_changed_bytes_and_late_baseline(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "case").mkdir()
            (directory / "case/run.json").write_text("{}", encoding="utf8")
            baseline: dict[str, Any] = dependency_fixture()
            path = directory / "dependencies.json"
            path.write_text(json.dumps(baseline), encoding="utf8")
            frozen = dict(
                dependency_baseline=path.name,
                dependency_baseline_sha256=module.digest(path),
            )
            after = copy.deepcopy(baseline)
            after["observed_utc"] = "2100-01-01T00:00:00+00:00"
            after_path = directory / "case-dependencies-after.json"
            after_path.write_text(json.dumps(after), encoding="utf8")
            self.assertEqual(
                module.dependency_coverage(directory, dict(id="case"), frozen), []
            )
            after["files"][next(iter(after["files"]))]["sha256"] = "modified"
            after_path.write_text(json.dumps(after), encoding="utf8")
            self.assertIn(
                "dependencies_changed_after_match",
                module.dependency_coverage(directory, dict(id="case"), frozen),
            )
            after["files"] = copy.deepcopy(baseline["files"])
            after_path.write_text(json.dumps(after), encoding="utf8")
            baseline["observed_utc"] = "2100-01-01T00:00:00+00:00"
            path.write_text(json.dumps(baseline), encoding="utf8")
            frozen["dependency_baseline_sha256"] = module.digest(path)
            self.assertIn(
                "dependency_baseline_observed_after_launch",
                module.dependency_coverage(directory, dict(id="case"), frozen),
            )


if __name__ == "__main__":
    unittest.main()
