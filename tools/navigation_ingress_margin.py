"""Independent grounded-approach margin revision; preserve R15 holdout failures."""

import argparse
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from native_jump_candidates import freeze, outcomes
from navigation_ingress_study import approach_gate, score
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

REFERENCE_HZ = 60
MINIMUM_TICKS = 3
MINIMUM_SECONDS = MINIMUM_TICKS / REFERENCE_HZ
SOURCE_FILES = (
    "grid-v1.json",
    "grid-60.json",
    "selected-v1.json",
    "selection-lock.json",
)


def policy_payload(previous) -> dict[str, Any]:
    grid, selected = read(previous / SOURCE_FILES[0]), read(previous / SOURCE_FILES[2])
    require(
        grid["stage"] == "predeclared_navigation_ingress_grid"
        and selected["stage"] == "navigation_ingress_selected60_before_holdout"
        and grid["formal_qualification"] is False
        and selected["formal_qualification"] is False,
        "wrong prior stage",
    )
    require(
        read(previous / SOURCE_FILES[3])
        == {"selected_sha256": sha(previous / SOURCE_FILES[2])},
        "prior selection lock changed",
    )
    points = {p["id"]: p for p in grid["cases"]}
    require(
        len(selected["cases"]) == 9
        and len({p["id"] for p in selected["cases"]}) == 9
        and {(p["scheme"], p["trial_mode"]) for p in selected["cases"]}
        == {(s, m) for s in SCHEMES for m in ("jump", "no_jump", "walk")}
        and all(points.get(p["id"]) == p for p in selected["cases"]),
        "prior holdout cohort changed",
    )
    return dict(
        schema=1,
        formal_qualification=False,
        minimum_grounded_margin_seconds=MINIMUM_SECONDS,
        minimum_reference_ticks=MINIMUM_TICKS,
        reference_hz=REFERENCE_HZ,
        policy_scope="author_route_stability_not_original_engine_requirement",
        previously_exposed_cases=sorted(p["id"] for p in selected["cases"]),
        source_evidence_sha256={name: sha(previous / name) for name in SOURCE_FILES},
        selection_policy="first_valid_unexposed_per_profile_using60_only",
    )


def margin_gate(point, row):
    approach = approach_gate(point, row)
    result: dict[str, Any] = dict(
        passed=False,
        seconds=None,
        required_seconds=MINIMUM_SECONDS,
        checkpoint_time=approach["checkpoint_time"],
        takeoff_time=None,
        reason="approach_unproven",
    )
    if not approach["passed"]:
        return result
    jumps = [s for s in row["trace"] if s["input"]["jump"]]
    if len(jumps) != 1:
        return dict(result, reason="not_single_takeoff")
    jump = jumps[0]
    margin = jump["time"] - approach["checkpoint_time"]
    require(math.isfinite(margin), "nonfinite approach margin")
    result.update(seconds=margin, takeoff_time=jump["time"])
    supported = (
        jump["jumped"] is True
        and jump["grounded_before"] is True
        and all(
            s["grounded_after"]
            for s in row["trace"]
            if approach["checkpoint_time"] <= s["time"] < jump["time"]
        )
    )
    if not supported:
        return dict(result, reason="lost_support")
    # Only absorbs JSON floating-point representation, not a physical sample.
    passed = margin + 1e-9 >= MINIMUM_SECONDS
    return dict(
        result, passed=passed, reason="passed" if passed else "insufficient_margin"
    )


def margin_score(point, row, rate):
    base = score(point, row, rate)
    margin = margin_gate(point, row)
    return dict(
        base, grounded_margin=margin, passed=bool(base["passed"] and margin["passed"])
    )


