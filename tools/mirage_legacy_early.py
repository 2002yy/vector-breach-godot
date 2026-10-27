"""Freeze earlier Legacy takeoff on the unchanged Mirage rise_05 route."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from movement_evidence_bank import geometry_matches, profile_evidence
from native_jump_candidates import freeze
from runup_action_completion import control_timeline, with_runup_contract, runup_gate
from runup_profile_inputs import run, selected_payload, source_data
from runup_profile_inputs import verify as verify_prior
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

TIMES = (0.15, 1 / 6, 11 / 60)
MODES = ("jump", "no_jump", "walk")


def timeline(jump) -> list[dict[str, Any]]:
    require(jump in TIMES, "unknown early launch time")
    return [
        dict(at=t, keys=keys, mouse_dx=0.0)
        for t, keys in (
            (0.0, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 1 / 60, []),
            (1.5, []),
        )
    ]


def prefix(row, time):
    samples = [s for s in row["trace"] if s["time"] < time - 1e-6]
    require(
        samples and all(s["grounded_after"] for s in samples),
        "supported prefix required",
    )
    points = [row["settled_start"]] + [s["position"] for s in samples]
    distance = sum(
        math.hypot(b[0] - a[0], b[2] - a[2]) for a, b in zip(points, points[1:])
    )
    return dict(jump_seconds=time, grounded_distance_m=distance)


def payload(source, prior, directory, project):
    data = source_data(source, project)
    verify_prior(source, prior / "legacy-v2", project, True)
    matrix = prior / "legacy-v2/grid-v1.json"
    report = prior / "legacy-v2/grid-60.json"
    _, old_rows = checked(matrix, report, 60, project)
    observed = [prefix(old_rows["legacy_16__later0__no_jump"], t) for t in TIMES]
    require(
        all(p["grounded_distance_m"] >= 0.5 for p in observed),
        "early timing lacks run-up distance",
    )
    parent = next(
        p
        for p in data["cases"]
        if p["scheme"] == "legacy_16" and p["trial_mode"] == "jump"
    )
    cases = []
    for index, time in enumerate(TIMES):
        for mode in MODES:
            point = copy.deepcopy(parent)
            point.update(
                id=f"legacy_16__early{index}__{mode}",
                source_case=parent["id"],
                variant=index,
                trial_mode=mode,
                early_jump_seconds=time,
                native_timeline=control_timeline(timeline(time), mode),
                rejection_path=str(directory / "rejected.json"),
            )
            cases.append(point)
    return dict(
        data,
        cases=cases,
        stage="predeclared_legacy_early_grid",
        policy="first_eligible_same_geometry_strong_runup_and_controls",
        historical_exposure=True,
        source_manifest_sha256=sha(source / "mirage-selected-v1.json"),
        source_reports_sha256={
            str(r): sha(source / f"mirage-{r}.json") for r in (60, 120)
        },
        prefix_manifest_sha256=sha(matrix),
        prefix_report_sha256=sha(report),
        grounded_prefix_observations=observed,
    )


def profile(points, rows, scheme):
    jump = next(
        p
        for p in points.values()
        if p["scheme"] == scheme and p["trial_mode"] == "jump"
    )
    base = jump["id"].removesuffix("jump")
    controls = {m: points[base + m] for m in ("no_jump", "walk")}
    return with_runup_contract(
        profile_evidence(
            jump,
            {r: rows[r][jump["id"]] for r in rows},
            {r: {m: rows[r][p["id"]] for m, p in controls.items()} for r in rows},
            controls,
        ),
        {str(r): runup_gate(jump, rows[r][jump["id"]], r) for r in rows},
    )


def verify(source, prior, directory, project) -> dict[str, Any]:
    grid = directory / "grid-v1.json"
    require(
        read(grid) == payload(source, prior, directory, project),
        "frozen early grid changed",
    )
    selected = directory / "selected-v1.json"
    data = selected_payload(directory, project)
    require(read(selected) == data, "early selection changed")
    legacy = None
    if data["cases"]:
        points, a = checked(selected, directory / "60.json", 60, project)
        _, b = checked(selected, directory / "120.json", 120, project)
        _, old = checked(grid, directory / "grid-60.json", 60, project)
        for point in points.values():
            require_unchanged_current(old[point["id"]], a[point["id"]])
        legacy = profile(points, {60: a, 120: b}, "legacy_16")
    original = source / "mirage-selected-v1.json"
    points, a = checked(original, source / "mirage-60.json", 60, project)
    _, b = checked(original, source / "mirage-120.json", 120, project)
    current = profile(points, {60: a, 120: b}, "current")
    modern = verify_prior(source, prior, project)["profiles"]["modern_cs"]
    modern_manifest = prior / "selected-v1.json"
    modern_point = next(
        p
        for p in read(modern_manifest)["cases"]
        if p["trial_mode"] == "jump" and p["scheme"] == "modern_cs"
    )
    require(
        all(
            geometry_matches(
                data["cases"][0] if data["cases"] else read(grid)["cases"][0], p
            )
            for p in [
                modern_point,
                next(p for p in points.values() if p["scheme"] == "current"),
            ]
        ),
        "cross-profile geometry differs",
    )
    return dict(
        schema=1,
        selected=data["selected_profiles"],
        observations=data["observations"],
        legacy=legacy,
        prior_current=current,
        prior_modern=modern,
        mirage_all_three_schemes_qualified=bool(
            legacy and all(p["jump_route_passed"] for p in (legacy, current, modern))
        ),
        grid_trials=9,
        selected_trials=len(data["cases"]) * 2,
        formal_release_ready=False,
        production_changed=False,
        historical_exposure=True,
        source_and_targets_unchanged=True,
        prior_selected_sha256=dict(current=sha(original), modern=sha(modern_manifest)),
        reports_sha256={
            p.name: sha(p)
            for p in directory.glob("*.json")
            if p.name in ("grid-60.json", "60.json", "120.json")
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=("freeze", "grid", "select", "replay", "verify")
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("prior", type=Path)
    parser.add_argument("directory", type=Path)
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
            payload(args.source, args.prior, args.directory, args.project),
        )
    elif args.mode in ("grid", "replay"):
        run(args.directory, args.project, args.godot, args.mode == "replay")
    elif args.mode == "select":
        freeze(
            args.directory / "selected-v1.json",
            selected_payload(args.directory, args.project),
        )
    else:
        result = verify(args.source, args.prior, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print(
            "LEGACY_EARLY_VERIFIED",
            result["selected"],
            result["mirage_all_three_schemes_qualified"],
        )
