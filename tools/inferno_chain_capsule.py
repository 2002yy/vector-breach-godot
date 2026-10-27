"""Bind full-body diagnostic sweeps to observed API travels and last-motion tails."""

import argparse
import math
from pathlib import Path

from build_native_route_study import read, sha
from edge_drop_revision import checked
from inferno_slide_path import IDS, check_anchor, reconstruct
from inferno_slide_path import verify as verify_prior
from native_jump_candidates import freeze
from validate_native_route_study import require

PROBES = (
    "tools/authoring/ChainCapsuleSweep.gd",
    "tools/authoring/audit_inferno_chain_capsule.gd",
)


def segments_for(row):
    trace = row["trace"]
    jump = next(i for i, frame in enumerate(trace) if frame["jumped"])
    end = next(
        i for i, frame in enumerate(trace) if frame["time"] == row["landing"]["time"]
    )
    segments, outside = [], []
    previous = row["settled_start"]
    for tick, frame in enumerate(trace):
        check_anchor(frame, previous)
        previous = frame["position"]
        chain = reconstruct(frame["slide_path"])
        if not jump <= tick <= end:
            if not chain["movement_chain_reconciled"]:
                outside.append(tick)
            continue
        require(chain["movement_chain_reconciled"], "unreconciled airborne chain")
        require(
            not frame["crouching"] and abs(frame["capsule_height"] - 1.8) < 1e-6,
            "standing-only source required for zero local offset",
        )
        receipt = frame["slide_path"]
        points = chain["points"]
        for index, (a, b) in enumerate(zip(points, points[1:])):
            segments.append(
                dict(
                    tick=tick,
                    time=frame["time"],
                    part=index,
                    kind="travel"
                    if index < receipt["slide_count"]
                    else "last_motion_tail",
                    **{"from": a, "to": b},
                    height=frame["capsule_height"],
                    local_offset=[0, 0, 0],
                    recovery_depth=chain["maximum_collision_depth_m"],
                )
            )
        # Same-frame central chord is a comparison query, never actual-path authority.
        segments.append(
            dict(
                tick=tick,
                time=frame["time"],
                part=-1,
                kind="comparison_chord",
                **{"from": receipt["start"], "to": receipt["end"]},
                height=frame["capsule_height"],
                local_offset=[0, 0, 0],
                recovery_depth=chain["maximum_collision_depth_m"],
            )
        )
    return segments, outside, end - jump + 1


def payload(source, project):
    # Revalidate the prior baseline physics/input equivalence, not its summary.
    verify_prior(
        source.parent / "runup-route-revision-20261027" / "v2", source, project
    )
    manifest = source / "matrix-v1.json"
    report = source / "60.json"
    _, rows = checked(manifest, report, 60, project)
    data = read(manifest)
    cases = []
    for key in IDS:
        segments, outside, frames = segments_for(rows[key])
        cases.append(
            dict(
                id=key,
                segments=segments,
                outside_unreconciled=outside,
                air_frames=frames,
            )
        )
    return dict(
        schema=1,
        baseline="11b236202d27cf74eb1c252b94bee1577139c339",
        level=data["level"],
        identity=data["identity"],
        runtime_sha256=data["runtime_sha256"],
        source_manifest_sha256=sha(manifest),
        source_report_sha256=sha(report),
        prior_baseline_manifest_sha256=data["source_manifest_sha256"],
        prior_baseline_report_sha256=data["source_report_sha256"],
        source_probe_sha256={
            key: value
            for case in data["cases"]
            for key, value in case["probe_sha256"].items()
        },
        actor_scene_sha256=sha(project / "scenes/player/Player.tscn"),
        probe_sha256={path: sha(project / path) for path in PROBES},
        radius=0.4,
        local_offset=[0, 0, 0],
        margin=0.001,
        collision_mask=1,
        excluded_bodies=[],
        cases=cases,
    )


def bound_equal(a, b):
    if isinstance(a, dict):
        return (
            isinstance(b, dict)
            and a.keys() == b.keys()
            and all(bound_equal(a[k], b[k]) for k in a)
        )
    if isinstance(a, list):
        return (
            isinstance(b, list)
            and len(a) == len(b)
            and all(bound_equal(x, y) for x, y in zip(a, b))
        )
    if isinstance(a, (float, int)) and not isinstance(a, bool):
        return isinstance(b, (float, int)) and math.isfinite(b) and abs(a - b) < 1e-10
    return a == b