def selection(directory, previous, project):
    policy_path = directory / "policy-v1.json"
    policy = read(policy_path)
    require(
        policy == policy_payload(previous), "frozen margin policy or source changed"
    )
    points, rows = checked(
        previous / "grid-v1.json", previous / "grid-60.json", 60, project
    )
    for point in points.values():
        for path, digest in point["probe_sha256"].items():
            require(
                sha(project / path.removeprefix("res://")) == digest,
                "live author probe drift",
            )
    excluded = set(policy["previously_exposed_cases"])
    selected, observations = [], []
    for scheme in SCHEMES:
        choice = None
        for point in points.values():
            if point["scheme"] != scheme or point["trial_mode"] != "jump":
                continue
            keys = [
                point["id"],
                *(
                    point["id"].removesuffix("jump") + mode
                    for mode in ("no_jump", "walk")
                ),
            ]
            exposed = bool(excluded.intersection(keys))
            result = margin_score(point, rows[point["id"]], 60)
            controls = any(
                outcomes(points[k], rows[k])["supported_arrival"] for k in keys[1:]
            )
            observations.append(
                dict(
                    scheme=scheme,
                    variant=point["variant"],
                    previously_exposed=exposed,
                    controls_arrive=controls,
                    **result,
                )
            )
            if choice is None and result["passed"] and not controls and not exposed:
                choice = [points[k] for k in keys]
        if choice:
            selected.extend(choice)
    return dict(
        read(previous / "grid-v1.json"),
        cases=selected,
        stage="navigation_margin_selected60_before_new_holdout",
        policy_sha256=sha(policy_path),
        observations=observations,
        previous_holdout_results_replaced=False,
    )


def verify(directory, previous, project):
    path, lock = directory / "selected-v2.json", directory / "selection-lock-v2.json"
    selected = selection(directory, previous, project)
    require(
        read(path) == selected and read(lock) == {"selected_sha256": sha(path)},
        "margin selection lock changed",
    )
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        human_acceptance=False,
        edge_lip_timing_accepted=False,
        precision_equivalence_accepted=False,
        spawn_to_navigation_connectivity="unproven",
        route_status="not_requalified",
        previous_holdout_results_replaced=False,
        minimum_grounded_margin_seconds=MINIMUM_SECONDS,
        source_grid_trials=len(read(previous / "grid-60.json")["results"]),
        new_grid_trials=0,
        replay_trials=0,
        results=[],
        observations=selected["observations"],
        checker_sha256=sha(Path(__file__)),
        evidence_sha256={
            p.name: sha(p) for p in (directory / "policy-v1.json", path, lock)
        },
        source_evidence_sha256=read(directory / "policy-v1.json")[
            "source_evidence_sha256"
        ],
    )
    if selected["cases"]:
        rows = {}
        baseline = {r["id"]: r for r in read(previous / "grid-60.json")["results"]}
        for rate in (60, 120):
            report = directory / f"replay-{rate}.json"
            _, rows[rate] = checked(path, report, rate, project)
            result["evidence_sha256"][report.name] = sha(report)
            result["replay_trials"] += len(rows[rate])
        for point in selected["cases"]:
            key = point["id"]
            require_unchanged_current(baseline[key], rows[60][key])
            if point["trial_mode"] != "jump":
                continue
            rates = {str(r): margin_score(point, rows[r][key], r) for r in (60, 120)}
            controls = {
                str(r): any(
                    outcomes(p, rows[r][p["id"]])["supported_arrival"]
                    for p in selected["cases"]
                    if p["scheme"] == point["scheme"] and p["trial_mode"] != "jump"
                )
                for r in (60, 120)
            }
            result["results"].append(
                dict(
                    scheme=point["scheme"],
                    variant=point["variant"],
                    rates=rates,
                    controls_arrive=controls,
                    passed=all(s["passed"] for s in rates.values())
                    and not any(controls.values()),
                )
            )
    result["navigation_margin_all_profiles"] = len(result["results"]) == 3 and all(
        r["passed"] for r in result["results"]
    )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "select", "verify"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("previous", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(args.directory / "policy-v1.json", policy_payload(args.previous))
    elif args.mode == "select":
        path = args.directory / "selected-v2.json"
        freeze(path, selection(args.directory, args.previous, args.project))
        freeze(
            args.directory / "selection-lock-v2.json", {"selected_sha256": sha(path)}
        )
    else:
        if args.out is None:
            parser.error("--out required")
        freeze(
            args.out,
            verify(args.directory, args.previous, args.project),
            tuple(args.directory.glob("*.json")) + tuple(args.previous.glob("*.json")),
        )
    print("NAVIGATION_MARGIN_STUDY_OK", args.mode)
