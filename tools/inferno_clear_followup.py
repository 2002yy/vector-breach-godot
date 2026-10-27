"""R31 bounded follow-up justified by preserved low/overshoot contact evidence."""

import argparse
from pathlib import Path
from typing import Any
from inferno_clear_inputs import payload as first_payload, selected_payload, verify
from native_jump_candidates import freeze
from runup_action_completion import control_timeline
from runup_profile_inputs import run


def timeline(scheme, variant) -> list[dict[str, Any]]:
    if scheme == "current":
        back, forward, air = 0.20, 0.20, (0.15, 0.225)[variant]
        jump = back + forward
        pairs = [
            (0.0, ["S"]),
            (back, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 1 / 60, ["W"]),
            (jump + air, ["S"]),
            (jump + air + 1 / 30, []),
            (1.5, []),
        ]
    else:
        back, forward = 0.20, (0.30, 0.35)[variant]
        jump = back + forward
        pairs = [
            (0.0, ["S"]),
            (back, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 1 / 60, ["W"]),
            (jump + 0.30, []),
            (1.5, []),
        ]
    return [dict(at=t, keys=k, mouse_dx=0.0) for t, k in pairs]


def payload(source, directory, project):
    data = first_payload(source, directory, project)
    cases = [
        p
        for p in data["cases"]
        if p["parent_case"] == "rise_03"
        and p["scheme"] in ("current", "modern_cs")
        and p["variant"] < 2
    ]
    for p in cases:
        p["native_timeline"] = control_timeline(
            timeline(p["scheme"], p["variant"]), p["trial_mode"]
        )
    return dict(
        data,
        cases=cases,
        stage="inferno_clear_inputs_followup_v2",
        variants=dict(
            current=[[0.20, 0.20, 0.15, 1 / 30], [0.20, 0.20, 0.225, 1 / 30]],
            modern_cs=[[0.20, 0.30, 0.30, 0], [0.20, 0.35, 0.30, 0]],
        ),
        hypothesis="Current overshot onto lower clip surface; Modern reverse reduced forward speed without side collision",
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
        result = verify(args.source, args.directory, args.project, builder=payload)
        freeze(args.directory / "validated-summary.json", result)
        print("INFERNO_FOLLOWUP_VERIFIED", result["selected"], list(result["profiles"]))
