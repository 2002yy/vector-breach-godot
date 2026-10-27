"""Freeze bounded replacement run-up routes without changing original map geometry."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from movement_evidence_bank import LEVELS, profile_evidence
from native_jump_candidates import RUNTIME, freeze, outcomes
from runup_action_completion import (
    CADENCE_PROBES,
    PROBES,
    QUEUE_PROBES,
    control_timeline,
    runup_gate,
    with_runup_contract,
)
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

MAPS = ("mirage", "inferno")
LIMIT = 6
RUNNER = "tools/authoring/audit_runup_routes.gd"
PARENT_RUNNER = "tools/authoring/audit_runup_actions.gd"


def grid_payload(name, source, project, rejection):
    manifest = read(source)
    require(name in MAPS and manifest["level"] == LEVELS[name], "source map differs")
    require(manifest["schema"] == 1, "original survey manifest required")
    records = manifest["survey"]["rises"][:LIMIT]
    require(records, "no surveyed rises")
    hashes = {
        "res://" + p: sha(project / p)
        for p in (*PROBES, *QUEUE_PROBES, *CADENCE_PROBES, PARENT_RUNNER, RUNNER)
    }
    cases = []
    for index, record in enumerate(records):
        require(0.5 <= record["height_change"] <= 1.45, "not eligible surveyed rise")
        direction = record["direction"]
        start = [v - d * 0.6 for v, d in zip(record["feet"], direction)]
        start[1] += 0.91
        native = [
            dict(at=t, keys=k, mouse_dx=0.0)
            for t, k in (
                (0.0, ["W"]),
                (0.2, ["W", "Space"]),
                (0.2 + 1 / 60, ["S", "Space"]),
                (0.3, ["S"]),
                (0.3 + 1 / 60, []),
                (1.5, []),
            )
        ]
        for mode in ("jump", "no_jump", "walk"):
            cases.append(
                dict(
                    id=f"rise_{index:02d}__current__{mode}",
                    parent_case=f"rise_{index:02d}",
                    kind="run_up",
                    scheme="current",
                    trial_mode=mode,
                    start=start,
                    yaw=math.atan2(-direction[0], -direction[2]),
                    target_feet=record["target_feet"],
                    target_radius=1.6,
                    target_height_tolerance=0.18,
                    duration=2.0,
                    source_nav_node=record["node"],
                    geometry=copy.deepcopy(record),
                    native_timeline=control_timeline(native, mode),
                    timeline=[
                        dict(at=0.0, direction=[0, -1]),
                        dict(at=0.2, jump=True),
                        dict(at=0.3, jump=False),
                        dict(at=1.5, direction=[0, 0]),
                    ],
                    queued_input=True,
                    enforce_cadence=True,
                    ablation="baseline",
                    rejection_path=str(rejection),
                    probe_sha256=hashes,
                )
            )
    return dict(
        schema=4,
        level=manifest["level"],
        identity=manifest["identity"],
        formal_qualification=False,
        diagnostic_only=True,
        parent_sha256=sha(source),
        input_map_sha256=sha(project / "project.godot"),
        runtime_sha256={"res://" + p: sha(project / p) for p in RUNTIME},
        stage="runup_route_revision_grid",
        cases=cases,
        selection_policy="first_current60_runup_landing_clear_corridor_nonwalking",
        candidate_limit=LIMIT,
    )


def choose(manifest, rows):
    observations, selected = [], None
    points = {p["id"]: p for p in manifest["cases"]}
    for point in manifest["cases"]:
        if point["trial_mode"] != "jump":
            continue
        row = rows[point["id"]]
        root = point["id"].removesuffix("jump")
        controls = {
            m: outcomes(points[root + m], rows[root + m])["supported_arrival"]
            for m in ("no_jump", "walk")
        }
        corridor = row["ingress_corridor"]
        eligible = (
            runup_gate(point, row, 60)["passed"]
            and outcomes(point, row)["first_landing"]
            and corridor["status"] == "geometric_corridor_found"
            and not any(controls.values())
        )
        observations.append(
            dict(
                candidate=point["parent_case"],
                runup=runup_gate(point, row, 60),
                first_landing=outcomes(point, row)["first_landing"],
                corridor=corridor["status"],
                controls=controls,
                eligible=eligible,
            )
        )
        if selected is None and eligible:
            selected = point["parent_case"]
    return selected, observations


def selected_payload(name, directory, project):
    grid = directory / f"{name}-grid-v1.json"
    data = read(grid)
    require(data["level"] == LEVELS[name], "grid map differs")
    _, rows = checked(grid, directory / f"{name}-grid-60.json", 60, project)
    selected, observations = choose(data, rows)
    cases = []
    for point in data["cases"]:
        if point["parent_case"] == selected:
            for scheme in SCHEMES:
                item = copy.deepcopy(point)
                item.update(
                    id=item["id"].replace("__current__", f"__{scheme}__"), scheme=scheme
                )
                cases.append(item)
    return dict(
        data,
        stage="runup_route_revision_selected",
        cases=cases,
        selected=selected,
        observations=observations,
        grid_sha256=sha(grid),
        report_sha256=sha(directory / f"{name}-grid-60.json"),
    )


def verify(name, source, directory, project) -> dict[str, Any]:
    grid = directory / f"{name}-grid-v1.json"
    require(
        read(grid)
        == grid_payload(name, source, project, directory / f"{name}-rejected.json"),
        "grid changed",
    )
    data = selected_payload(name, directory, project)
    selected = directory / f"{name}-selected-v1.json"
    require(read(selected) == data, "selection changed")
    profiles = {}
    if data["selected"] is not None:
        points, r60 = checked(selected, directory / f"{name}-60.json", 60, project)
        _, r120 = checked(selected, directory / f"{name}-120.json", 120, project)
        rows = {60: r60, 120: r120}
        _, original = checked(grid, directory / f"{name}-grid-60.json", 60, project)
        for point in points.values():
            if point["scheme"] == "current":
                require_unchanged_current(original[point["id"]], r60[point["id"]])
        for scheme in SCHEMES:
            jump = next(
                p
                for p in points.values()
                if p["scheme"] == scheme and p["trial_mode"] == "jump"
            )
            prefix = jump["id"].removesuffix("jump")
            controls = {m: points[prefix + m] for m in ("no_jump", "walk")}
            profile = profile_evidence(
                jump,
                {r: rows[r][jump["id"]] for r in rows},
                {r: {m: rows[r][p["id"]] for m, p in controls.items()} for r in rows},
                controls,
            )
            profiles[scheme] = with_runup_contract(
                profile,
                {str(r): runup_gate(jump, rows[r][jump["id"]], r) for r in rows},
            )
    return dict(
        map=name,
        selected=data["selected"],
        observations=data["observations"],
        profiles=profiles,
        formal_release_ready=False,
        human_acceptance=False,
        original_failures_preserved=True,
        production_changed=False,
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
    for name in MAPS:
        source = args.sources / f"{name}-manifest.json"
        if args.mode == "freeze":
            freeze(
                args.directory / f"{name}-grid-v1.json",
                grid_payload(
                    name, source, args.project, args.directory / f"{name}-rejected.json"
                ),
            )
        elif args.mode == "select":
            freeze(
                args.directory / f"{name}-selected-v1.json",
                selected_payload(name, args.directory, args.project),
            )
        else:
            result = verify(name, source, args.directory, args.project)
            freeze(args.directory / f"{name}-verified.json", result)
            print(
                name,
                result["selected"],
                {k: v["status"] for k, v in result["profiles"].items()},
            )
