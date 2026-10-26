"""Frozen sub-0.1s Modern air braking and original collision-contact diagnostics."""

import argparse
import copy
import math
import statistics
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from edge_landing_controls import observe
from edge_lip_window import MAPS, REFERENCE_HZ
from movement_dimension_gates import action_gate
from native_jump_candidates import freeze
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

TICKS = (1, 2, 3, 4, 5)


def relative_body(body):
    parts = body.split("/")
    require(
        len(parts) >= 5
        and parts[:2] == ["", "root"]
        and all(p and p not in (".", "..") for p in parts[2:])
        and parts[-1] == "RuntimeCollision",
        "unbound collision body",
    )
    return "/".join(parts[3:])


def floor_contacts(row):
    contact = row["landing"]
    if not contact:
        return []
    require(contact["grounded_after"] is True, "first contact lacks support")
    result = []
    for item in contact["contacts"]:
        normal, position = item["normal"], item["position"]
        require(
            len(normal) == len(position) == 3
            and all(math.isfinite(v) for v in (*normal, *position))
            and abs(math.sqrt(sum(v * v for v in normal)) - 1) <= 0.02,
            "invalid collision contact",
        )
        if normal[1] >= 0.7:
            relative = relative_body(item["body"])
            result.append(dict(body=relative, normal_y=normal[1], height=position[1]))
    require(bool(result), "supported first contact has no floor normal")
    return result


def contact_proof(point, row) -> dict[str, Any]:
    contacts = floor_contacts(row)
    if not contacts:
        return dict(observed=False)
    require(
        all(
            c["body"].split("/")[0] in point["original_collision_roots"]
            for c in contacts
        ),
        "contact outside original collision root",
    )
    heights = [c["height"] for c in contacts]
    height = statistics.median(heights)
    target_error = height - point["target_feet"][1]
    initial_error = height - (row["settled_start"][1] - 0.9)
    return dict(
        observed=True,
        bodies=sorted({c["body"] for c in contacts}),
        minimum_normal_y=min(c["normal_y"] for c in contacts),
        height_span_m=max(heights) - min(heights),
        target_plane_error_m=target_error,
        initial_plane_error_m=initial_error,
        within_target_height=abs(target_error) <= point["target_height_tolerance"],
        matches_initial_height=abs(initial_error) <= 0.03,
        scope="collision_group_and_height_not_visual_prop_or_triangle_identity",
    )


def short_timeline(original, ticks) -> list[dict[str, Any]]:
    require(type(ticks) is int and ticks in TICKS, "unfrozen reverse duration")
    at, switch = original["request_time"], original["switch_time"]
    return [
        dict(at=0, keys=["W"], mouse_dx=0),
        dict(at=at, keys=["W", "Space"], mouse_dx=0),
        dict(at=switch, keys=["S"], mouse_dx=0),
        dict(at=switch + ticks / REFERENCE_HZ, keys=[], mouse_dx=0),
        dict(at=1.5, keys=[], mouse_dx=0),
    ]


def payload(name, source, project, rejection):
    manifest, report = Path(source["manifest"]), Path(source["report60"])
    points, rows = checked(manifest, report, 60, project)
    require(
        read(manifest)["stage"] == "frozen_post_takeoff_controls",
        "wrong braking parent",
    )
    baseline = points["modern_cs__baseline"]
    require(
        all(
            action_gate(points[k], rows[k], 60)["passed"]
            for k in ("modern_cs__baseline", "modern_cs__reverse_010")
        ),
        "controls require real takeoff",
    )
    roots = sorted(
        {
            c["body"].split("/")[0]
            for c in floor_contacts(rows["modern_cs__reverse_010"])
        }
    )
    require(bool(roots), "missing original contact root")
    for path, digest in baseline["probe_sha256"].items():
        require(
            sha(project / path.removeprefix("res://")) == digest, "author probe drift"
        )
    cases = []
    for variant in ("baseline", "reverse_010", *(f"brake_{n}" for n in TICKS)):
        original = (
            points[f"modern_cs__{variant}"]
            if variant in ("baseline", "reverse_010")
            else baseline
        )
        point = copy.deepcopy(original)
        point.update(
            id=f"modern_cs__{variant}",
            source_case=original["id"],
            air_control_variant=variant,
            original_collision_roots=roots,
            rejection_path=str(rejection),
            parent_case="modern_short_brake",
        )
        if variant.startswith("brake_"):
            n = int(variant.removeprefix("brake_"))
            point.update(
                reverse_reference_ticks=n, native_timeline=short_timeline(original, n)
            )
        cases.append(point)
    return dict(
        read(manifest),
        stage="frozen_modern_short_brake_window",
        cases=cases,
        map_label=name,
        reference_ticks=list(TICKS),
        selection_policy="all_frozen_before_both_rates",
        source_manifest_sha256=sha(manifest),
        source_report60_sha256=sha(report),
        source_report120_sha256=sha(Path(source["report120"])),
        formal_qualification=False,
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
        "short brake lock changed",
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
            "frozen short brake inputs changed",
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
            for variant in ("baseline", "reverse_010"):
                key = f"modern_cs__{variant}"
                require_unchanged_current(old[key], rows[key])
                original = contact_proof(points[key], old[key])
                current = contact_proof(points[key], rows[key])
                require(
                    original["bodies"] == current["bodies"]
                    and abs(
                        original["target_plane_error_m"]
                        - current["target_plane_error_m"]
                    )
                    < 1e-5,
                    "control floor contact changed",
                )
            observations = []
            for key, point in points.items():
                result_row = observe(
                    point, rows[key], rows["modern_cs__baseline"], rate
                )
                result_row["floor_contact"] = contact_proof(point, rows[key])
                if "reverse_reference_ticks" in point:
                    result_row["reverse_reference_ticks"] = point[
                        "reverse_reference_ticks"
                    ]
                observations.append(result_row)
            result["groups"].append(
                dict(
                    map=name,
                    physics_hz=rate,
                    observations=observations,
                    successful_ticks=[
                        o["reverse_reference_ticks"]
                        for o in observations
                        if o["first_landing"] and "reverse_reference_ticks" in o
                    ],
                )
            )
    groups = result["groups"]
    result["common_success_ticks"] = sorted(
        set.intersection(*(set(g["successful_ticks"]) for g in groups))
    )
    result["takeoffs"] = sum(o["takeoff"] for g in groups for o in g["observations"])
    result["first_landings"] = sum(
        o["first_landing"] for g in groups for o in g["observations"]
    )
    result["control_traces_match_R18"] = len(groups) * 2
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
    print("MODERN_BRAKE_WINDOW_OK", args.mode)
