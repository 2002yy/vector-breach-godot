"""Final finite Current brake test on unchanged Inferno rise_03."""

import argparse
from pathlib import Path
from typing import Any
from inferno_clear_inputs import payload as original_payload, selected_payload, verify
from inferno_clear_followup import payload as second_payload
from native_jump_candidates import freeze
from runup_action_completion import control_timeline
from runup_profile_inputs import run
from build_native_route_study import read, sha
from validate_native_route_study import require

BRAKES = (0.15, 0.25, 0.35)


def timeline(variant) -> list[dict[str, Any]]:
    brake = BRAKES[variant]
    return [
        dict(at=t, keys=k, mouse_dx=0.0)
        for t, k in (
            (0.0, ["S"]),
            (0.20, ["W"]),
            (0.40, ["W", "Space"]),
            (0.40 + 1 / 60, ["W"]),
            (0.55, ["S"]),
            (0.55 + brake, []),
            (1.5, []),
        )
    ]


def payload(source, directory, project):
    data = original_payload(source, directory, project)
    cases = [
        p
        for p in data["cases"]
        if p["parent_case"] == "rise_03" and p["scheme"] == "current"
    ]
    for p in cases:
        p["native_timeline"] = control_timeline(timeline(p["variant"]), p["trial_mode"])
    return dict(
        data,
        cases=cases,
        stage="inferno_current_long_brake_v3",
        variants=list(BRAKES),
        hypothesis="33ms reverse retained high air coasting speed; test longer reverse without changing original target",
    )


def composite(source, directory, project):
    first = directory.parent
    second = first / "v2"
    reports = [
        verify(source, first, project),
        verify(source, second, project, builder=second_payload),
        verify(source, directory, project, builder=payload),
    ]
    manifests = [read(p / "selected-v1.json") for p in (first, second, directory)]
    reference = manifests[0]
    fields = (
        "start",
        "yaw",
        "target_feet",
        "target_radius",
        "target_height_tolerance",
        "geometry",
        "source_nav_node",
        "kind",
    )
    original = next(p for p in reference["cases"] if p["trial_mode"] == "jump")
    profiles = {}
    for manifest, report in zip(manifests, reports):
        require(
            manifest["selected"] in (None, "rise_03")
            and (manifest["selected"] is not None or not manifest["cases"]),
            "composite must use original same point",
        )
        for field in ("identity", "level", "runtime_sha256", "input_map_sha256"):
            require(
                manifest[field] == reference[field], "composite source binding differs"
            )
        for point in manifest["cases"]:
            require(
                all(point[field] == original[field] for field in fields),
                "composite frozen geometry differs",
            )
            require(
                point["probe_sha256"] == original["probe_sha256"],
                "composite probe differs",
            )
        for scheme, profile in report["profiles"].items():
            require(scheme not in profiles, "duplicate composite profile")
            profiles[scheme] = profile
    complete = bool(
        set(profiles) == {"current", "legacy_16", "modern_cs"}
        and all(
            p["status"] == "qualified_jump" and p["category_action_passed"]
            for p in profiles.values()
        )
    )
    return dict(
        schema=1,
        selected_point="rise_03",
        profiles=profiles,
        category_closed=complete,
        action_categories=15,
        route_categories=9 if complete else 8,
        total_valid_replays=78 + 9 + reports[-1]["selected_trials"],
        production_changed=False,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        source_summaries_sha256={
            str(p): sha(p / "validated-summary.json")
            for p in (first, second, directory)
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=("freeze", "grid", "select", "replay", "verify", "composite")
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
    elif args.mode == "composite":
        result = composite(args.source, args.directory, args.project)
        freeze(args.directory / "composite-summary.json", result)
        print("INFERNO_COMPOSITE_VERIFIED", result["category_closed"])
    else:
        result = verify(args.source, args.directory, args.project, builder=payload)
        freeze(args.directory / "validated-summary.json", result)
        print("CURRENT_BRAKE_VERIFIED", result["selected"], list(result["profiles"]))
