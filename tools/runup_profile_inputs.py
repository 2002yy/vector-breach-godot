"""Freeze profile-specific inputs on an unchanged Mirage run-up route."""

import argparse
import copy
import subprocess
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from movement_evidence_bank import LEVELS, profile_evidence
from native_jump_candidates import freeze, outcomes
from runup_action_completion import control_timeline, runup_gate, with_runup_contract
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

SCHEMES = ("legacy_16", "modern_cs")
MODES = ("jump", "no_jump", "walk")
BRAKES = (0, 1 / 60, 1 / 30)
RUNNER = "tools/authoring/audit_runup_routes.gd"


def timeline(scheme, brake, jump_time=None) -> list[dict[str, Any]]:
    require(scheme in SCHEMES and brake in BRAKES, "unknown frozen input")
    jump = 0.2 if scheme == "legacy_16" else 0.25
    if jump_time is not None:
        require(
            scheme == "legacy_16" and brake == 0 and jump_time in (0.25, 0.30, 0.35),
            "unknown Legacy follow-up input",
        )
        jump = jump_time
    events = [(0.0, ["W"]), (jump, ["W", "Space"])]
    events.append((jump + 1 / 60, ["S"] if brake else []))
    if brake:
        events.append((jump + 1 / 60 + brake, []))
    events.append((1.5, []))
    return [dict(at=t, keys=k, mouse_dx=0.0) for t, k in events]


def source_data(source, project):
    manifest = source / "mirage-selected-v1.json"
    data = read(manifest)
    require(
        data["level"] == LEVELS["mirage"]
        and data["schema"] == 4
        and data["selected"] == "rise_05",
        "frozen Mirage rise_05 source required",
    )
    for rate in (60, 120):
        checked(manifest, source / f"mirage-{rate}.json", rate, project)
    return data


def payload(source, directory, project, legacy_followup=False):
    data = source_data(source, project)
    cases = []
    for scheme in SCHEMES:
        parent = next(
            p
            for p in data["cases"]
            if p["scheme"] == scheme and p["trial_mode"] == "jump"
        )
        for index, brake in enumerate(BRAKES):
            for mode in MODES:
                point = copy.deepcopy(parent)
                point.update(
                    id=f"{scheme}__brake{index}__{mode}",
                    source_case=parent["id"],
                    variant=index,
                    trial_mode=mode,
                    native_timeline=control_timeline(timeline(scheme, brake), mode),
                    rejection_path=str(directory / "rejected.json"),
                )
                cases.append(point)
    result = dict(
        data,
        cases=cases,
        stage="profile_specific_runup_inputs_grid",
        source_manifest_sha256=sha(source / "mirage-selected-v1.json"),
        source_reports_sha256={
            str(r): sha(source / f"mirage-{r}.json") for r in (60, 120)
        },
        policy="first_60Hz_runup_firstlanding_clearcorridor_and_no_control_arrival",
        historical_exposure=True,
    )
    if legacy_followup:
        result["cases"] = [p for p in cases if p["scheme"] == "legacy_16"]
        for point in result["cases"]:
            jump_time = (0.25, 0.30, 0.35)[point["variant"]]
            point.update(
                id=point["id"].replace("__brake", "__later"),
                followup_jump_seconds=jump_time,
                native_timeline=control_timeline(
                    timeline("legacy_16", 0, jump_time), point["trial_mode"]
                ),
            )
        result["stage"] = "legacy_later_launch_v2_grid"
    return result


def choose(data, rows):
    points = {p["id"]: p for p in data["cases"]}
    schemes = {p["scheme"] for p in data["cases"]}
    require(schemes and schemes <= set(SCHEMES), "unknown profile subset")
    selected = {s: None for s in SCHEMES if s in schemes}
    observations = []
    for point in data["cases"]:
        if point["trial_mode"] != "jump":
            continue
        row = rows[point["id"]]
        prefix = point["id"].removesuffix("jump")
        controls = {
            m: outcomes(points[prefix + m], rows[prefix + m])["supported_arrival"]
            for m in ("no_jump", "walk")
        }
        action = runup_gate(point, row, 60)
        landing = outcomes(point, row)["first_landing"]
        corridor = row["ingress_corridor"]["status"]
        eligible = (
            action["passed"]
            and landing
            and corridor == "geometric_corridor_found"
            and not any(controls.values())
        )
        observations.append(
            dict(
                scheme=point["scheme"],
                variant=point["variant"],
                runup=action,
                first_landing=landing,
                corridor=corridor,
                controls=controls,
                eligible=bool(eligible),
            )
        )
        if eligible and selected[point["scheme"]] is None:
            selected[point["scheme"]] = point["variant"]
    return selected, observations


