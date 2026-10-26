"""Freeze a navigation-point approach and uninterrupted native surface ingress."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from map_jump_qualification import clear_corridor
from native_jump_candidates import freeze, inside, outcomes
from surface_ingress_study import qualify, timeline
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

PROBE = "tools/authoring/audit_navigation_ingress.gd"


def navigation_start(points, checkpoint, goal):
    dx, dz = goal[0] - checkpoint[0], goal[2] - checkpoint[2]
    length = math.hypot(dx, dz)
    require(length > 0, "zero ingress direction")
    candidates = []
    for index, position in enumerate(points):
        x, z = position[0] - checkpoint[0], position[2] - checkpoint[2]
        behind = -(x * dx + z * dz) / length
        lateral = abs(x * dz - z * dx) / length
        if (
            1 <= behind <= 2
            and lateral <= 0.1
            and abs(position[1] - checkpoint[1]) <= 0.15
        ):
            candidates.append((math.hypot(x, z), index, position))
    require(bool(candidates), "no aligned authored approach node in frozen range")
    _, node, start = min(candidates)
    return node, start


def grid_payload(source, project, rejection):
    parent = read(source)
    require(
        parent["stage"] == "ingress_selected_using60_before_holdout"
        and parent["formal_qualification"] is False,
        "wrong ingress parent",
    )
    original = next(
        p
        for p in parent["cases"]
        if p["scheme"] == "current" and p["trial_mode"] == "jump"
    )
    layout = project / "data/levels/match-local/dustline.json"
    require(
        sha(layout) == parent["identity"]["layout_sha256"], "navigation layout drift"
    )
    node, start = navigation_start(
        read(layout)["layout"]["navigationGraph"]["points"],
        original["start"],
        original["target_feet"],
    )
    cases = []
    for scheme in SCHEMES:
        for jump in (0.2, 0.25, 0.3, 0.35, 0.4):
            for travel in (0.15, 0.3):
                variant = f"jump{round(jump * 1000)}_travel{round(travel * 1000)}"
                for mode in ("jump", "no_jump", "walk"):
                    point = copy.deepcopy(original)
                    native = timeline(jump, travel, False)
                    for event in native:
                        if mode != "jump":
                            event["keys"] = [k for k in event["keys"] if k != "Space"]
                        if mode == "walk":
                            event["keys"].append("Shift")
                    point.update(
                        id=f"{scheme}__{variant}__{mode}",
                        scheme=scheme,
                        parent_case="navigation_ingress",
                        variant=variant,
                        trial_mode=mode,
                        start=copy.deepcopy(start),
                        source_nav_node=node,
                        native_timeline=native,
                        approach_feet=[
                            original["start"][0],
                            original["start"][1] - 0.91,
                            original["start"][2],
                        ],
                        approach_radius=0.12,
                        approach_height_tolerance=0.18,
                        minimum_approach_travel=0.1,
                        input_surface="authored_navigation_start",
                        ingress_origin="authored_navigation_node",
                        rejection_path=str(rejection),
                    )
                    point["probe_sha256"]["res://" + PROBE] = sha(project / PROBE)
                    cases.append(point)
    return dict(
        parent,
        cases=cases,
        stage="predeclared_navigation_ingress_grid",
        parent_ingress_sha256=sha(source),
        formal_qualification=False,
        spawn_to_navigation_connectivity="unproven",
    )


def approach_gate(point, row) -> dict[str, Any]:
    checkpoint = dict(
        target_feet=point["approach_feet"],
        target_radius=point["approach_radius"],
        target_height_tolerance=point["approach_height_tolerance"],
    )
    for index, sample in enumerate(row["trace"]):
        if sample["input"]["jump"]:
            break
        position = sample["position"]
        travel = math.hypot(
            position[0] - point["start"][0], position[2] - point["start"][2]
        )
        if (
            inside(checkpoint, sample)
            and travel >= point["minimum_approach_travel"]
            and index > 0
            and all(s["grounded_after"] for s in row["trace"][1 : index + 1])
        ):
            return dict(
                passed=True, checkpoint_time=sample["time"], horizontal_travel=travel
            )
    return dict(passed=False, checkpoint_time=None, horizontal_travel=None)


def score(point, row, rate):
    ingress = qualify(point, row, rate)
    approach = approach_gate(point, row)
    corridor = clear_corridor(
        dict(point, target_feet=point["approach_feet"]), row["approach_corridor"]
    )[0]
    return dict(
        ingress=ingress,
        approach=approach,
        approach_corridor=corridor,
        passed=bool(ingress["passed"] and approach["passed"] and corridor),
    )


def selection(grid, report, project):
    points, rows = checked(grid, report, 60, project)
    observations, selected = [], []
    for scheme in SCHEMES:
        choice = None
        for point in points.values():
            if point["scheme"] != scheme or point["trial_mode"] != "jump":
                continue
            controls = [
                point["id"].removesuffix("jump") + m for m in ("no_jump", "walk")
            ]
            result = score(point, rows[point["id"]], 60)
            controls_arrive = any(
                outcomes(points[k], rows[k])["supported_arrival"] for k in controls
            )
            observations.append(
                dict(
                    scheme=scheme,
                    variant=point["variant"],
                    controls_arrive=controls_arrive,
                    **result,
                )
            )
            if choice is None and result["passed"] and not controls_arrive:
                choice = [point, *(points[k] for k in controls)]
        if choice:
            selected.extend(choice)
    return dict(
        read(grid),
        cases=selected,
        observations=observations,
        stage="navigation_ingress_selected60_before_holdout",
        grid_sha256=sha(grid),
        selection_report_sha256=sha(report),
    )


def verify(directory, source, project):
    grid, report = directory / "grid-v1.json", directory / "grid-60.json"
    selected_path, lock = (
        directory / "selected-v1.json",
        directory / "selection-lock.json",
    )
    require(
        read(grid) == grid_payload(source, project, directory / "rejected.json"),
        "frozen navigation approach changed",
    )
    selected = selection(grid, report, project)
    require(
        read(selected_path) == selected
        and read(lock) == {"selected_sha256": sha(selected_path)},
        "selection or lock changed",
    )
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        edge_lip_timing_accepted=False,
        spawn_to_navigation_connectivity="unproven",
        route_status="not_requalified",
        grid_trials=len(read(report)["results"]),
        replay_trials=0,
        observations=selected["observations"],
        results=[],
        checker_sha256=sha(Path(__file__)),
        evidence_sha256={p.name: sha(p) for p in (grid, report, selected_path, lock)},
        parent_ingress_sha256=sha(source),
    )
    if selected["cases"]:
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
            rates = {str(r): score(point, reports[r][key], r) for r in (60, 120)}
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
                    rates=rates,
                    controls_arrive=controls,
                    passed=all(s["passed"] for s in rates.values())
                    and not any(controls.values()),
                )
            )
    result["navigation_ingress_all_profiles"] = len(result["results"]) == 3 and all(
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
    print("NAVIGATION_INGRESS_STUDY_OK", args.mode)
