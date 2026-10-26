"""Freeze bounded jump inputs, select using 60 Hz only, verify untouched 120 Hz."""

import argparse
import copy
import json
import math
from pathlib import Path

from build_native_route_study import SCHEMES, read, sha
from validate_native_route_study import check_trace, require

GEOMETRY = (
    "start",
    "yaw",
    "target_feet",
    "target_radius",
    "target_height_tolerance",
    "duration",
)
RUNTIME = (
    "scripts/player/PlayerController.gd",
    "scripts/player/ClassicMovementRules.gd",
    "tools/authoring/NativeRoutePlayer.gd",
)
VARIANTS = (
    ("precrouch_010", "pre", 0.1),
    ("precrouch_025", "pre", 0.25),
    ("precrouch_040", "pre", 0.4),
    ("precrouch_055", "pre", 0.55),
    ("aircrouch_010", "air", 0.1),
    ("aircrouch_025", "air", 0.25),
)


def freeze(path, payload, protected=()):
    require(
        path.resolve() not in {p.resolve() for p in protected},
        "cannot overwrite source evidence",
    )
    data = (json.dumps(payload, indent=2) + "\n").encode()
    require(
        not path.exists() or path.read_bytes() == data,
        "frozen file differs; use a new revision",
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def digital(original):
    held = dict(direction=[0, 0], crouch=False, jump=False, walk=False)
    result = []
    for event in original:
        held.update({k: v for k, v in event.items() if k in held})
        require(
            held["direction"] in ([0, -1], [0, 0]),
            "baseline direction not forward/stop",
        )
        keys = ["W"] if held["direction"] == [0, -1] else []
        keys += [
            name
            for name, flag in (("Ctrl", "crouch"), ("Shift", "walk"), ("Space", "jump"))
            if held[flag]
        ]
        result.append(dict(at=event["at"], keys=keys, mouse_dx=0.0))
    return result


def variant_input(kind, at):
    events = [
        (0.0, ["W", "Ctrl"] if kind == "pre" else ["W"]),
        (at, ["W", "Space", "Ctrl"] if kind == "pre" else ["W", "Space"]),
    ]
    if kind == "air":
        events.append((at + 2 / 60, ["W", "Space", "Ctrl"]))
    events += [(at + 0.1, ["W", "Ctrl"]), (1.5, ["Ctrl"])]
    return [dict(at=time, keys=keys, mouse_dx=0.0) for time, keys in events]


def backstep_input(back, run):
    jump = back + run
    return [
        dict(at=time, keys=keys, mouse_dx=0.0)
        for time, keys in (
            (0, ["S"]),
            (back, ["W"]),
            (jump, ["W", "Space"]),
            (jump + 2 / 60, ["W", "Space", "Ctrl"]),
            (jump + 0.1, ["W", "Ctrl"]),
            (1.5, ["Ctrl"]),
        )
    ]


def grid_payload(parent, map_name, project, revision="v1"):
    source = read(parent)
    cases = []
    for original in source["cases"]:
        variants = (
            [(name, variant_input(kind, at)) for name, kind, at in VARIANTS]
            if map_name == "mirage"
            else [("original", digital(original["timeline"]))]
        )
        if revision == "v2":
            require(
                map_name == "mirage",
                "v2 is the explicit Mirage wall-start investigation",
            )
            variants = [
                ("back150_run200", backstep_input(0.15, 0.2)),
                ("back250_run300", backstep_input(0.25, 0.3)),
            ]
        for scheme in SCHEMES:
            for variant, timeline in variants:
                for mode in ("jump", "no_jump"):
                    point = copy.deepcopy(original)
                    point.update(
                        id=f"{scheme}__{original['id']}__{variant}__{mode}",
                        parent_case=original["id"],
                        scheme=scheme,
                        variant=variant,
                        trial_mode=mode,
                        goal_kind="first_landing"
                        if mode == "jump"
                        else "supported_arrival",
                        native_timeline=copy.deepcopy(timeline),
                    )
                    if mode == "no_jump":
                        for event in point["native_timeline"]:
                            event["keys"] = [k for k in event["keys"] if k != "Space"]
                    cases.append(point)
    payload = dict(
        schema=4,
        stage="predeclared_grid",
        formal_qualification=False,
        map_name=map_name,
        level=source["level"],
        identity=source["identity"],
        parent_sha256=sha(parent),
        input_map_sha256=sha(project / "project.godot"),
        runtime_sha256={"res://" + p: sha(project / p) for p in RUNTIME},
        cases=cases,
    )
    if revision == "v2":
        payload["revision"] = "v2"
    return payload


def inside(point, sample):
    position, goal = sample["position"], point["target_feet"]
    return (
        math.hypot(position[0] - goal[0], position[2] - goal[2])
        <= point["target_radius"]
        and abs(position[1] - 0.9 - goal[1]) <= point["target_height_tolerance"]
    )


def outcomes(point, row):
    """Derive first landing/arrival from the actual trace; do not trust score booleans."""
    jumped = airborne = False
    landing = entry = None
    for sample in row["trace"]:
        jumped = jumped or sample["jumped"]
        airborne = airborne or (jumped and not sample["grounded_after"])
        if airborne and sample["grounded_after"] and landing is None:
            landing = sample
        if entry is None and sample["grounded_after"] and inside(point, sample):
            entry = sample
    support = row["goal_entry_support"]
    require(
        all(s["normal"][1] >= 0.7 and s["body"] for s in support),
        "invalid original support",
    )
    arrival = bool(row["start_valid"] and entry and support)
    require(row["target_entry"] == (entry or {}), "fabricated goal-entry sample")
    require(row["route_arrival_reached"] == arrival, "fabricated arrival verdict")
    control_mode = point["trial_mode"] in ("no_jump", "walk")
    if control_mode:
        require(not jumped, "no-jump control jumped")
        landing = entry
    require(
        row["landing"] == (landing or {}),
        "first-landing sample replaced by later arrival",
    )
    reached = bool(
        row["start_valid"]
        and landing
        and inside(point, landing)
        and row["support"]
        and (not jumped if control_mode else jumped and airborne)
    )
    require(row["target_reached"] == reached, "fabricated first-landing verdict")
    return dict(
        first_landing=reached,
        supported_arrival=arrival,
        landing_time=landing["time"] if landing else None,
        arrival_time=entry["time"] if entry else None,
    )


def check_report(manifest_path, report_path, rate, project):
    manifest, report = read(manifest_path), read(report_path)
    require(
        manifest["schema"] == 4 and manifest["formal_qualification"] is False,
        "formal gate forbidden",
    )
    require(
        report["manifest_sha256"] == sha(manifest_path)
        and report["identity"] == manifest["identity"]
        and report["runtime_sha256"] == manifest["runtime_sha256"]
        and report["input_map_sha256"] == manifest["input_map_sha256"]
        and report["physics_hz"] == rate
        and report["feedback"] is False,
        "report identity mismatch",
    )
    require(
        sha(project / "project.godot") == manifest["input_map_sha256"], "InputMap drift"
    )
    for path, expected in manifest["runtime_sha256"].items():
        require(sha(project / path.removeprefix("res://")) == expected, "runtime drift")
    identity = manifest["identity"]
    for path, field in (
        (identity["collision_path"], "collision_sha256"),
        (identity["collision_path"] + ".import", "collision_import_sha256"),
        (f"res://data/levels/{manifest['level']}.json", "level_sha256"),
    ):
        require(
            sha(project / path.removeprefix("res://")) == identity[field], "map drift"
        )
    level = read(project / f"data/levels/{manifest['level']}.json")
    require(
        sha(
            project
            / level.get(
                "match_manifest", "res://data/levels/match-local/dustline.json"
            ).removeprefix("res://")
        )
        == identity["layout_sha256"],
        "layout drift",
    )
    cases = {p["id"]: p for p in manifest["cases"]}
    rows = {r["id"]: r for r in report["results"]}
    require(
        len(cases) == len(manifest["cases"])
        and len(rows) == len(report["results"])
        and cases.keys() == rows.keys(),
        "missing/duplicate trials",
    )
    results = {}
    for name, point in cases.items():
        row = rows[name]
        require(
            (row["scheme"], row["mode"]) == (point["scheme"], point["trial_mode"]),
            "profile/mode mismatch",
        )
        delays = check_trace(point, row, rate)
        results[name] = dict(outcomes(point, row), jump_delays=delays)
    return results


def choose(grid, results):
    groups = {}
    for point in grid["cases"]:
        key = (point["parent_case"], point["scheme"])
        groups.setdefault(key, [])
        if point["trial_mode"] == "jump":
            groups[key].append(point)
    selected, rejected = [], []
    by_id = {p["id"]: p for p in grid["cases"]}
    for (parent, scheme), candidates in groups.items():
        for point in candidates:
            control = by_id[point["id"].removesuffix("jump") + "no_jump"]
            if (
                results[point["id"]]["first_landing"]
                and not results[control["id"]]["supported_arrival"]
            ):
                selected.extend((point, control))
                break
        else:
            rejected.append(
                dict(
                    parent_case=parent,
                    scheme=scheme,
                    reason="no_candidate_with_first_landing_and_negative_paired_control",
                )
            )
    return selected, rejected


def select(grid_path, report_path, output, project):
    grid = read(grid_path)
    require(grid["stage"] == "predeclared_grid", "selection requires predeclared grid")
    results = check_report(grid_path, report_path, 60, project)
    cases, rejected = choose(grid, results)
    selected = dict(
        grid,
        stage="selected_using_60_only",
        grid_sha256=sha(grid_path),
        selection_report_sha256=sha(report_path),
        cases=cases,
        unselected=rejected,
    )
    freeze(output, selected, (grid_path, report_path))
    return selected


def verify(directory, parents, project):
    summary = dict(
        formal_release_ready=False,
        selection_hz=60,
        holdout_hz=120,
        input_kind="synthetic InputMap keys; not OS/human",
        results=[],
        unselected=[],
        grid_trials=0,
        replay_trials=0,
        first_landing_passes=0,
        negative_controls=0,
        exploration=[],
    )
    lock = read(directory / "selection-lock.json")
    require(
        lock["selection_uses_60_only"] is True, "missing pre-holdout selection lock"
    )
    for name in ("dust2", "mirage", "inferno"):
        revision = "v2" if name == "mirage" else "v1"
        parent, grid_path = (
            parents / f"{name}-manifest.json",
            directory / f"{name}-grid-{revision}.json",
        )
        grid = read(grid_path)
        require(
            grid == grid_payload(parent, name, project, revision),
            "predeclared grid changed",
        )
        discovery = directory / f"{name}-grid-{revision}-60.json"
        grid_results = check_report(grid_path, discovery, 60, project)
        expected, rejected = choose(grid, grid_results)
        selected_path = directory / f"{name}-selected-{revision}.json"
        selected = read(selected_path)
        require(
            lock["selected_sha256"][name] == sha(selected_path),
            "selected inputs changed after lock",
        )
        require(
            selected
            == dict(
                grid,
                stage="selected_using_60_only",
                grid_sha256=sha(grid_path),
                selection_report_sha256=sha(discovery),
                cases=expected,
                unselected=rejected,
            ),
            "selected inputs were altered or cherry-picked",
        )
        summary["grid_trials"] += len(grid_results)
        summary["unselected"] += [dict(map=name, **r) for r in rejected]
        for point in grid["cases"]:
            if point["trial_mode"] == "jump":
                summary["exploration"].append(
                    dict(
                        map=name,
                        revision=revision,
                        scheme=point["scheme"],
                        variant=point["variant"],
                        case=point["parent_case"],
                        **grid_results[point["id"]],
                    )
                )
        for rate in (60, 120):
            results = check_report(
                selected_path, directory / f"{name}-selected-{rate}.json", rate, project
            )
            for point in selected["cases"]:
                result = results[point["id"]]
                if point["trial_mode"] == "jump":
                    require(
                        result["first_landing"],
                        "selected candidate failed untouched-frequency verification",
                    )
                    summary["first_landing_passes"] += 1
                else:
                    require(
                        not result["supported_arrival"],
                        "paired no-jump control reached target",
                    )
                    summary["negative_controls"] += 1
                summary["results"].append(
                    dict(
                        map=name,
                        case=point["parent_case"],
                        scheme=point["scheme"],
                        variant=point["variant"],
                        mode=point["trial_mode"],
                        physics_hz=rate,
                        **result,
                    )
                )
                summary["replay_trials"] += 1
    # Retain the unsuccessful first Mirage matrix; selected successes cannot erase it.
    first_path = directory / "mirage-grid-v1.json"
    require(
        read(first_path)
        == grid_payload(parents / "mirage-manifest.json", "mirage", project),
        "initial failed grid was replaced",
    )
    first_results = check_report(
        first_path, directory / "mirage-grid-60.json", 60, project
    )
    summary["grid_trials"] += len(first_results)
    for point in read(first_path)["cases"]:
        if point["trial_mode"] == "jump":
            summary["exploration"].append(
                dict(
                    map="mirage",
                    revision="v1",
                    scheme=point["scheme"],
                    variant=point["variant"],
                    case=point["parent_case"],
                    **first_results[point["id"]],
                )
            )
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("grid", "select", "verify"))
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument(
        "--map", dest="map_name", choices=("dust2", "mirage", "inferno")
    )
    parser.add_argument("--revision", choices=("v1", "v2"), default="v1")
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode == "grid":
        parent, output = args.paths
        freeze(
            output,
            grid_payload(parent, args.map_name, args.project, args.revision),
            (parent,),
        )
        print("NATIVE_JUMP_GRID_FROZEN", args.map_name, sha(output))
    elif args.mode == "select":
        payload = select(*args.paths, args.project)
        print(
            "NATIVE_JUMP_SELECTED_60_ONLY",
            len(payload["cases"]),
            "unselected",
            len(payload["unselected"]),
        )
    else:
        directory, parents, output = args.paths
        payload = verify(directory, parents, args.project)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(
            "NATIVE_JUMP_VERIFY_OK",
            payload["replay_trials"],
            "trials; formal_release_ready=false",
        )
