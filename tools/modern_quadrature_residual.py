"""Separate candidate horizontal landing drift from vertical integration and snap timing."""

import argparse
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from modern_brake_window import floor_contacts
from modern_ground_quadrature import verify as verify_candidate
from native_jump_candidates import freeze
from validate_native_route_study import require


def end_state(row, rate, time):
    samples = [s for s in row["trace"] if abs(s["time"] + 1 / rate - time) < 1e-6]
    require(len(samples) == 1, "common physical endpoint missing")
    return samples[0]


def observe(rows) -> dict[str, Any]:
    jump_times = {
        r: [s["time"] for s in row["trace"] if s["jumped"]] for r, row in rows.items()
    }
    require(
        all(len(v) == 1 for v in jump_times.values())
        and abs(jump_times[60][0] - jump_times[120][0]) < 1e-6,
        "same single jump request required",
    )
    takeoff = jump_times[60][0]
    air = {
        r: [
            s
            for s in row["trace"]
            if takeoff <= s["time"] < row["landing"]["time"] and not s["grounded_after"]
        ]
        for r, row in rows.items()
    }
    speeds = {
        r: [math.hypot(s["velocity"][0], s["velocity"][2]) for s in trace]
        for r, trace in air.items()
    }
    require(all(v for v in speeds.values()), "missing airborne samples")
    reference = air[60][0]["velocity"]
    require(
        all(
            math.hypot(
                s["velocity"][0] - reference[0],
                s["velocity"][2] - reference[2],
            )
            < 1e-4
            for trace in air.values()
            for s in trace
        ),
        "constant horizontal velocity required for landing-time attribution",
    )
    a, b = (rows[r]["landing"] for r in (60, 120))
    landing_time_delta = abs((a["time"] + 1 / 60) - (b["time"] + 1 / 120))
    horizontal = math.hypot(
        a["position"][0] - b["position"][0], a["position"][2] - b["position"][2]
    )
    mean_speed = sum(sum(v) / len(v) for v in speeds.values()) / 2
    common = {}
    for offset in (1 / 60, 0.1, 0.3):
        time = takeoff + offset
        states = {r: end_state(row, r, time) for r, row in rows.items()}
        common[str(offset)] = dict(
            end_seconds=time,
            y_delta_m=states[60]["position"][1] - states[120]["position"][1],
            vertical_velocity_delta_mps=states[60]["velocity"][1]
            - states[120]["velocity"][1],
            horizontal_delta_m=math.hypot(
                states[60]["position"][0] - states[120]["position"][0],
                states[60]["position"][2] - states[120]["position"][2],
            ),
        )
    snaps = {}
    contacts = {r: floor_contacts(row) for r, row in rows.items()}
    for rate, row in rows.items():
        snaps[str(rate)] = [
            s["time"]
            for s in row["trace"]
            if takeoff <= s["time"] <= row["landing"]["time"]
            and any(
                stage["stage"] == "snap"
                and math.dist(stage["before"]["position"], stage["after"]["position"])
                > 1e-6
                for stage in s["stages"]
            )
        ]
    return dict(
        common_end_states=common,
        horizontal_speed_ranges={
            str(r): dict(min_mps=min(v), max_mps=max(v)) for r, v in speeds.items()
        },
        same_air_speed=all(max(v) - min(v) < 1e-4 for v in speeds.values())
        and abs(speeds[60][0] - speeds[120][0]) < 1e-4,
        first_landing_end_seconds={
            str(r): rows[r]["landing"]["time"] + 1 / r for r in (60, 120)
        },
        first_landing_horizontal_delta_m=horizontal,
        first_landing_end_time_delta_seconds=landing_time_delta,
        same_speed_time_contribution_m=mean_speed * landing_time_delta,
        horizontal_residual_m=horizontal - mean_speed * landing_time_delta,
        apex_y_delta_m=max(s["position"][1] for s in rows[60]["trace"])
        - max(s["position"][1] for s in rows[120]["trace"]),
        custom_snap_tick_start_seconds=snaps,
        landing_same_collision_groups={p["body"] for p in contacts[60]}
        == {p["body"] for p in contacts[120]},
        landing_height_delta_m=abs(
            sum(p["height"] for p in contacts[60]) / len(contacts[60])
            - sum(p["height"] for p in contacts[120]) / len(contacts[120])
        ),
        precision_equivalence_accepted=False,
    )


def summarize(candidate_root, source_root, project) -> dict[str, Any]:
    results, bindings = {}, {}
    for name in ("inferno", "dust2", "mirage"):
        folder = candidate_root / name
        verify_candidate(source_root / f"{name}-queued-v1.json", folder, project)
        rows = {
            r: next(
                p
                for p in read(folder / f"{r}.json")["results"]
                if p["id"] == "candidate__jump"
            )
            for r in (60, 120)
        }
        results[name] = observe(rows)
        bindings[name] = {str(r): sha(folder / f"{r}.json") for r in (60, 120)}
    return dict(
        schema=1,
        results=results,
        source_reports_sha256=bindings,
        formal_release_ready=False,
        production_changed=False,
        scope="R25_fixed_crouch_candidates_residual_attribution_not_vertical_repair",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate_root", type=Path)
    parser.add_argument("source_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    result = summarize(args.candidate_root, args.source_root, args.project)
    freeze(args.output, result)
    print(
        "QUADRATURE_RESIDUAL_VERIFIED",
        [(n, v["horizontal_residual_m"]) for n, v in result["results"].items()],
    )
