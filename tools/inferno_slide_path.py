"""Bind slide movement receipts to unchanged Inferno gameplay replays."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from movement_evidence_bank import LEVELS
from native_jump_candidates import freeze
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

IDS = ("rise_00__current__jump", "rise_02__current__jump")
PROBES = (
    "tools/authoring/SlidePathReceipt.gd",
    "tools/authoring/SlidePathProbePlayer.gd",
    "tools/authoring/audit_inferno_slide_path.gd",
)


def vector(value):
    require(
        len(value) == 3 and all(math.isfinite(x) for x in value),
        "finite vector required",
    )
    return list(value)


def add(a, b):
    return [x + y for x, y in zip(a, b)]


def subtract(a, b):
    return [x - y for x, y in zip(a, b)]


def reconstruct(sample) -> dict[str, Any]:
    start, end = vector(sample["start"]), vector(sample["end"])
    delta, last = vector(sample["position_delta"]), vector(sample["last_motion"])
    require(math.dist(add(start, delta), end) < 1e-5, "central endpoints differ")
    require(
        sample["stage"]
        in {"before_post_step", "before_snap", "before_camera", "fixture"},
        "capture phase differs",
    )
    moves = sample["movements"]
    require(sample["slide_count"] == len(moves), "collision count differs")
    cursor, points, depth = start, [start], 0.0
    for index, move in enumerate(moves):
        require(
            move["index"] == index and move["contacts"],
            "ordered collision contacts required",
        )
        travel = vector(move["travel"])
        vector(move["remainder"])
        require(
            math.isfinite(move["depth"]) and move["depth"] >= 0,
            "collision depth invalid",
        )
        depth = max(depth, move["depth"])
        for contact in move["contacts"]:
            require(
                contact["body"] and contact["shape"] >= 0,
                "bound collision body required",
            )
            vector(contact["normal"])
            vector(contact["position"])
        cursor = add(cursor, travel)
        points.append(cursor)
    tail = subtract(end, cursor)
    if math.dist(tail, [0, 0, 0]) < 1e-5:
        complete, tail_kind = True, "no_terminal_tail"
    elif math.dist(tail, last) < 1e-5:
        complete, tail_kind = True, "last_motion_tail"
        points.append(end)
    else:
        complete, tail_kind = False, "unreconciled_terminal_displacement"
    return dict(
        movement_chain_reconciled=complete,
        tail_kind=tail_kind,
        contact_moves=len(moves),
        maximum_collision_depth_m=depth,
        points=points,
        terminal_residual_m=math.dist(tail, [0, 0, 0]),
        geometric_clearance_proven=False,
    )


def check_anchor(frame, previous_position=None):
    receipt = frame["slide_path"]
    stage = receipt["stage"]
    wanted = {"before_post_step": "post_step", "before_snap": "snap"}
    if stage in wanted:
        anchors = [s for s in frame["stages"] if s["stage"] == wanted[stage]]
        require(len(anchors) == 1, "central capture stage missing")
        end = anchors[0]["before"]["position"]
    else:
        require(stage == "before_camera", "unsupported capture stage")
        end = frame["position"]
    require(math.dist(end, receipt["end"]) < 1e-5, "central capture endpoint differs")
    pre = [s for s in frame["stages"] if s["stage"] == "pre_step"]
    if pre:
        require(
            math.dist(pre[-1]["after"]["position"], receipt["start"]) < 1e-5,
            "central capture origin differs from pre-step endpoint",
        )
    elif previous_position is not None:
        require(
            math.dist(previous_position, receipt["start"]) < 1e-5,
            "central capture origin differs from previous physics endpoint",
        )


def payload(source, directory, project):
    manifest = source / "inferno-grid-v1.json"
    data = read(manifest)
    require(
        data["level"] == LEVELS["inferno"] and data["schema"] == 4, "source map differs"
    )
    points, _ = checked(manifest, source / "inferno-grid-60.json", 60, project)
    cases = []
    for key in IDS:
        point = copy.deepcopy(points[key])
        point["rejection_path"] = str(directory / "rejected.json")
        point["probe_sha256"].update({"res://" + p: sha(project / p) for p in PROBES})
        cases.append(point)
    return dict(
        data,
        cases=cases,
        source_manifest_sha256=sha(manifest),
        source_report_sha256=sha(source / "inferno-grid-60.json"),
        stage="observed_slide_api_receipts_not_clearance_qualification",
    )


def verify(source, directory, project) -> dict[str, Any]:
    manifest = directory / "matrix-v1.json"
    require(
        read(manifest) == payload(source, directory, project),
        "frozen source/probes changed",
    )
    _, old = checked(
        source / "inferno-grid-v1.json", source / "inferno-grid-60.json", 60, project
    )
    _, rows = checked(manifest, directory / "60.json", 60, project)
    require(set(rows) == set(IDS), "exact source case set required")
    sites = []
    for key in IDS:
        row = rows[key]
        require_unchanged_current(old[key], row)
        previous_position = row["settled_start"]
        for frame in row["trace"]:
            check_anchor(frame, previous_position)
            previous_position = frame["position"]
        frames = [reconstruct(s["slide_path"]) for s in row["trace"]]
        require(
            len(frames) == len(old[key]["trace"]), "complete frame receipts required"
        )
        jump = next(i for i, s in enumerate(row["trace"]) if s["jumped"])
        landing = next(
            i for i, s in enumerate(row["trace"]) if s["time"] == row["landing"]["time"]
        )
        air = frames[jump : landing + 1]
        sites.append(
            dict(
                id=key,
                frames=len(frames),
                reconciled_frames=sum(f["movement_chain_reconciled"] for f in frames),
                air_frames=len(air),
                reconciled_air_frames=sum(f["movement_chain_reconciled"] for f in air),
                air_contact_moves=sum(f["contact_moves"] for f in air),
                air_terminal_tails=sum(
                    f["tail_kind"] == "last_motion_tail" for f in air
                ),
                maximum_air_collision_depth_m=max(
                    f["maximum_collision_depth_m"] for f in air
                ),
                status="route_unproven",
                geometric_clearance_proven=False,
            )
        )
    return dict(
        schema=1,
        sites=sites,
        new_gameplay_replays=2,
        baseline_physics_input_traces_unchanged=2,
        report_sha256=sha(directory / "60.json"),
        formal_release_ready=False,
        production_changed=False,
        limitation="API travel chain reconciliation is not a full recovery/platform path or clearance proof.",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(
            args.directory / "matrix-v1.json",
            payload(args.source, args.directory, args.project),
        )
    else:
        result = verify(args.source, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print("INFERNO_SLIDE_PATH_VERIFIED", result["sites"])