def verify(source, output, project):
    manifest = read(output / "chain-v1.json")
    require(
        manifest == payload(source, project),
        "frozen chain/source/runtime/probes changed",
    )
    report = read(output / "sweep.json")
    require(
        report["manifest_sha256"] == sha(output / "chain-v1.json"),
        "query manifest changed",
    )
    for key in ("identity", "probe_sha256", "runtime_sha256"):
        require(report[key] == manifest[key], "query binding differs: " + key)
    require(len(report["results"]) == len(IDS), "query case count differs")
    results = []
    query_count = 0
    for case, row in zip(manifest["cases"], report["results"]):
        require(row["id"] == case["id"], "query case differs")
        require(
            len(row["segments"]) == len(case["segments"]), "query segment count differs"
        )
        for segment, observed in zip(case["segments"], row["segments"]):
            require(
                bound_equal(segment, observed["segment"]),
                "query segment/source binding differs",
            )
            require(
                0 <= observed["free_fraction"] <= observed["unsafe_fraction"] <= 1,
                "invalid cast fraction",
            )
            clear = (
                not observed["initial_overlaps"]
                and not observed["endpoint_overlaps"]
                and observed["free_fraction"] >= 0.999999
            )
            require(
                observed["query_clear"] == clear, "clearance classification differs"
            )
            require(
                observed["clearance_proven"]
                == (clear and segment["recovery_depth"] == 0),
                "recovery qualification differs",
            )
            query_count += 5 + int(observed["free_fraction"] < 1)
            require(
                observed["query_count"] == 5 + int(observed["free_fraction"] < 1),
                "segment query count differs",
            )
        actual = [
            s for s in row["segments"] if s["segment"]["kind"] != "comparison_chord"
        ]
        chords = [
            s for s in row["segments"] if s["segment"]["kind"] == "comparison_chord"
        ]
        changed = [
            c["segment"]["tick"]
            for c in chords
            if not c["query_clear"]
            and all(
                s["query_clear"]
                for s in actual
                if s["segment"]["tick"] == c["segment"]["tick"]
            )
        ]
        results.append(
            dict(
                id=case["id"],
                air_frames=case["air_frames"],
                actual_segments=len(actual),
                last_motion_tails=sum(
                    s["segment"]["kind"] == "last_motion_tail" for s in actual
                ),
                query_clear_segments=sum(s["query_clear"] for s in actual),
                proven_segments=sum(s["clearance_proven"] for s in actual),
                overlap_segments=sum(
                    bool(s["initial_overlaps"] or s["endpoint_overlaps"])
                    for s in actual
                ),
                support_cast_segments=sum(
                    s["impact_contact"]["classification"] == "support" for s in actual
                ),
                wall_cast_segments=sum(
                    s["impact_contact"]["classification"] == "wall_or_ceiling"
                    for s in actual
                ),
                recovery_depth_segments=sum(
                    s["segment"]["recovery_depth"] > 0 for s in actual
                ),
                nonclear_comparison_chords=sum(not c["query_clear"] for c in chords),
                old_chord_nonclear_removed_ticks=changed,
                outside_unreconciled_frames=len(case["outside_unreconciled"]),
                status="route_unproven",
                geometric_clearance_proven=False,
            )
        )
    require(report["collision_queries"] == query_count, "query count differs")
    return dict(
        schema=1,
        results=results,
        collision_queries=query_count,
        source_report_sha256=sha(source / "60.json"),
        query_report_sha256=sha(output / "sweep.json"),
        new_gameplay_replays=0,
        production_changed=False,
        formal_release_ready=False,
        limitation="Contact/overlap and nonzero recovery depth remain unproven; central chains do not prove other stage displacements or 12 outside-interval recovery frames.",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(args.output / "chain-v1.json", payload(args.source, args.project))
    else:
        result = verify(args.source, args.output, args.project)
        freeze(args.output / "validated-summary.json", result)
        print(result)
