"""Freeze actual run-up body poses; never infer clearance from landing success."""

import argparse
import math
from pathlib import Path

from build_native_route_study import read, sha
from edge_drop_revision import checked
from movement_evidence_bank import LEVELS
from native_jump_candidates import freeze
from validate_native_route_study import require

PROBES = (
    "tools/authoring/ObservedPathSweep.gd",
    "tools/authoring/audit_observed_inferno.gd",
)
IDS = ("rise_00__current__jump", "rise_02__current__jump")


def poses(row):
    trace = row["trace"]
    jumps = [i for i, s in enumerate(trace) if s["jumped"]]
    require(len(jumps) == 1 and jumps[0] > 0, "one jump with previous pose required")
    start = jumps[0]
    landing = row["landing"]
    require(landing is not None, "first landing required")
    ends = [i for i, s in enumerate(trace) if s["time"] == landing["time"]]
    require(len(ends) == 1 and ends[0] >= start, "unique first landing required")
    end = ends[0]
    require(trace[end]["grounded_after"], "landing support required")
    result = []

    def append(position, height, label, tick):
        require(
            len(position) == 3 and all(math.isfinite(x) for x in position),
            "finite pose required",
        )
        require(0.8 <= height <= 2.0, "capsule height invalid")
        point = dict(position=list(position), height=height, label=label, tick=tick)
        if (
            result
            and result[-1]["position"] == point["position"]
            and result[-1]["height"] == height
        ):
            return
        result.append(point)

    previous = trace[start - 1]
    append(
        previous["position"], previous["capsule_height"], "before_takeoff", start - 1
    )
    for index in range(start, end + 1):
        sample = trace[index]
        for stage in sample["stages"]:
            require(
                stage["stage"] in ("pre_step", "post_step", "snap"), "unknown stage"
            )
            for phase in ("before", "after"):
                append(
                    stage[phase]["position"],
                    sample["capsule_height"],
                    stage["stage"] + "_" + phase,
                    index,
                )
        append(sample["position"], sample["capsule_height"], "physics_end", index)
    require(result[-1]["position"] == landing["position"], "final landing pose missing")
    require(len(result) >= 2, "nonempty observed segment chain required")
    return result


def check_segments(case, row):
    require(len(case["poses"]) >= 2, "nonempty observed segment chain required")
    require(
        len(row["segments"]) == len(case["poses"]) - 1,
        "complete segment chain required",
    )
    for i, segment in enumerate(row["segments"]):
        require(
            segment["from"] == case["poses"][i]["position"]
            and segment["to"] == case["poses"][i + 1]["position"],
            "segment endpoints differ",
        )
        transition = (
            abs(case["poses"][i]["height"] - case["poses"][i + 1]["height"]) > 0.00001
        )
        require(
            abs(
                segment["height"]
                - max(case["poses"][i]["height"], case["poses"][i + 1]["height"])
            )
            < 1e-6
            and segment["height_transition"] == transition,
            "capsule segment dimensions differ",
        )
        require(
            math.isfinite(segment["free_fraction"])
            and 0 <= segment["free_fraction"] <= 1,
            "invalid sweep fraction",
        )
        require(
            all(
                isinstance(segment[key], int) and segment[key] >= 0
                for key in ("initial_overlaps", "endpoint_overlaps")
            ),
            "invalid overlap count",
        )
        expected = (
            not segment["initial_overlaps"]
            and not segment["endpoint_overlaps"]
            and segment["free_fraction"] >= 0.999999
            and not transition
        )
        require(segment["clear"] == expected, "segment clearance differs")
    clear = all(s["clear"] for s in row["segments"])
    require(row["clear"] == clear, "clearance aggregate differs")
    return clear


def check_result_ids(report):
    require(
        len(report["results"]) == len(IDS)
        and {p["id"] for p in report["results"]} == set(IDS),
        "case set or count differs",
    )


def payload(directory, project):
    source = directory / "inferno-grid-v1.json"
    report = directory / "inferno-grid-60.json"
    manifest = read(source)
    require(manifest["level"] == LEVELS["inferno"], "source map differs")
    points, rows = checked(source, report, 60, project)
    cases = []
    for key in IDS:
        require(rows[key]["target_reached"], "source first landing must pass")
        cases.append(
            dict(
                id=key,
                poses=poses(rows[key]),
                original_corridor=rows[key]["ingress_corridor"]["status"],
            )
        )
    return dict(
        schema=1,
        level=manifest["level"],
        identity=manifest["identity"],
        cases=cases,
        source_manifest_sha256=sha(source),
        source_report_sha256=sha(report),
        actor_scene_sha256=sha(project / "scenes/player/Player.tscn"),
        probe_sha256={p: sha(project / p) for p in PROBES},
        collision_mask=1,
        margin=0.001,
        diagnostic_only=True,
        qualification="continuous_piecewise_capsule_path_not_engine_slide_replay",
    )


def verify(directory, evidence, project):
    frozen = evidence / "path-v1.json"
    require(read(frozen) == payload(directory, project), "frozen observed path differs")
    report = read(evidence / "sweep.json")
    require(
        report["schema"] == 1
        and abs(report["capsule_radius"] - 0.4) < 1e-7
        and report["local_shape_offset"] == [0, 0, 0]
        and report["margin"] == 0.001,
        "capsule query contract differs",
    )
    require(report["manifest_sha256"] == sha(frozen), "manifest hash differs")
    require(
        report["probe_sha256"] == read(frozen)["probe_sha256"], "probe hash differs"
    )
    require(report["identity"] == read(frozen)["identity"], "geometry identity differs")
    check_result_ids(report)
    result = []
    for case, row in zip(read(frozen)["cases"], report["results"]):
        require(case["id"] == row["id"], "case order differs")
        clear = check_segments(case, row)
        result.append(
            dict(
                id=case["id"],
                segments=len(row["segments"]),
                clear_segments=sum(s["clear"] for s in row["segments"]),
                contact_segments=sum(s["support_contact"] for s in row["segments"]),
                initial_overlaps=sum(
                    s["initial_overlaps"] > 0 for s in row["segments"]
                ),
                endpoint_overlaps=sum(
                    s["endpoint_overlaps"] > 0 for s in row["segments"]
                ),
                minimum_free_fraction=min(s["free_fraction"] for s in row["segments"]),
                observed_piecewise_path_clear=clear,
                original_corridor=case["original_corridor"],
                status="observed_geometric_path_clear" if clear else "route_unproven",
            )
        )
    actual_calls = sum(
        3 + int(s["free_fraction"] < 1.0)
        for row in report["results"]
        for s in row["segments"]
    )
    require(report["collision_queries"] == actual_calls, "native query count differs")
    return dict(
        schema=1,
        results=result,
        source_reports_sha256=dict(
            source=sha(directory / "inferno-grid-60.json"),
            sweep=sha(evidence / "sweep.json"),
        ),
        new_gameplay_replays=0,
        collision_queries=actual_calls,
        formal_release_ready=False,
        production_changed=False,
        limitation="Exact full capsule swept on recorded stage chords; nonclear chords cannot disprove actual engine slide path. Floor contact is not excluded.",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(args.evidence / "path-v1.json", payload(args.source, args.project))
    else:
        result = verify(args.source, args.evidence, args.project)
        freeze(args.evidence / "validated-summary-v2.json", result)
        print("OBSERVED_INFERNO_VERIFIED", result["results"])
