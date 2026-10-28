"""Recompute real-player flat-plane movement measurements; no subjective acceptance."""

import argparse
import json
import math
import statistics
import subprocess
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from validate_native_route_study import require

SCHEMES = ("current", "legacy_16", "modern_cs")
CASES = (
    "run",
    "walk",
    "crouch",
    "release",
    "reverse",
    "jump",
    "crouch_jump",
    "awp",
    "awp_scoped",
)
SCRIPT = "tools/authoring/measure_movement_feel.gd"
SOURCES = {
    SCRIPT,
    "scripts/player/PlayerController.gd",
    "scripts/player/ClassicMovementRules.gd",
    "scenes/player/Player.tscn",
    "scripts/combat/WeaponSystem.gd",
    "scripts/combat/WeaponCatalog.gd",
    "scripts/combat/WeaponProfile.gd",
    "scenes/combat/WeaponSystem.tscn",
    "data/weapons/rifle.tres",
    "data/weapons/pistol.tres",
    "project.godot",
}


def check_timeline(sample, name, rate):
    tick = sample["tick"]
    moving = tick > round(rate * 0.25) and name not in ("jump", "crouch_jump")
    direction = [0, -1] if moving else [0, 0]
    if name in ("release", "reverse") and tick > round(rate * 1.75):
        direction = [0, 1] if name == "reverse" else [0, 0]
    require(sample["direction"] == direction, "input timeline direction drift")
    require(
        sample["walking"] == (name == "walk" and tick > round(rate * 0.25)),
        "walk timeline drift",
    )
    require(
        sample["crouching"]
        == (name in ("crouch", "crouch_jump") and tick > round(rate * 0.25)),
        "crouch timeline drift",
    )
    require(
        sample["jump_requested"]
        == (name in ("jump", "crouch_jump") and tick == round(rate * 0.5) + 2),
        "jump request timeline drift",
    )


def speed(sample):
    return math.hypot(sample["velocity"][0], sample["velocity"][2])


def metrics(row, rate) -> dict[str, Any]:
    trace = row["trace"]
    name = row["case"]
    if name in ("jump", "crouch_jump"):
        jumps = [i for i, sample in enumerate(trace) if sample["jumped"]]
        require(len(jumps) == 1, "need exactly one real jump")
        start = jumps[0]
        require(
            trace[start]["jump_requested"] and trace[start]["grounded_before"],
            "unsupported jump",
        )
        lands = [i for i in range(start + 1, len(trace)) if trace[i]["grounded"]]
        require(bool(lands), "jump did not land")
        end = lands[0]
        return dict(
            height_m=max(s["foot_y"] for s in trace[start : end + 1])
            - trace[start]["foot_before"],
            airtime_s=(trace[end]["tick"] - trace[start]["tick"] + 1) / rate,
            launch_velocity_mps=trace[start]["velocity"][1],
            landing_foot_error_m=trace[end]["foot_y"] - trace[start]["foot_before"],
        )
    if name in ("release", "reverse"):
        trigger_tick = round(rate * 1.75) + 1
        before = next(s for s in trace if s["tick"] == trigger_tick - 1)
        stable = [
            s
            for s in trace
            if trigger_tick - round(rate * 0.5) <= s["tick"] < trigger_tick
        ]
        spread = max(speed(s) for s in stable) - min(speed(s) for s in stable)
        require(
            spread <= 0.001 and speed(before) > 0.01,
            "stop comparison lacks stable moving initial state",
        )
        after = [s for s in trace if s["tick"] >= trigger_tick]
        crossings = (
            [s for s in after if speed(s) <= 0.01]
            if name == "release"
            else [s for s in after if s["velocity"][2] >= 0]
        )
        require(bool(crossings), "no stop/reverse crossing")
        first = crossings[0]
        return dict(
            initial_speed_mps=speed(before),
            initial_speed_window_s=0.5,
            initial_speed_range_mps=spread,
            stop_or_crossing_s=(first["tick"] - trigger_tick + 1) / rate,
            displacement_to_crossing_m=math.dist(
                [before["position"][0], before["position"][2]],
                [first["position"][0], first["position"][2]],
            ),
            forward_sliding_m=max(
                before["position"][2] - s["position"][2]
                for s in after[: after.index(first) + 1]
            ),
            threshold_mps=0.01 if name == "release" else 0.0,
        )
    steady = [s for s in trace if s["tick"] > round(rate * 2.0)]
    require(bool(steady), "missing final half-second sample window")
    spread = max(speed(s) for s in steady) - min(speed(s) for s in steady)
    require(spread <= 0.001, "speed measurement has not reached steady state")
    return dict(
        measured_speed_mps=statistics.median(speed(s) for s in steady),
        reported_limit_mps=statistics.median(s["speed_limit"] for s in steady),
        final_speed_range_mps=spread,
        scoped=steady[0]["scoped"],
        fov=steady[0]["fov"],
    )


