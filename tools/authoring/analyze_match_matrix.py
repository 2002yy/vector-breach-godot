"""Requalify a frozen match matrix and describe sampled risks, not gameplay approval."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from typing import Any
from datetime import datetime

from run_bounded_full_match import qualify


ACTIVE = {"Live", "Bomb Planted"}
MAP_IDS = {
    "dustline-depths-original-local",
    "mirage-classic-local",
    "inferno-classic-local",
}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def summarize_trace(rows) -> dict[str, Any]:
    """Consume one trace incrementally; spans end at the last observed sample."""
    counts = Counter()
    longest = {"live_dropped_c4": {}, "dead_player_active_round": {}}
    runs = {}
    economy = {}
    events = []
    gaps = []
    first_frame = None
    previous = None
    stalled = 0.0
    money_min = None
    money_max = None
    for row in rows:
        if "event" in row:
            counts["events"] += 1
            events.append(row)
            continue
        counts["samples"] += 1
        frame, serial = int(row["frame"]), row["serial"]
        if first_frame is None:
            first_frame = frame
        adjacent = (
            previous is not None
            and serial == previous["serial"]
            and frame == previous["frame"] + 60
        )
        if previous is not None and frame <= previous["frame"]:
            raise ValueError("non-increasing physical frames")
        if previous is not None and frame != previous["frame"] + 60:
            counts["sampling_gaps"] += 1
            gaps.append(
                dict(
                    before=previous.copy(),
                    after=dict(
                        frame=frame, serial=serial, round_state=row["round_state"]
                    ),
                )
            )
        actors = row["actors"]
        eligible = {
            "live_dropped_c4": row["round_state"] == "Live"
            and row["c4_state"] == "dropped"
            and any(a["team"] == "T" and a["alive"] for a in actors),
            "dead_player_active_round": row["round_state"] in ACTIVE
            and row["player_dead"],
        }
        for key, active in eligible.items():
            if not active:
                runs.pop(key, None)
                continue
            if key not in runs or not adjacent:
                runs[key] = dict(serial=serial, first_frame=frame, samples=0)
            run = runs[key]
            run.update(last_frame=frame, samples=run["samples"] + 1)
            run["sampled_span_seconds"] = (frame - run["first_frame"]) / 60
            if run["samples"] > longest[key].get("samples", 0):
                longest[key] = run.copy()
            counts[key + "_samples"] += 1
        teams = {}
        for actor in actors:
            ai = actor["ai"]
            money = int(ai["money"])
            if not 0 <= money <= 16000:
                raise ValueError("AI money outside game bounds")
            money_min = money if money_min is None else min(money_min, money)
            money_max = money if money_max is None else max(money_max, money)
            teams.setdefault(actor["team"], []).append(money)
            stalled = max(stalled, float(ai.get("route_stalled_seconds", 0)))
            if actor["alive"] and ai.get("route_blocked"):
                counts["alive_route_blocked_actor_samples"] += 1
        balances = {
            team: dict(
                count=len(values), mean=sum(values) / len(values), total=sum(values)
            )
            for team, values in teams.items()
        }
        entry = economy.setdefault(str(serial), dict(first_frame=frame, first=balances))
        entry.update(last_frame=frame, last=balances)
        previous = {"serial": serial, "frame": frame, "round_state": row["round_state"]}
    return dict(
        counts=dict(counts),
        longest_sampled_spans=longest,
        peak_route_stalled_seconds=stalled,
        sampled_ai_money_min=money_min,
        sampled_ai_money_max=money_max,
        economy_by_round=economy,
        first_frame=first_frame,
        last_frame=previous["frame"] if previous else None,
        round_events=events,
        sampling_gaps=gaps,
        limits=[
            "Spans are one-second observations, not exact event durations; gaps split runs.",
            "Dropped C4 with live attackers does not prove idleness, reachability or a pickup bug.",
            "Route stall counters are diagnostics, not physical proof of a stuck actor.",
            "AI-only balances exclude the idle human; compare means and counts, not unequal team totals.",
            "Despawned dead actors are absent; sampled balances have survivor/roster selection bias.",
            "Round first/last samples are not synchronized buy-stage or reward snapshots.",
        ],
    )


def summarize_rounds(records):
    longest = current = 0
    previous = None
    for row in records:
        winner = row["winner_squad"]
        current = current + 1 if winner == previous else 1
        longest = max(longest, current)
        previous = winner
    reasons = Counter(row["reason"] for row in records)
    return dict(
        count=len(records),
        reasons=dict(reasons),
        timeout_fraction=reasons["TIME"] / len(records) if records else None,
        longest_same_squad_win_streak=longest,
        limits="Squad identity survives side swaps; a win streak alone does not prove economy snowballing.",
    )


def analyze_case(directory, case, frozen):
    problems = []
    receipt = json.loads((directory / "run.json").read_text(encoding="utf8"))
    expected = (case["map"], case["side"], case["seed"])
    stable = receipt.get("source_before") == receipt.get("source_after")
    passed, status = qualify(directory, receipt.get("exit_code"), not stable, expected)
    if not passed:
        problems.append(status)
    if receipt.get("qualified_complete") is not True:
        problems.append("receipt_not_qualified")
    if receipt.get("settings_unchanged") is not True or receipt.get(
        "settings_before"
    ) != receipt.get("settings_after"):
        problems.append("settings_changed")
    if receipt.get("source_before") != frozen["frozen_sources"]:
        problems.append("matrix_source_mismatch")
    if (receipt.get("map"), receipt.get("side"), receipt.get("seed")) != expected:
        problems.append("receipt_identity_mismatch")
    result = json.loads((directory / "result.json").read_text(encoding="utf8"))
    with (directory / "trace.jsonl").open(encoding="utf8") as stream:
        trace = summarize_trace(json.loads(line) for line in stream if line.strip())
    if trace["counts"].get("samples", 0) == 0:
        problems.append("empty_trace")
    coverage_problems = trace_coverage(trace, result)
    return dict(
        id=case["id"],
        qualified_complete=not problems,
        problems=problems,
        trace_coverage_qualified=not coverage_problems,
        trace_coverage_problems=coverage_problems,
        observed_head=receipt.get("head"),
        wall_seconds=receipt.get("wall_seconds"),
        simulated_seconds=result.get("simulated_seconds"),
        player_score=result.get("player_score"),
        opponent_score=result.get("opponent_score"),
        rounds=summarize_rounds(result["round_records"]),
        trace=trace,
        files={
            name: digest(directory / name)
            for name in ("run.json", "result.json", "trace.jsonl", "process.log")
        },
    )


def trace_coverage(trace, result):
    """Keep match completion separate from coverage needed to analyze that match."""
    problems = []
    serials = {str(r["round_serial"]) for r in result["round_records"]}
    if set(trace["economy_by_round"]) != serials:
        problems.append("sampled_round_set_mismatch")
    if trace["first_frame"] != 60:
        problems.append("initial_sample_missing")
    expected_tail = int(float(result.get("simulated_seconds", 0)) * 60 + 0.01)
    if trace["last_frame"] is None or not 0 <= expected_tail - trace["last_frame"] < 60:
        problems.append("final_sample_missing")
    if trace["counts"].get("sampling_gaps", 0):
        problems.append("sampling_gaps_require_review")
    observed = [
        (r.get("serial"), r.get("winner"), r.get("reason"))
        for r in trace["round_events"]
        if r.get("event") == "round_ended"
    ]
    expected = [
        (r["round_serial"], r["winner_side"], r["reason"])
        for r in result["round_records"]
    ]
    if observed != expected:
        problems.append("round_end_events_mismatch")
    return problems


def dependency_coverage(directory, case, frozen):
    """Check added local-resource receipts without rewriting early observations."""
    baseline_name = frozen.get("dependency_baseline")
    if not baseline_name or Path(baseline_name).name != baseline_name:
        return ["dependency_baseline_missing_or_invalid"]
    baseline_path = directory / baseline_name
    if digest(baseline_path) != frozen.get("dependency_baseline_sha256"):
        return ["dependency_baseline_sha_mismatch"]
    baseline = json.loads(baseline_path.read_text(encoding="utf8"))
    if not dependency_closure_valid(baseline):
        return ["expected_local_dependency_closure_missing"]
    case_id = case["id"]
    after_path = directory / (case_id + "-dependencies-after.json")
    after = json.loads(after_path.read_text(encoding="utf8"))
    problems = []
    if after["files"] != baseline["files"] or after["maps"] != baseline["maps"]:
        problems.append("dependencies_changed_after_match")
    run_path = directory / case_id / "run.json"
    completed_at = run_path.stat().st_mtime
    observed_after = datetime.fromisoformat(after["observed_utc"]).timestamp()
    if observed_after < completed_at:
        problems.append("dependency_observation_precedes_completed_receipt")
    before_path = directory / (case_id + "-dependencies-before.json")
    before = (
        json.loads(before_path.read_text(encoding="utf8"))
        if before_path.exists()
        else baseline
    )
    created_at = getattr(run_path.stat(), "st_birthtime", None)
    if created_at is None:
        problems.append("launch_creation_time_unavailable")
    elif datetime.fromisoformat(before["observed_utc"]).timestamp() > created_at:
        problems.append("dependency_baseline_observed_after_launch")
    if before["files"] != baseline["files"] or before["maps"] != baseline["maps"]:
        problems.append("dependencies_changed_before_match")
    return problems


def dependency_closure_valid(baseline):
    if set(baseline["maps"]) != MAP_IDS:
        return False
    expected = set()
    for level, info in baseline["maps"].items():
        source = info["source"]
        cache = (
            "res://assets/local_reference/collision_cache/"
            + hashlib.sha256(source.encode()).hexdigest()
            + ".res"
        )
        expected.update(
            {
                f"res://data/levels/{level}.json",
                info["manifest"],
                source,
                source + ".import",
                info["compiled"],
                cache,
                cache + ".json",
            }
        )
    if len(expected) != 21 or set(baseline["files"]) != expected:
        return False
    return all(
        name.startswith("res://")
        and ".." not in name[6:].split("/")
        and "\\" not in name
        for name in expected
    )


def analyze_matrix(directory, manifest_name="matrix-frozen.json"):
    if Path(manifest_name).name != manifest_name:
        raise ValueError("Manifest must be an immediate child")
    path = directory / manifest_name
    frozen = json.loads(path.read_text(encoding="utf8"))
    cases = frozen["cases"]
    identities = [(c["map"], c["side"], c["seed"]) for c in cases]
    expected = {
        (map_id, side, seed)
        for map_id in (
            "dustline-depths-original-local",
            "mirage-classic-local",
            "inferno-classic-local",
        )
        for side in ("T", "CT")
        for seed in (1701, 1702, 1703)
    }
    matrix_problems = []
    if len(identities) != 18 or set(identities) != expected:
        matrix_problems.append("not_exact_three_map_two_side_three_seed_matrix")
    if len({case["id"] for case in cases}) != len(cases):
        matrix_problems.append("duplicate_case_id")
    results = []
    for case in cases:
        case_path = Path(case["id"])
        if (
            case_path.is_absolute()
            or len(case_path.parts) != 1
            or case_path.name in {".", ".."}
        ):
            matrix_problems.append("invalid_case_path")
            results.append(
                dict(id=case["id"], qualified_complete=False, error="invalid_case_path")
            )
            continue
        try:
            result = analyze_case(directory / case_path, case, frozen)
            try:
                dependency_problems = dependency_coverage(directory, case, frozen)
            except (OSError, ValueError, KeyError, TypeError) as error:
                dependency_problems = [str(error)]
            result.update(
                dependency_qualified=not dependency_problems,
                dependency_problems=dependency_problems,
            )
            results.append(result)
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append(
                dict(id=case["id"], qualified_complete=False, error=str(error))
            )
    qualified = sum(r["qualified_complete"] for r in results)
    maps = {}
    for case, result in zip(cases, results):
        if not result.get("qualified_complete"):
            continue
        item = maps.setdefault(
            case["map"],
            dict(
                matches=0,
                trace_qualified_matches=0,
                rounds=0,
                reasons=Counter(),
                longest_dropped_span_seconds=0,
                longest_death_wait_span_seconds=0,
            ),
        )
        item["matches"] += 1
        item["trace_qualified_matches"] += int(result["trace_coverage_qualified"])
        item["rounds"] += result["rounds"]["count"]
        item["reasons"].update(result["rounds"]["reasons"])
        spans = result["trace"]["longest_sampled_spans"]
        item["longest_dropped_span_seconds"] = max(
            item["longest_dropped_span_seconds"],
            spans["live_dropped_c4"].get("sampled_span_seconds", 0),
        )
        item["longest_death_wait_span_seconds"] = max(
            item["longest_death_wait_span_seconds"],
            spans["dead_player_active_round"].get("sampled_span_seconds", 0),
        )
    return dict(
        frozen_manifest_sha256=digest(path),
        production_head=frozen["production_head"],
        matrix_problems=matrix_problems,
        qualified=qualified,
        total=len(cases),
        complete_18_match_sample=not matrix_problems
        and qualified == 18
        and all(r.get("dependency_qualified") for r in results),
        complete_18_match_trace_analysis=not matrix_problems
        and qualified == 18
        and all(r.get("dependency_qualified") for r in results)
        and all(r.get("trace_coverage_qualified") for r in results),
        full_gameplay_acceptance=False,
        matches=results,
        by_map=maps,
        limits="Idle human plus nine AI; no manual three-map, original-engine equivalence or 70% GPU FPS acceptance.",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", default="matrix-frozen.json")
    args = parser.parse_args()
    report = analyze_matrix(args.directory, args.manifest)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )
    print(
        json.dumps(
            {
                key: report[key]
                for key in (
                    "qualified",
                    "total",
                    "matrix_problems",
                    "complete_18_match_sample",
                )
            }
        )
    )
