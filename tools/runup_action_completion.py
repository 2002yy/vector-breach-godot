"""Freeze genuine run-up actions on original Mirage/Inferno geometry without granting routes."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from movement_dimension_gates import action_gate
from movement_evidence_bank import LEVELS, profile_evidence
from native_jump_candidates import RUNTIME, digital, freeze
from queued_three_map_audit import CADENCE_PROBES, PROBES, QUEUE_PROBES
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

MAPS = ("mirage", "inferno")
VARIANTS = ("original", "back250_run150", "back350_run200")
MODES = ("jump", "no_jump", "walk")
PROBE = "tools/authoring/audit_runup_actions.gd"
MINIMUM_DISTANCE = 0.5
MINIMUM_GROUNDED_SECONDS = 0.05
MINIMUM_FORWARD_TAKEOFF = 0.5


def native_timeline(parent, variant) -> list[dict[str, Any]]:
    require(variant in VARIANTS, "unknown frozen run-up input")
    if variant == "original":
        return digital(parent["timeline"])
    back, run = (0.25, 0.15) if variant == "back250_run150" else (0.35, 0.2)
    jump = back + run
    return [
        dict(at=t, keys=keys, mouse_dx=0.0)
        for t, keys in (
            (0.0, ["S"]),
            (back, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 0.1, ["W"]),
            (1.5, []),
        )
    ]


def control_timeline(native, mode) -> list[dict[str, Any]]:
    require(mode in MODES, "unknown control")
    result = copy.deepcopy(native)
    if mode != "jump":
        for event in result:
            event["keys"] = [
                k
                for k in event["keys"]
                if k != "Space" and not (mode == "walk" and k == "Ctrl")
            ]
            if mode == "walk" and "Shift" not in event["keys"]:
                event["keys"].append("Shift")
    return result


def payload(name, source, project, rejection) -> dict[str, Any]:
    manifest = read(source)
    require(
        name in MAPS and manifest["level"] == LEVELS[name], "source map label differs"
    )
    parents = [
        p for p in manifest["cases"] if p["id"] == "run_up" and p["kind"] == "run_up"
    ]
    require(
        manifest["schema"] == 1 and len(parents) == 1, "original run-up case required"
    )
    parent = parents[0]
    hashes = {
        "res://" + p: sha(project / p)
        for p in (*PROBES, *QUEUE_PROBES, *CADENCE_PROBES, PROBE)
    }
    cases = []
    for scheme in SCHEMES:
        for variant in VARIANTS:
            for mode in MODES:
                point = copy.deepcopy(parent)
                point.update(
                    id=f"{scheme}__{variant}__{mode}",
                    parent_case="run_up",
                    scheme=scheme,
                    variant=variant,
                    trial_mode=mode,
                    queued_input=True,
                    ablation="baseline",
                    enforce_cadence=True,
                    rejection_path=str(rejection),
                    probe_sha256=hashes,
                    native_timeline=control_timeline(
                        native_timeline(parent, variant), mode
                    ),
                )
                cases.append(point)
    return dict(
        schema=4,
        formal_qualification=False,
        diagnostic_only=True,
        level=manifest["level"],
        identity=manifest["identity"],
        parent_sha256=sha(source),
        input_map_sha256=sha(project / "project.godot"),
        runtime_sha256={"res://" + p: sha(project / p) for p in RUNTIME},
        cases=cases,
        stage="original_runup_action_grid",
        runup_policy=dict(
            minimum_grounded_distance_m=MINIMUM_DISTANCE,
            minimum_supported_suffix_seconds=MINIMUM_GROUNDED_SECONDS,
            minimum_forward_takeoff_mps=MINIMUM_FORWARD_TAKEOFF,
            scope="independent_action_contract_not_route_or_CS_equivalence",
        ),
    )


def runup_gate(point, row, rate):
    action = action_gate(point, row, rate)
    trace = row["trace"]
    indices = [i for i, s in enumerate(trace) if s["jumped"]]
    result: dict[str, Any] = dict(
        passed=False,
        action_passed=action["passed"],
        supported_suffix_seconds=0.0,
        grounded_distance_m=0.0,
        forward_takeoff_mps=0.0,
    )
    if not action["passed"] or len(indices) != 1:
        return result
    index = indices[0]
    start = index
    while start > 0 and trace[start - 1]["grounded_after"]:
        start -= 1
    duration = (index - start) / rate
    points = [trace[i]["position"] for i in range(start, index)]
    if start == 0:
        points.insert(0, row["settled_start"])
    distance = sum(
        math.hypot(b[0] - a[0], b[2] - a[2]) for a, b in zip(points, points[1:])
    )
    jump = trace[index]
    direction = (-math.sin(point["yaw"]), -math.cos(point["yaw"]))
    speed = jump["velocity"][0] * direction[0] + jump["velocity"][2] * direction[1]
    return dict(
        result,
        supported_suffix_seconds=duration,
        grounded_distance_m=distance,
        forward_takeoff_mps=speed,
        passed=bool(
            duration + 1e-9 >= MINIMUM_GROUNDED_SECONDS
            and distance >= MINIMUM_DISTANCE
            and speed >= MINIMUM_FORWARD_TAKEOFF
        ),
    )


def selected_payload(name, directory, project):
    grid = directory / f"{name}-grid-v1.json"
    require(
        name in MAPS and read(grid)["level"] == LEVELS[name], "grid map label differs"
    )
    points, rows = checked(grid, directory / f"{name}-grid-60.json", 60, project)
    cases, observations = [], []
    for scheme in SCHEMES:
        choice = None
        for variant in VARIANTS:
            point = points[f"{scheme}__{variant}__jump"]
            score = runup_gate(point, rows[point["id"]], 60)
            observations.append(dict(scheme=scheme, variant=variant, **score))
            if choice is None and score["passed"]:
                choice = variant
        if choice is not None:
            cases.extend(points[f"{scheme}__{choice}__{mode}"] for mode in MODES)
    return dict(
        read(grid),
        cases=cases,
        stage="runup_action_selected60_before_current120_replay",
        grid_sha256=sha(grid),
        selection_report_sha256=sha(directory / f"{name}-grid-60.json"),
        observations=observations,
    )


def select(directory, project):
    result = {}
    for name in MAPS:
        selected = selected_payload(name, directory, project)
        path = directory / f"{name}-selected-v1.json"
        freeze(path, selected)
        result[name] = sha(path)
    freeze(directory / "selection-lock.json", result)


def with_runup_contract(profile, runup) -> dict[str, Any]:
    require(set(runup) == {"60", "120"}, "both run-up rates required")
    passed = all(v["passed"] for v in runup.values())
    result: dict[str, Any] = dict(profile, runup=runup, category_action_passed=passed)
    if not passed and (
        result["jump_route_passed"] or result["status"] == "qualified_jump"
    ):
        result.update(status="route_unproven", jump_route_passed=False)
    return result


def verify(directory, sources, project) -> dict[str, Any]:
    sites = []
    for name in MAPS:
        grid, selected = (
            directory / f"{name}-grid-v1.json",
            directory / f"{name}-selected-v1.json",
        )
        require(
            read(grid)
            == payload(
                name,
                sources / f"{name}-manifest.json",
                project,
                directory / f"{name}-rejected.json",
            ),
            "frozen original geometry or run-up policy changed",
        )
        data = read(selected)
        require(
            data == selected_payload(name, directory, project),
            "selected action inputs or observations changed",
        )
        require(
            read(directory / "selection-lock.json")[name] == sha(selected),
            "selection lock changed",
        )
        points = {p["id"]: p for p in data["cases"]}
        require(
            len(points) == 9 and {p["scheme"] for p in points.values()} == set(SCHEMES),
            "incomplete selected profiles",
        )
        rows = {}
        for rate in (60, 120):
            _, rows[rate] = checked(
                selected, directory / f"{name}-{rate}.json", rate, project
            )
        _, grid_rows = checked(grid, directory / f"{name}-grid-60.json", 60, project)
        profiles = {}
        for scheme in SCHEMES:
            jump = next(
                p
                for p in points.values()
                if p["scheme"] == scheme and p["trial_mode"] == "jump"
            )
            controls = {
                m: points[jump["id"].removesuffix("jump") + m]
                for m in ("no_jump", "walk")
            }
            for point in (jump, *controls.values()):
                require_unchanged_current(grid_rows[point["id"]], rows[60][point["id"]])
            profile = profile_evidence(
                jump,
                {r: rows[r][jump["id"]] for r in (60, 120)},
                {
                    r: {m: rows[r][p["id"]] for m, p in controls.items()}
                    for r in (60, 120)
                },
                controls,
            )
            runup = {
                str(r): runup_gate(jump, rows[r][jump["id"]], r) for r in (60, 120)
            }
            profiles[scheme] = with_runup_contract(profile, runup)
        sites.append(
            dict(map=name, kind="run_up", profiles=profiles, human_review="pending")
        )
    return dict(
        schema=1,
        sites=sites,
        new_grid_trials=54,
        new_selected_trials=36,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        scope="runup_actions_on_original_geometry_not_complete_route_acceptance",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "select", "verify"))
    parser.add_argument("sources", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        for name in MAPS:
            freeze(
                args.directory / f"{name}-grid-v1.json",
                payload(
                    name,
                    args.sources / f"{name}-manifest.json",
                    args.project,
                    args.directory / f"{name}-rejected.json",
                ),
            )
    elif args.mode == "select":
        select(args.directory, args.project)
    else:
        summary = verify(args.directory, args.sources, args.project)
        freeze(args.directory / "validated-summary.json", summary)
        print(
            "RUNUP_ACTION_COMPLETION_VERIFIED",
            [
                (
                    s["map"],
                    {p: v["category_action_passed"] for p, v in s["profiles"].items()},
                )
                for s in summary["sites"]
            ],
        )
