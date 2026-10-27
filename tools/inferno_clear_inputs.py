"""Bounded original Inferno clear-corridor inputs; no production changes."""

import argparse
import copy
from pathlib import Path
from typing import Any
from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from movement_evidence_bank import LEVELS, profile_evidence
from native_jump_candidates import freeze, outcomes
from runup_action_completion import control_timeline, runup_gate, with_runup_contract
from runup_profile_inputs import run
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

POINTS = ("rise_03", "rise_04")
VARIANTS = ((0.20, 0.20, 0.30), (0.25, 0.20, 0.35), (0.30, 0.20, 0.40))
MODES = ("jump", "no_jump", "walk")
ARTIFACTS = (
    "grid-v1.json",
    "grid-60.json",
    "selected-v1.json",
    "60.json",
    "120.json",
    "all-profile-selection-empty.json",
)


def artifact_hashes(directory):
    return {
        name: sha(directory / name)
        for name in ARTIFACTS
        if (directory / name).is_file()
    }


def timeline(index) -> list[dict[str, Any]]:
    back, forward, air = VARIANTS[index]
    jump = back + forward
    return [
        dict(at=t, keys=k, mouse_dx=0.0)
        for t, k in (
            (0.0, ["S"]),
            (back, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 1 / 60, ["W"]),
            (jump + air, ["S"]),
            (jump + air + 1 / 30, []),
            (1.5, []),
        )
    ]


def payload(source, directory, project):
    manifest = source / "inferno-grid-v1.json"
    data = read(manifest)
    require(
        data["level"] == LEVELS["inferno"] and data["schema"] == 4, "source map differs"
    )
    checked(manifest, source / "inferno-grid-60.json", 60, project)
    cases = []
    for key in POINTS:
        parent = next(
            p
            for p in data["cases"]
            if p["parent_case"] == key and p["trial_mode"] == "jump"
        )
        for scheme in SCHEMES:
            for variant in range(len(VARIANTS)):
                for mode in MODES:
                    p = copy.deepcopy(parent)
                    p.update(
                        id=f"{key}__{scheme}__v{variant}__{mode}",
                        scheme=scheme,
                        variant=variant,
                        trial_mode=mode,
                        native_timeline=control_timeline(timeline(variant), mode),
                        rejection_path=str(directory / "rejected.json"),
                    )
                    cases.append(p)
    return dict(
        data,
        cases=cases,
        stage="inferno_clear_inputs_grid",
        source_manifest_sha256=sha(manifest),
        source_report_sha256=sha(source / "inferno-grid-60.json"),
        selection_policy="same_point_all_profiles_first_strong_60Hz_then_dual_rate",
        historical_exposure=True,
        variants=[list(v) for v in VARIANTS],
    )


def choose(data, rows):
    points = {p["id"]: p for p in data["cases"]}
    candidates = {key: {scheme: None for scheme in SCHEMES} for key in POINTS}
    observations = []
    for p in data["cases"]:
        if p["trial_mode"] != "jump":
            continue
        row = rows[p["id"]]
        prefix = p["id"].removesuffix("jump")
        controls = {
            m: outcomes(points[prefix + m], rows[prefix + m])["supported_arrival"]
            for m in MODES[1:]
        }
        action = runup_gate(p, row, 60)
        landing = outcomes(p, row)["first_landing"]
        corridor = row["ingress_corridor"]["status"]
        eligible = bool(
            action["passed"]
            and landing
            and corridor == "geometric_corridor_found"
            and not any(controls.values())
        )
        observations.append(
            dict(
                point=p["parent_case"],
                scheme=p["scheme"],
                variant=p["variant"],
                runup=action,
                first_landing=landing,
                corridor=corridor,
                controls=controls,
                eligible=eligible,
                landing_distance=row["landing_distance"],
                landing_height_error=row["landing_height_error"],
            )
        )
        if eligible and candidates[p["parent_case"]][p["scheme"]] is None:
            candidates[p["parent_case"]][p["scheme"]] = p["variant"]
    selected = next(
        (k for k in POINTS if all(v is not None for v in candidates[k].values())), None
    )
    if selected is None:
        selected = next(
            (k for k in POINTS if any(v is not None for v in candidates[k].values())),
            None,
        )
    return selected, candidates, observations


def selected_payload(directory, project):
    matrix = directory / "grid-v1.json"
    data = read(matrix)
    _, rows = checked(matrix, directory / "grid-60.json", 60, project)
    selected, candidates, observations = choose(data, rows)
    cases = [
        p
        for p in data["cases"]
        if selected is not None
        and p["parent_case"] == selected
        and p["variant"] == candidates[selected][p["scheme"]]
    ]
    return dict(
        data,
        cases=cases,
        selected=selected,
        candidates=candidates,
        observations=observations,
        stage="inferno_clear_inputs_selected",
        grid_sha256=sha(matrix),
        grid_report_sha256=sha(directory / "grid-60.json"),
    )


def verify(source, directory, project, builder=payload):
    require(
        read(directory / "grid-v1.json") == builder(source, directory, project),
        "frozen grid changed",
    )
    data = selected_payload(directory, project)
    require(read(directory / "selected-v1.json") == data, "selection changed")
    profiles = {}
    if data["cases"]:
        points, a = checked(
            directory / "selected-v1.json", directory / "60.json", 60, project
        )
        _, b = checked(
            directory / "selected-v1.json", directory / "120.json", 120, project
        )
        _, old = checked(
            directory / "grid-v1.json", directory / "grid-60.json", 60, project
        )
        rows = {60: a, 120: b}
        for p in points.values():
            require_unchanged_current(old[p["id"]], a[p["id"]])
        for scheme in (
            s for s in SCHEMES if any(p["scheme"] == s for p in points.values())
        ):
            jump = next(
                p
                for p in points.values()
                if p["scheme"] == scheme and p["trial_mode"] == "jump"
            )
            controls = {
                m: points[jump["id"].removesuffix("jump") + m] for m in MODES[1:]
            }
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
    complete = bool(
        len(profiles) == 3
        and all(
            p["status"] == "qualified_jump" and p["category_action_passed"]
            for p in profiles.values()
        )
    )
    return dict(
        schema=1,
        selected=data["selected"],
        candidates=data["candidates"],
        observations=data["observations"],
        profiles=profiles,
        category_closed=complete,
        route_categories=9 if complete else 8,
        action_categories=15,
        grid_trials=len(read(directory / "grid-v1.json")["cases"]),
        selected_trials=len(data["cases"]) * 2,
        production_changed=False,
        original_failures_preserved=True,
        historical_exposure=True,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        artifacts_sha256=artifact_hashes(directory),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=("freeze", "grid", "select", "replay", "verify")
    )
    parser.add_argument("source", type=Path)
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
            payload(args.source, args.directory, args.project),
        )
    elif args.mode in ("grid", "replay"):
        run(args.directory, args.project, args.godot, args.mode == "replay")
    elif args.mode == "select":
        freeze(
            args.directory / "selected-v1.json",
            selected_payload(args.directory, args.project),
        )
    else:
        result = verify(args.source, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print(
            "INFERNO_CLEAR_INPUTS_VERIFIED",
            result["selected"],
            result["category_closed"],
        )