def selected_payload(directory, project):
    matrix = directory / "grid-v1.json"
    data = read(matrix)
    require(data["level"] == LEVELS["mirage"], "grid map differs")
    _, rows = checked(matrix, directory / "grid-60.json", 60, project)
    selected, observations = choose(data, rows)
    cases = [p for p in data["cases"] if selected[p["scheme"]] == p["variant"]]
    return dict(
        data,
        cases=cases,
        selected_profiles=selected,
        observations=observations,
        grid_sha256=sha(matrix),
        grid_report_sha256=sha(directory / "grid-60.json"),
        stage="profile_specific_runup_selected",
    )


def verify(source, directory, project, legacy_followup=False) -> dict[str, Any]:
    grid = directory / "grid-v1.json"
    require(
        read(grid) == payload(source, directory, project, legacy_followup),
        "frozen grid changed",
    )
    selected = directory / "selected-v1.json"
    data = selected_payload(directory, project)
    require(read(selected) == data, "selection changed")
    profiles = {}
    if data["cases"]:
        points, a = checked(selected, directory / "60.json", 60, project)
        _, b = checked(selected, directory / "120.json", 120, project)
        _, grid_rows = checked(grid, directory / "grid-60.json", 60, project)
        for point in points.values():
            require_unchanged_current(grid_rows[point["id"]], a[point["id"]])
        rows = {60: a, 120: b}
        for scheme, variant in data["selected_profiles"].items():
            if variant is None:
                continue
            jump = next(
                p
                for p in points.values()
                if p["scheme"] == scheme
                and p["variant"] == variant
                and p["trial_mode"] == "jump"
            )
            prefix = jump["id"].removesuffix("jump")
            controls = {m: points[prefix + m] for m in ("no_jump", "walk")}
            profiles[scheme] = with_runup_contract(
                profile_evidence(
                    jump,
                    {r: rows[r][jump["id"]] for r in rows},
                    {
                        r: {m: rows[r][p["id"]] for m, p in controls.items()}
                        for r in rows
                    },
                    controls,
                ),
                {str(r): runup_gate(jump, rows[r][jump["id"]], r) for r in rows},
            )
    return dict(
        schema=1,
        selected=data["selected_profiles"],
        observations=data["observations"],
        profiles=profiles,
        formal_release_ready=False,
        production_changed=False,
        historical_exposure=True,
        source_and_target_unchanged=True,
        grid_trials=len(read(grid)["cases"]),
        selected_trials=len(data["cases"]) * 2,
        reports_sha256={
            p.name: sha(p)
            for p in directory.glob("*.json")
            if p.name in ("grid-60.json", "60.json", "120.json")
        },
    )


def run(directory, project, executable, selected):
    matrix = directory / ("selected-v1.json" if selected else "grid-v1.json")
    if not read(matrix)["cases"]:
        return
    for rate in (60, 120) if selected else (60,):
        target = directory / (f"{rate}.json" if selected else "grid-60.json")
        require(not target.exists(), "refuse overwriting raw report")
        log = target.with_suffix(".log")
        require(not log.exists(), "refuse overwriting raw log")
        with log.open("w", encoding="utf-8") as stream:
            subprocess.run(
                [
                    str(executable),
                    "--headless",
                    "--path",
                    str(project),
                    "--single-threaded-scene",
                    "--rendering-method",
                    "gl_compatibility",
                    "--fixed-fps",
                    str(rate),
                    "--quit-after",
                    "10000",
                    "-s",
                    RUNNER,
                    "--",
                    "replay",
                    str(matrix),
                    str(target),
                    str(rate),
                ],
                cwd=project,
                stdout=stream,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=180,
            )
        output = log.read_text(encoding="utf-8")
        require(
            "NATIVE_ROUTE_KEYBOARD_WRITTEN" in output
            and "SCRIPT ERROR:" not in output
            and "\nERROR:" not in output,
            "native producer failed",
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=("freeze", "grid", "select", "replay", "verify")
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--legacy-followup", action="store_true")
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument(
        "--godot",
        type=Path,
        default=Path("D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe"),
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(
            args.directory / "grid-v1.json",
            payload(args.source, args.directory, args.project, args.legacy_followup),
        )
    elif args.mode in ("grid", "replay"):
        run(args.directory, args.project, args.godot, args.mode == "replay")
    elif args.mode == "select":
        freeze(
            args.directory / "selected-v1.json",
            selected_payload(args.directory, args.project),
        )
    else:
        result = verify(args.source, args.directory, args.project, args.legacy_followup)
        freeze(args.directory / "validated-summary.json", result)
        print("PROFILE_RUNUP_INPUTS_VERIFIED", result["selected"])
