"""Keep physical jump actions separate from traversable jump routes and coverage."""

import argparse
import json
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from map_jump_qualification import KINDS, clear_corridor
from native_jump_candidates import check_report
from queued_three_map_audit import MAPS, check_cadence, verify
from tactical_jump_coverage import classify
from validate_native_route_study import check_trace, require


def check_physical_samples(trace):
    require(bool(trace), "empty physical trace")
    for sample in trace:
        require(
            len(sample["position"]) == len(sample["velocity"]) == 3
            and all(
                isinstance(v, (int, float)) and math.isfinite(v)
                for v in (*sample["position"], *sample["velocity"])
            ),
            "nonfinite physical trace",
        )


def check_control(row):
    check_physical_samples(row["trace"])
    require(
        not any(s["jumped"] or s["input"]["jump"] for s in row["trace"]),
        "walking control performed a jump",
    )


def action_gate(point, row, rate):
    """Observe takeoff independently of reaching a target or its category name."""
    require(rate in (60, 120), "unsupported physical rate")
    require(point["queued_input"] is True, "action gate requires queued evidence")
    require(point["trial_mode"] == "jump", "jump action requires a jump trial")
    delays = check_trace(point, row, rate)
    check_cadence(row, point)
    trace = row["trace"]
    check_physical_samples(trace)
    for index, sample in enumerate(trace):
        if index:
            current, previous = sample["cadence"], trace[index - 1]["cadence"]
            require(
                current["process_frame"] - previous["process_frame"] == 1
                and current["physics_frame"] - previous["physics_frame"] == 1,
                "actual engine counters contradict supported cadence",
            )
    consumed = [s for s in trace if s["input"]["jump"]]
    takeoffs = [s for s in trace if s["jumped"]]
    # This single-jump cohort cannot certify repeated hops or an edge fall.
    passed = bool(
        row["start_valid"]
        and len(consumed) == len(takeoffs) == 1
        and takeoffs[0] is consumed[0]
        and takeoffs[0]["grounded_before"] is True
        and takeoffs[0]["grounded_after"] is False
        and takeoffs[0]["velocity"][1] > 0
    )
    return dict(
        passed=passed,
        consumed_edges=len(consumed),
        actual_takeoffs=len(takeoffs),
        input_delays_seconds=delays,
        takeoff_time=takeoffs[0]["time"] if len(takeoffs) == 1 else None,
        scope="single_supported_takeoff_synthetic_InputMap",
    )


def route_gate(corridors, actions, landings, controls):
    require(
        set(corridors) == set(actions) == set(landings) == set(controls) == {60, 120},
        "both physical rates required",
    )
    require(
        all(set(rows) == {"no_jump", "walk"} for rows in controls.values()),
        "both walking controls required at each rate",
    )
    status = classify(
        corridors,
        {r: actions[r]["passed"] and landings[r] for r in (60, 120)},
        {r: any(controls[r].values()) for r in (60, 120)},
    )
    return dict(
        status=status,
        jump_route_passed=status == "qualified_jump",
        action_passed=all(a["passed"] for a in actions.values()),
    )


def category_coverage(points):
    return [
        dict(
            map=name,
            category=kind,
            action_evidence_present=any(
                p["map"] == name and p["kind"] == kind and p["action_passed"]
                for p in points
            ),
            all_profiles_route_passed=all(
                any(
                    p["map"] == name
                    and p["kind"] == kind
                    and p["scheme"] == scheme
                    and p["jump_route_passed"]
                    for p in points
                )
                for scheme in SCHEMES
            ),
        )
        for name in MAPS
        for kind in sorted(KINDS)
    ]


def evaluate(directory, sources, project):
    prior = verify(directory, sources, project)
    result: dict[str, Any] = dict(
        schema=1,
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        human_acceptance=False,
        source_trials_revalidated=prior["trials"],
        evidence_sha256={},
        checker_sha256=sha(Path(__file__)),
        points=[],
    )
    for name in MAPS:
        path = directory / f"{name}-queued-v1.json"
        manifest = read(path)
        result["evidence_sha256"][path.name] = sha(path)
        result["evidence_sha256"][f"source/{name}-matrix-v1.json"] = sha(
            sources / f"{name}-matrix-v1.json"
        )
        outcomes, rows = {}, {}
        for rate in (60, 120):
            report = directory / f"{name}-{rate}.json"
            result["evidence_sha256"][report.name] = sha(report)
            outcomes[rate] = check_report(path, report, rate, project)
            rows[rate] = {r["id"]: r for r in read(report)["results"]}
        cases = {
            (p["parent_case"], p["scheme"], p["trial_mode"]): p
            for p in manifest["cases"]
            if p["queued_input"]
        }
        for (parent, scheme, mode), point in cases.items():
            if mode != "jump":
                continue
            actions = {
                r: action_gate(point, rows[r][point["id"]], r) for r in (60, 120)
            }
            corridor = clear_corridor(point, point["corridor"])
            for rate in (60, 120):
                for control_mode in ("no_jump", "walk"):
                    control = rows[rate][cases[(parent, scheme, control_mode)]["id"]]
                    check_control(control)
            controls = {
                r: {
                    m: outcomes[r][cases[(parent, scheme, m)]["id"]][
                        "supported_arrival"
                    ]
                    for m in ("no_jump", "walk")
                }
                for r in (60, 120)
            }
            landings = {r: outcomes[r][point["id"]]["first_landing"] for r in (60, 120)}
            result["points"].append(
                dict(
                    map=name,
                    case=parent,
                    scheme=scheme,
                    kind=point["kind"],
                    actions={str(r): a for r, a in actions.items()},
                    body_corridor_clear=corridor[0],
                    controls={str(r): c for r, c in controls.items()},
                    first_landings={str(r): v for r, v in landings.items()},
                    **route_gate(
                        {60: corridor, 120: corridor}, actions, landings, controls
                    ),
                )
            )
    result["category_coverage"] = category_coverage(result["points"])
    result["all_categories_covered"] = all(
        r["all_profiles_route_passed"] for r in result["category_coverage"]
    )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = evaluate(args.directory, args.sources, args.project)
    # Never allow a derived summary to replace a raw report or frozen input.
    require(
        args.out.resolve().parent
        not in (args.directory.resolve(), args.sources.resolve())
        and not args.out.exists(),
        "use a new output outside source evidence directories",
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("MOVEMENT_DIMENSIONS_WRITTEN", len(result["points"]), "release_ready=False")
