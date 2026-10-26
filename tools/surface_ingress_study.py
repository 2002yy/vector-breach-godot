"""Frozen native ingress routes to the exact previously sampled Dust II surface."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from map_jump_qualification import clear_corridor
from movement_dimension_gates import action_gate, check_control
from native_jump_candidates import check_report, freeze, inside, outcomes
from queued_three_map_audit import check_cadence
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

PROBE = "tools/authoring/audit_surface_ingress.gd"


def timeline(jump, travel, crouch) -> list[dict[str, Any]]:
    return [
        dict(at=at, keys=keys, mouse_dx=0)
        for at, keys in (
            (0, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 0.05, ["W", "Ctrl"] if crouch else ["W"]),
            (jump + travel, ["Ctrl"] if crouch else []),
        )
    ]


def grid_payload(source, project, rejection):
    parent = read(source)
    require(
        parent["stage"] == "selected_current60_before_holdout"
        and parent["surface_accessibility"] == "unproven",
        "wrong surface parent",
    )
    original = next(
        p
        for p in parent["cases"]
        if p["scheme"] == "current" and p["trial_mode"] == "jump"
    )
    goal = original["geometry"]["feet"]
    floor = original["target_feet"]
    delta = [b - a for a, b in zip(floor, goal)]
    yaw = math.atan2(-delta[0], -delta[2])
    cases = []
    for scheme in SCHEMES:
        for jump in (0.0, 0.1, 0.2):
            for travel in (0.15, 0.3):
                for crouch in (False, True):
                    variant = f"jump{round(jump * 1000)}_travel{round(travel * 1000)}_crouch{int(crouch)}"
                    for mode in ("jump", "no_jump", "walk"):
                        point = copy.deepcopy(original)
                        native = timeline(jump, travel, crouch)
                        if mode != "jump":
                            for event in native:
                                event["keys"] = [
                                    k for k in event["keys"] if k != "Space"
                                ]
                                if mode == "walk":
                                    event["keys"].append("Shift")
                        point.update(
                            id=f"{scheme}__{variant}__{mode}",
                            scheme=scheme,
                            parent_case="surface_ingress",
                            kind="run_up",
                            variant=variant,
                            trial_mode=mode,
                            start=[floor[0], floor[1] + 0.91, floor[2]],
                            target_feet=goal,
                            target_radius=0.35,
                            target_height_tolerance=0.18,
                            yaw=yaw,
                            duration=2.0,
                            native_timeline=native,
                            rejection_path=str(rejection),
                            ingress_origin="R13_lower_drop_floor",
                            ingress_goal="R13_exact_upper_surface",
                        )
                        point["probe_sha256"]["res://" + PROBE] = sha(project / PROBE)
                        cases.append(point)
    return dict(
        parent,
        stage="predeclared_ingress_grid",
        cases=cases,
        parent_surface_sha256=sha(source),
        source_surface_accessibility="unproven",
        formal_qualification=False,
    )


def qualify(point, row, rate):
    action = action_gate(point, row, rate)
    corridor = clear_corridor(point, row["ingress_corridor"])[0]
    arrival = outcomes(point, row)["supported_arrival"]
    tail = row["trace"][-(round(0.1 * rate) + 1) :]
    held = len(tail) == round(0.1 * rate) + 1 and all(
        s["grounded_after"] and inside(point, s) for s in tail
    )
    return dict(
        action=action["passed"],
        corridor=corridor,
        arrival=arrival,
        stable_finish=held,
        passed=bool(action["passed"] and corridor and arrival and held),
    )


def initial_jump_rejection(point, row, rate):
    """Classify only the known tick-zero request; every other invariant stays fatal."""
    mismatches = [
        s
        for s in row["trace"]
        if s["input"]["jump"] and abs(s["jump_requested_time"] - s["time"]) >= 1e-6
    ]
    if not mismatches:
        return False
    require(
        point["trial_mode"] == "jump"
        and point["queued_input"]
        and len(mismatches) == 1
        and any(
            e["at"] == 0 and "Space" in e["keys"] for e in point["native_timeline"]
        ),
        "unexpected jump cadence failure",
    )
    sample = mismatches[0]
    require(
        sample["cadence"]["tick"] == 1
        and sample["jump_requested_time"] == 0
        and abs(sample["time"] - 1 / rate) < 1e-6,
        "unexpected jump boundary failure",
    )
    # Check the full cadence contract even for a rejected measurement. Use an
    # independent copy only to isolate that already-recorded timing violation;
    # the raw row is never modified, selected, or used as qualifying evidence.
    cadence_only = copy.deepcopy(row)
    cadence_only["trace"][1]["input"]["jump"] = False
    check_cadence(cadence_only, point)
    return True


def selection(grid_path, report_path, project):
    check_report(grid_path, report_path, 60, project)
    points = {p["id"]: p for p in read(grid_path)["cases"]}
    rows = {r["id"]: r for r in read(report_path)["results"]}
    rejected = []
    for key, point in points.items():
        row = rows[key]
        for a, b in zip(row["trace"], row["trace"][1:]):
            require(
                b["cadence"]["process_frame"] - a["cadence"]["process_frame"] == 1
                and b["cadence"]["physics_frame"] - a["cadence"]["physics_frame"] == 1,
                "observed engine counter mismatch",
            )
        if point["trial_mode"] != "jump":
            check_control(row)
        if initial_jump_rejection(point, row, 60):
            rejected.append(key)
        else:
            check_cadence(row, point)
    selected, observations = [], []
    for scheme in SCHEMES:
        choice = None
        for point in points.values():
            if point["scheme"] != scheme or point["trial_mode"] != "jump":
                continue
            controls = [
                point["id"].removesuffix("jump") + m for m in ("no_jump", "walk")
            ]
            if point["id"] in rejected or any(k in rejected for k in controls):
                observations.append(
                    dict(
                        scheme=scheme,
                        variant=point["variant"],
                        passed=False,
                        rejected="initial_tick_jump_consumed_next_tick",
                    )
                )
                continue
            result = qualify(point, rows[point["id"]], 60)
            walked = any(
                outcomes(points[k], rows[k])["supported_arrival"] for k in controls
            )
            observations.append(
                dict(
                    scheme=scheme,
                    variant=point["variant"],
                    controls_arrive=walked,
                    **result,
                )
            )
            if choice is None and result["passed"] and not walked:
                choice = [point, *(points[k] for k in controls)]
        if choice:
            selected.extend(choice)
    return dict(
        read(grid_path),
        stage="ingress_selected_using60_before_holdout",
        cases=selected,
        observations=observations,
        grid_sha256=sha(grid_path),
        selection_report_sha256=sha(report_path),
        rejected_cadence_trials=rejected,
    )


def verify(directory, source, project):
    grid = directory / "grid-v1.json"
    report = directory / "grid-60.json"
    selected_path = directory / "selected-v1.json"
    lock = directory / "selection-lock.json"
    require(
        read(grid) == grid_payload(source, project, directory / "rejected.json"),
        "ingress geometry or inputs changed",
    )
    selected = selection(grid, report, project)
    require(
        read(selected_path) == selected
        and read(lock) == {"selected_sha256": sha(selected_path)},
        "ingress selection lock changed",
    )
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        edge_lip_timing_accepted=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        grid_trials=len(read(report)["results"]),
        replay_trials=0,
        observations=selected["observations"],
        rejected_cadence_trials=selected["rejected_cadence_trials"],
        results=[],
        evidence_sha256={p.name: sha(p) for p in (grid, report, selected_path, lock)},
        parent_surface_sha256=sha(source),
        checker_sha256=sha(Path(__file__)),
    )
    if not selected["cases"]:
        result["surface_ingress_all_profiles"] = False
        return result
    reports = {}
    baseline = {r["id"]: r for r in read(report)["results"]}
    for rate in (60, 120):
        path = directory / f"replay-{rate}.json"
        _, reports[rate] = checked(selected_path, path, rate, project)
        result["evidence_sha256"][path.name] = sha(path)
        result["replay_trials"] += len(reports[rate])
    for point in selected["cases"]:
        key = point["id"]
        require_unchanged_current(baseline[key], reports[60][key])
        if point["trial_mode"] != "jump":
            continue
        results = {str(r): qualify(point, reports[r][key], r) for r in (60, 120)}
        controls = {
            str(r): any(
                outcomes(p, reports[r][p["id"]])["supported_arrival"]
                for p in selected["cases"]
                if p["scheme"] == point["scheme"] and p["trial_mode"] != "jump"
            )
            for r in (60, 120)
        }
        result["results"].append(
            dict(
                scheme=point["scheme"],
                variant=point["variant"],
                rates=results,
                controls_arrive=controls,
                passed=all(v["passed"] for v in results.values())
                and not any(controls.values()),
            )
        )
    result["surface_ingress_all_profiles"] = len(result["results"]) == 3 and all(
        r["passed"] for r in result["results"]
    )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "select", "verify"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(
            args.directory / "grid-v1.json",
            grid_payload(args.source, args.project, args.directory / "rejected.json"),
        )
    elif args.mode == "select":
        path = args.directory / "selected-v1.json"
        freeze(
            path,
            selection(
                args.directory / "grid-v1.json",
                args.directory / "grid-60.json",
                args.project,
            ),
        )
        freeze(args.directory / "selection-lock.json", {"selected_sha256": sha(path)})
    else:
        if args.out is None:
            parser.error("--out required")
        freeze(
            args.out,
            verify(args.directory, args.source, args.project),
            tuple(args.directory.glob("*.json")) + (args.source,),
        )
    print("SURFACE_INGRESS_STUDY_OK", args.mode)
