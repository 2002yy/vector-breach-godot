"""Bounded replacement edge discovery; select with Current/60 before holdout replay."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from movement_dimension_gates import action_gate, check_control
from native_jump_candidates import check_report, freeze
from ordinary_edge_actions import edge_context, payload
from queued_three_map_audit import check_cadence
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

MAPS = ("dust2", "inferno")
LIMIT = 8


def shortlist(records):
    chosen, seen = [], set()
    for index, record in enumerate(records):
        key = tuple(record["feet"] + record["direction"])
        if key in seen:
            continue
        seen.add(key)
        chosen.append((index, record))
        if len(chosen) == LIMIT:
            break
    require(bool(chosen), "no surveyed drop candidates")
    return chosen


def grid_payload(source, project, rejection, records=None):
    base = payload(source, project, rejection)
    templates = [
        p
        for p in base["cases"]
        if p["parent_case"] == "edge" and p["scheme"] == "current"
    ]
    cases = []
    candidates = read(source)["survey"]["drops"] if records is None else records
    for index, record in shortlist(candidates):
        require(-2 <= record["height_change"] <= -0.5, "not a surveyed drop")
        for original in templates:
            point = copy.deepcopy(original)
            point.update(
                id=f"drop_{index:02d}__current__{point['trial_mode']}",
                parent_case=f"drop_{index:02d}",
                survey_index=index,
                start=[record["feet"][0], record["feet"][1] + 0.91, record["feet"][2]],
                target_feet=record["target_feet"],
                yaw=math.atan2(-record["direction"][0], -record["direction"][2]),
                source_nav_node=record["node"],
                geometry=copy.deepcopy(record),
            )
            cases.append(point)
    return dict(
        base,
        stage="bounded_current60_grid",
        cases=cases,
        candidate_limit=LIMIT,
        selection_policy="first_actual_drop_and_takeoff_current60",
    )


def checked(manifest, report, rate, project):
    check_report(manifest, report, rate, project)
    points = {p["id"]: p for p in read(manifest)["cases"]}
    rows = {r["id"]: r for r in read(report)["results"]}
    for key, point in points.items():
        row = rows[key]
        check_cadence(row, point)
        for a, b in zip(row["trace"], row["trace"][1:]):
            require(
                b["cadence"]["process_frame"] - a["cadence"]["process_frame"] == 1
                and b["cadence"]["physics_frame"] - a["cadence"]["physics_frame"] == 1,
                "observed engine counter mismatch",
            )
        if point["trial_mode"] != "jump":
            check_control(row)
    return points, rows


def choose(grid, rows):
    observations, selected = [], None
    for point in grid["cases"]:
        if point["trial_mode"] != "jump":
            continue
        key = point["parent_case"]
        action = action_gate(point, rows[point["id"]], 60)
        context = edge_context(point, rows[f"{key}__current__no_jump"])
        observations.append(dict(candidate=key, action=action["passed"], drop=context))
        if selected is None and action["passed"] and context:
            selected = key
    return selected, observations


def selected_payload(grid_path, report_path, project):
    grid = read(grid_path)
    _, rows = checked(grid_path, report_path, 60, project)
    selected, observations = choose(grid, rows)
    cases = []
    for original in grid["cases"]:
        if original["parent_case"] != selected:
            continue
        for scheme in SCHEMES:
            point = copy.deepcopy(original)
            point.update(
                id=f"{selected}__{scheme}__{point['trial_mode']}", scheme=scheme
            )
            cases.append(point)
    return dict(
        grid,
        stage="selected_current60_before_holdout",
        cases=cases,
        grid_sha256=sha(grid_path),
        selection_report_sha256=sha(report_path),
        selected=selected,
        observations=observations,
    )


def verify(directory, sources, project):
    lock_path = directory / "selection-lock.json"
    lock = read(lock_path)
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        edge_lip_timing_accepted=False,
        route_qualification_replaced=False,
        human_acceptance=False,
        selection_hz=60,
        holdout_hz=120,
        grid_trials=0,
        replay_trials=0,
        results=[],
        exploration=[],
        checker_sha256=sha(Path(__file__)),
        evidence_sha256={lock_path.name: sha(lock_path)},
    )
    require(set(lock) == set(MAPS), "both map selections must be locked before holdout")
    for name in MAPS:
        source = sources / f"{name}-manifest.json"
        grid_path = directory / f"{name}-grid-v1.json"
        grid_report = directory / f"{name}-grid-60.json"
        selected_path = directory / f"{name}-selected-v1.json"
        require(
            read(grid_path)
            == grid_payload(source, project, directory / f"{name}-rejected.json"),
            "grid source or bounded selection changed",
        )
        selected = selected_payload(grid_path, grid_report, project)
        require(
            read(selected_path) == selected and lock[name] == sha(selected_path),
            "locked selection changed",
        )
        result["grid_trials"] += len(read(grid_report)["results"])
        result["exploration"].append(
            dict(map=name, observations=selected["observations"])
        )
        for path in (grid_path, grid_report, selected_path):
            result["evidence_sha256"][path.name] = sha(path)
        result["evidence_sha256"][f"source/{source.name}"] = sha(source)
        if selected["selected"] is None:
            require(not selected["cases"], "unselected map contains replay cases")
            result["results"].append(
                dict(
                    map=name,
                    candidate=None,
                    status="bounded_candidates_exhausted",
                    route_status="not_requalified",
                )
            )
            continue
        replay = {}
        for rate in (60, 120):
            report = directory / f"{name}-{rate}.json"
            _, replay[rate] = checked(selected_path, report, rate, project)
            result["replay_trials"] += len(replay[rate])
            result["evidence_sha256"][report.name] = sha(report)
        grid_rows = {r["id"]: r for r in read(grid_report)["results"]}
        for point in selected["cases"]:
            key = point["id"]
            if point["scheme"] == "current":
                require_unchanged_current(grid_rows[key], replay[60][key])
            if point["trial_mode"] != "jump":
                continue
            parent, scheme = point["parent_case"], point["scheme"]
            result["results"].append(
                dict(
                    map=name,
                    candidate=parent,
                    scheme=scheme,
                    actions={
                        str(r): action_gate(point, replay[r][key], r) for r in (60, 120)
                    },
                    drop_context={
                        str(r): edge_context(
                            point, replay[r][f"{parent}__{scheme}__no_jump"]
                        )
                        for r in (60, 120)
                    },
                    route_status="not_requalified",
                )
            )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "select", "verify"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.mode == "freeze":
        for name in MAPS:
            source = args.sources / f"{name}-manifest.json"
            freeze(
                args.directory / f"{name}-grid-v1.json",
                grid_payload(
                    source, args.project, args.directory / f"{name}-rejected.json"
                ),
                (source,),
            )
    elif args.mode == "select":
        lock = {}
        for name in MAPS:
            path = args.directory / f"{name}-selected-v1.json"
            freeze(
                path,
                selected_payload(
                    args.directory / f"{name}-grid-v1.json",
                    args.directory / f"{name}-grid-60.json",
                    args.project,
                ),
            )
            lock[name] = sha(path)
        freeze(args.directory / "selection-lock.json", lock)
    else:
        if args.out is None:
            parser.error("--out required")
        freeze(
            args.out,
            verify(args.directory, args.sources, args.project),
            tuple(args.directory.glob("*.json")) + tuple(args.sources.glob("*.json")),
        )
    print("EDGE_DROP_REVISION_OK", args.mode)
