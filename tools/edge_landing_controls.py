"""Frozen post-takeoff input controls; keep original edge goals and old failures."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from edge_lip_window import MAPS, REFERENCE_HZ
from movement_dimension_gates import action_gate
from native_jump_candidates import freeze, outcomes
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

VARIANTS = ("baseline", "release", "reverse_010", "reverse_030", "reverse_hold")


def timeline(original, variant):
    require(variant in VARIANTS, "unknown landing input")
    if variant == "baseline":
        return copy.deepcopy(original["native_timeline"])
    at = original["request_time"]
    switch = at + 1 / REFERENCE_HZ
    events: list[dict[str, Any]] = [
        dict(at=0, keys=["W"], mouse_dx=0),
        dict(at=at, keys=["W", "Space"], mouse_dx=0),
        dict(at=switch, keys=[] if variant == "release" else ["S"], mouse_dx=0),
    ]
    if variant in ("reverse_010", "reverse_030"):
        events.append(
            dict(
                at=switch + (0.1 if variant == "reverse_010" else 0.3),
                keys=[],
                mouse_dx=0,
            )
        )
    events.append(dict(at=1.5, keys=[], mouse_dx=0))
    return events


def payload(name, source, project, rejection):
    path, report = Path(source["manifest"]), Path(source["report60"])
    points, rows = checked(path, report, 60, project)
    require(read(path)["stage"] == "frozen_edge_lip_window", "wrong edge parent")
    cases = []
    for scheme in SCHEMES:
        original = points[f"lip__{scheme}__+0"]
        require(
            action_gate(original, rows[original["id"]], 60)["passed"],
            "baseline must take off",
        )
        for probe, digest in original["probe_sha256"].items():
            require(
                sha(project / probe.removeprefix("res://")) == digest,
                "author probe drift",
            )
        for variant in VARIANTS:
            point = copy.deepcopy(original)
            point.update(
                id=f"{scheme}__{variant}",
                parent_case="edge_landing_control",
                source_case=original["id"],
                air_control_variant=variant,
                switch_time=original["request_time"] + 1 / REFERENCE_HZ,
                rejection_path=str(rejection),
                native_timeline=timeline(original, variant),
            )
            cases.append(point)
    return dict(
        read(path),
        cases=cases,
        stage="frozen_post_takeoff_controls",
        map_label=name,
        variants=list(VARIANTS),
        input_policy="same_through_takeoff_switch_after_one_reference_frame_no_selection",
        source_manifest_sha256=sha(path),
        source_report60_sha256=sha(report),
        source_report120_sha256=sha(Path(source["report120"])),
        formal_qualification=False,
    )


def prefix_before_switch(point, row, baseline):
    prefix = [s for s in row["trace"] if s["time"] < point["switch_time"] - 1e-6]
    control = [s for s in baseline["trace"] if s["time"] < point["switch_time"] - 1e-6]
    require(
        prefix and any(s["jumped"] for s in prefix),
        "prefix does not include actual takeoff",
    )
    require_unchanged_current(dict(trace=prefix), dict(trace=control))


def contact_metrics(point, row) -> dict[str, Any]:
    contact = row["landing"]
    if not contact:
        return dict(observed=False)
    start, goal = point["start"], point["target_feet"]
    dx, dz = goal[0] - start[0], goal[2] - start[2]
    length = math.hypot(dx, dz)
    require(length > 0, "zero forward reference")
    x, z = contact["position"][0] - goal[0], contact["position"][2] - goal[2]
    return dict(
        observed=True,
        time=contact["time"],
        forward_error_m=(x * dx + z * dz) / length,
        lateral_error_m=abs(x * dz - z * dx) / length,
        horizontal_error_m=math.hypot(x, z),
        height_error_m=contact["position"][1] - 0.9 - goal[1],
    )


def observe(point, row, baseline, rate) -> dict[str, Any]:
    prefix_before_switch(point, row, baseline)
    action = action_gate(point, row, rate)
    outcome = outcomes(point, row)
    contact = contact_metrics(point, row)
    goal, start = point["target_feet"], point["start"]
    dx, dz = goal[0] - start[0], goal[2] - start[2]
    length = math.hypot(dx, dz)
    require(length > 0, "zero forward reference")
    speeds = [
        (s["velocity"][0] * dx + s["velocity"][2] * dz) / length
        for s in row["trace"]
        if s["time"] >= point["switch_time"] - 1e-6
        and not s["grounded_after"]
        and (not contact["observed"] or s["time"] < contact["time"])
    ]
    return dict(
        variant=point["air_control_variant"],
        takeoff=action["passed"],
        prefix_through_takeoff_unchanged=True,
        contact=contact,
        minimum_forward_speed_airborne=min(speeds) if speeds else None,
        airborne_reversed=any(v < -0.001 for v in speeds),
        **outcome,
    )


def freeze_matrix(directory, sources, project):
    config = read(sources)
    require(set(config) == set(MAPS), "three maps required")
    hashes = {}
    for name in MAPS:
        path = directory / f"{name}-matrix-v1.json"
        freeze(
            path,
            payload(name, config[name], project, directory / f"{name}-rejected.json"),
        )
        hashes[path.name] = sha(path)
    freeze(
        directory / "matrix-lock.json",
        dict(sources_sha256=sha(sources), manifests_sha256=hashes),
    )


def verify(directory, sources, project):
    config = read(sources)
    require(set(config) == set(MAPS), "three maps required")
    paths = [directory / f"{name}-matrix-v1.json" for name in MAPS]
    lock = directory / "matrix-lock.json"
    require(
        read(lock)
        == dict(
            sources_sha256=sha(sources),
            manifests_sha256={p.name: sha(p) for p in paths},
        ),
        "landing input lock changed",
    )
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        human_acceptance=False,
        edge_lip_timing_accepted=False,
        precision_equivalence_accepted=False,
        route_status="not_requalified",
        trials=0,
        groups=[],
        checker_sha256=sha(Path(__file__)),
        sources_sha256=sha(sources),
        evidence_sha256={lock.name: sha(lock)},
    )
    for name, path in zip(MAPS, paths):
        require(
            read(path)
            == payload(
                name, config[name], project, directory / f"{name}-rejected.json"
            ),
            "frozen landing controls changed",
        )
        result["evidence_sha256"][path.name] = sha(path)
        for rate in (60, 120):
            report = directory / f"{name}-{rate}.json"
            points, rows = checked(path, report, rate, project)
            old = {
                r["id"]: r for r in read(Path(config[name][f"report{rate}"]))["results"]
            }
            result["evidence_sha256"][report.name] = sha(report)
            result["trials"] += len(rows)
            for scheme in SCHEMES:
                base = rows[f"{scheme}__baseline"]
                base_point = points[base["id"]]
                require_unchanged_current(old[base_point["source_case"]], base)
                observations = [
                    observe(
                        points[f"{scheme}__{v}"], rows[f"{scheme}__{v}"], base, rate
                    )
                    for v in VARIANTS
                ]
                result["groups"].append(
                    dict(
                        map=name,
                        scheme=scheme,
                        physics_hz=rate,
                        observations=observations,
                    )
                )
    samples = [s for g in result["groups"] for s in g["observations"]]
    result["takeoffs"] = sum(s["takeoff"] for s in samples)
    result["first_landings"] = sum(s["first_landing"] for s in samples)
    result["arrivals"] = sum(s["supported_arrival"] for s in samples)
    result["baseline_traces_match_R17"] = len(result["groups"])
    result["by_variant"] = {
        v: dict(
            trials=sum(s["variant"] == v for s in samples),
            first_landings=sum(
                s["first_landing"] for s in samples if s["variant"] == v
            ),
            arrivals=sum(s["supported_arrival"] for s in samples if s["variant"] == v),
        )
        for v in VARIANTS
    }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze_matrix(args.directory, args.sources, args.project)
    else:
        if args.out is None:
            parser.error("--out required")
        protected = (
            tuple(args.directory.glob("*.json"))
            + (args.sources,)
            + tuple(
                Path(p) for entry in read(args.sources).values() for p in entry.values()
            )
        )
        freeze(args.out, verify(args.directory, args.sources, args.project), protected)
    print("EDGE_LANDING_CONTROLS_OK", args.mode)