def validate(data, project=None) -> dict[str, Any]:
    require(
        data["schema"] == 1
        and data["kind"] == "synthetic_flat_real_player_measurement",
        "wrong report kind",
    )
    require(
        data["human_review"] == "pending" and data["formal_release_ready"] is False,
        "false human acceptance",
    )
    rate = data["physics_rate"]
    require(rate in (60, 120), "bad rate")
    require(
        data["input_mode"] == "synthetic_action_press_parent_physics",
        "input mode drift",
    )
    require(
        data["foot_definition"]
        == "collision_shape_global_y_minus_half_current_capsule_height",
        "foot definition drift",
    )
    require(
        data["airtime_definition"]
        == "end_of_first_grounded_sample_minus_start_of_jump_sample",
        "airtime definition drift",
    )
    require(
        data["fixture"] == dict(floor_size=[200, 1, 200], floor_top_y=0.0),
        "diagnostic geometry drift",
    )
    require(set(data["source_lock"]) == SOURCES, "incomplete source identity")
    if project is not None:
        for name, digest in data["source_lock"].items():
            path = (project / name).resolve()
            require(path.is_relative_to(project.resolve()), "source outside project")
            require(sha(path) == digest, "source drift")
    require(
        [(r["scheme"], r["case"]) for r in data["rows"]]
        == [(scheme, name) for scheme in SCHEMES for name in CASES],
        "missing/reordered measurement cases",
    )
    result = []
    for row in data["rows"]:
        trace = row["trace"]
        duration = 4.0 if row["case"] in ("release", "reverse") else 2.5
        require(len(trace) == round(rate * duration), "incomplete measurement timeline")
        for expected_tick, sample in enumerate(trace, 1):
            require(
                type(sample["tick"]) is int and sample["tick"] == expected_tick,
                "unordered measurement",
            )
            require(
                type(sample["delta"]) in (int, float)
                and abs(sample["delta"] - 1 / rate) <= 1e-9,
                "mixed measurement clock",
            )
            for key in ("position", "velocity"):
                require(
                    isinstance(sample[key], list)
                    and len(sample[key]) == 3
                    and all(
                        type(v) in (int, float) and math.isfinite(v)
                        for v in sample[key]
                    ),
                    "invalid vector",
                )
            for key in ("foot_y", "foot_before", "speed_limit", "fov"):
                require(
                    type(sample[key]) in (int, float) and math.isfinite(sample[key]),
                    "invalid scalar",
                )
            for key in (
                "jumped",
                "jump_requested",
                "grounded_before",
                "grounded",
                "crouching",
                "walking",
                "scoped",
            ):
                require(type(sample[key]) is bool, "invalid state flag")
            check_timeline(sample, row["case"], rate)
            scoped = row["case"] == "awp_scoped"
            require(
                sample["weapon_id"]
                == ("sniper" if row["case"].startswith("awp") else "rifle")
                and sample["scoped"] == scoped,
                "weapon/scope context mismatch",
            )
            require(
                abs(sample["fov"] - 28.0) < 1e-5 if scoped else sample["fov"] > 28,
                "scope/FOV mismatch",
            )
        result.append(
            dict(scheme=row["scheme"], case=row["case"], metrics=metrics(row, rate))
        )
    return dict(
        schema=1,
        physics_rate=rate,
        rows=result,
        human_review="pending",
        formal_release_ready=False,
        scope="synthetic_flat_plane_not_three_map_or_original_client_acceptance",
    )


def run(directory, project, godot, rate):
    require(not directory.exists(), "measurement directory exists")
    require(
        not directory.resolve().is_relative_to(project.resolve()),
        "use external evidence directory",
    )
    directory.mkdir(parents=True)
    scene = directory / "fixture.tscn"
    scene.write_text(
        '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://'
        + SCRIPT
        + '" id="1"]\n\n[node name="Measure" type="Node3D"]\nscript = ExtResource("1")\n',
        encoding="utf-8",
    )
    raw = directory / "raw.json"
    args = [
        str(godot),
        "--headless",
        "--path",
        str(project),
        "--single-threaded-scene",
        "--rendering-method",
        "gl_compatibility",
        "--fixed-fps",
        str(rate),
        str(scene),
        "--",
        str(raw),
        str(rate),
    ]
    with (directory / "native.log").open("w", encoding="utf-8") as log:
        subprocess.run(
            args,
            cwd=project,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=True,
            timeout=300,
        )
    report = validate(read(raw), project)
    report.update(raw_sha256=sha(raw))
    (directory / "metrics.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return report


def verify_directory(directory, project):
    raw = directory / "raw.json"
    expected = validate(read(raw), project)
    expected.update(raw_sha256=sha(raw))
    require(read(directory / "metrics.json") == expected, "derived metrics drift")
    return expected


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=("run", "verify"))
    p.add_argument("path", type=Path)
    p.add_argument("--project", type=Path, default=Path.cwd())
    p.add_argument("--godot", type=Path)
    p.add_argument("--rate", type=int, choices=(60, 120), default=60)
    a = p.parse_args()
    if a.mode == "run":
        require(a.godot is not None, "run requires godot")
        run(a.path, a.project, a.godot, a.rate)
    else:
        verify_directory(a.path, a.project)
    print("MOVEMENT_FEEL_VALIDATED", a.mode, a.path)
