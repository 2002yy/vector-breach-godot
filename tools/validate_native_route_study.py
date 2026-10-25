"""Validate frozen key/mouse execution; never promote a route study to release acceptance."""

import argparse
import math
from pathlib import Path

from build_native_route_study import SCHEMES, read, sha

KEYS = {"W", "A", "S", "D", "Space", "Ctrl", "Shift"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_trace(point, row, rate):
    require(row["feedback"] is False and row["input_released"] is True,
            "feedback or held-key contamination")
    trace = row["trace"]
    require(len(trace) == round(point["duration"] * rate), "incomplete trace")
    timeline = point["native_timeline"]
    held, index, requested, consumed = [], 0, [], []
    mouse_count = key_count = 0
    for tick, sample in enumerate(trace):
        time = tick / rate
        require(abs(sample["time"] - time) < 1e-6, "trace timing changed")
        keys, dx = held, 0.0
        while index < len(timeline) and timeline[index]["at"] <= time + 1e-6:
            event = timeline[index]
            keys = event["keys"]
            dx += event["mouse_dx"]
            index += 1
        require(set(keys) <= KEYS and len(keys) == len(set(keys)), "invalid digital keys")
        require(sample["native_command"] == {"keys": keys, "mouse_dx": dx},
                "executed command differs from frozen timeline")
        key_count += len(set(keys) ^ set(held))
        if "Space" in keys and "Space" not in held:
            requested.append(time)
        held = keys
        x, y = int("D" in keys) - int("A" in keys), int("S" in keys) - int("W" in keys)
        length = max(1, math.hypot(x, y))
        require(all(abs(a - b) < 1e-6 for a, b in zip(sample["input"]["direction"], (x / length, y / length))),
                "InputMap direction mismatch")
        require(sample["input"]["crouch"] == ("Ctrl" in keys) and
                sample["input"]["walk"] == ("Shift" in keys), "InputMap posture mismatch")
        if dx:
            mouse_count += 1
            mouse = sample["last_mouse"]
            require(abs(mouse["dx"] - dx) < 1e-6, "mouse delta rescaled by viewport")
            angle_error = mouse["after"] - mouse["before"] + dx * mouse["sensitivity"]
            require(abs(math.atan2(math.sin(angle_error), math.cos(angle_error))) < 2e-5,
                    "shipped mouse handler rotation mismatch")
        require(sample["mouse_events_seen"] == mouse_count and sample["key_events_seen"] == key_count,
                "native events not delivered exactly once")
        if sample["input"]["jump"]:
            consumed.append(time)
            require(requested and abs(sample["jump_requested_time"] - requested[-1]) < 1e-6,
                    "lost jump event provenance")
    require(len(consumed) == len(requested), "missing or repeated jump edge")
    delays = [b - a for a, b in zip(requested, consumed)]
    require(all(-1e-6 <= delay <= 1 / rate + 1e-6 for delay in delays), "jump delay exceeds one tick")
    require(row["target_reached"] == (row["reason"] == "reached"), "first landing verdict mismatch")
    if row["route_arrival_reached"]:
        require(row["start_valid"] and row["target_entry"].get("grounded_after") and
                row["goal_entry_support"], "arrival without frozen collision support")
    return delays


def validate(directory, project):
    study_path = directory / "native-study-v2.json"
    study, seed = read(study_path), read(directory / "discovery-seed.json")
    require(study["schema"] == 4 and study["formal_qualification"] is False,
            "study cannot become formal qualification")
    require(study["seed_sha256"] == sha(directory / "discovery-seed.json") and
            study["discovery_sha256"] == sha(directory / "discovery-final.json"), "provenance drift")
    require(study["identity"] == seed["identity"], "map identity changed")
    require(study["input_map_sha256"] == sha(project / "project.godot"), "InputMap changed")
    for path, expected in study["runtime_sha256"].items():
        require(sha(project / path.removeprefix("res://")) == expected, "runtime source drift")
    identity = study["identity"]
    level_data = read(project / f"data/levels/{study['level']}.json")
    require(sha(project / level_data["match_manifest"].removeprefix("res://")) == identity["layout_sha256"],
            "original navigation/layout identity drift")
    for path, key in ((identity["collision_path"], "collision_sha256"),
                      (identity["collision_path"] + ".import", "collision_import_sha256"),
                      (f"res://data/levels/{study['level']}.json", "level_sha256")):
        require(sha(project / path.removeprefix("res://")) == identity[key], "original map identity drift")
    parents = {p["id"]: p for p in seed["cases"]}
    cases = {p["id"]: p for p in study["cases"]}
    suffixes = ("route_no_jump", "route_walk", "run_up", "crouch_jump", "input_contract")
    expected = {f"{s}_{suffix}" for s in SCHEMES for suffix in suffixes}
    require(len(study["cases"]) == 15 and set(cases) == expected, "case coverage changed")
    for point in cases.values():
        original = parents[point["parent_case"]]
        require(all(point[k] == original[k] for k in
                    ("start", "yaw", "target_feet", "target_radius", "target_height_tolerance")),
                "geometry or goal tolerance changed")
        suffix = point["id"].removeprefix(point["scheme"] + "_")
        goal = ("supported_arrival" if suffix.startswith("route_") else
                "input_contract" if suffix == "input_contract" else "first_landing")
        require(point["goal_kind"] == goal, "goal semantics changed")
    summary = {"formal_release_ready": False, "input_kind": "synthetic InputMap keys/mouse; not OS/human",
               "study_sha256": sha(study_path), "results": [], "route_arrivals": 0,
               "first_landing_reached": 0, "jump_trials": 0, "input_contract_trials": 0}
    replays = {}
    for rate, name in ((60, "replay-final-60.json"), (120, "replay-final-120.json"), (60, "repeat-final-60.json")):
        report = read(directory / name)
        require(report["manifest_sha256"] == sha(study_path) and report["identity"] == study["identity"] and
                report["physics_hz"] == rate and report["runtime_sha256"] == study["runtime_sha256"] and
                report["input_map_sha256"] == study["input_map_sha256"] and report["feedback"] is False,
                "replay provenance mismatch")
        require(len(report["results"]) == 15 and {r["id"] for r in report["results"]} == expected,
                "replay coverage changed")
        for row in report["results"]:
            point = cases[row["id"]]
            require(row["scheme"] == point["scheme"] and row["mode"] == point["trial_mode"], "profile binding changed")
            delays = check_trace(point, row, rate)
            if row["target_reached"]:
                landing = row["landing"]
                target = point["target_feet"]
                require(row["start_valid"] and row["support"] and landing.get("grounded_after") and
                        math.hypot(landing["position"][0] - target[0], landing["position"][2] - target[2]) <= point["target_radius"] + 1e-6 and
                        abs(landing["position"][1] - 0.9 - target[1]) <= point["target_height_tolerance"] + 1e-6,
                        "unbacked first landing or control verdict")
            if row["route_arrival_reached"]:
                position = row["target_entry"]["position"]
                target = point["target_feet"]
                require(math.hypot(position[0] - target[0], position[2] - target[2]) <= point["target_radius"] + 1e-6 and
                        abs(position[1] - 0.9 - target[1]) <= point["target_height_tolerance"] + 1e-6,
                        "reported arrival outside original target")
                require(all(s["normal"][1] >= 0.7 and s["body"] for s in row["goal_entry_support"]),
                        "reported support is not walkable original collision")
            if name.startswith("repeat"):
                # Wall clock receipt fields are intentionally excluded from deterministic comparison.
                for a, b in zip(replays[row["id"]]["trace"], row["trace"]):
                    require({k: v for k, v in a.items() if k not in ("input_event_usec", "consumed_usec")} ==
                            {k: v for k, v in b.items() if k not in ("input_event_usec", "consumed_usec")},
                            "repeated physical/input trace differs")
                continue
            if rate == 60:
                replays[row["id"]] = row
            goal = point["goal_kind"]
            if goal == "supported_arrival":
                require(row["route_arrival_reached"] and not row["jumped"], "profile-specific no-jump route failed")
                summary["route_arrivals"] += 1
            elif goal == "first_landing":
                summary["jump_trials"] += 1
                summary["first_landing_reached"] += int(row["target_reached"])
            else:
                summary["input_contract_trials"] += 1
            summary["results"].append({"id": row["id"], "scheme": row["scheme"], "physics_hz": rate,
                "goal_kind": goal, "first_landing_or_control_reached": row["target_reached"],
                "supported_arrival": row["route_arrival_reached"], "arrival_time": row["target_entry"].get("time"),
                "jump_edge_delay_seconds": delays})
    summary["repeat_60_exact"] = True
    return summary


if __name__ == "__main__":
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = validate(args.directory, args.project)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("NATIVE_ROUTE_STUDY_OK 30 trials + 15 repeat; formal_release_ready=false")
