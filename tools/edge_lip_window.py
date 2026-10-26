"""Sample a fixed three-map edge-lip timing bracket without changing movement."""

import argparse
import copy
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from movement_dimension_gates import action_gate, check_control
from native_jump_candidates import freeze, inside, outcomes
from ordinary_edge_actions import edge_context
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

MAPS = ("dust2", "mirage", "inferno")
OFFSETS = (-2, -1, 0, 1, 2)
REFERENCE_HZ = 60


def support_loss(row):
    check_control(row)
    trace = row["trace"]
    require(
        row["start_valid"] and trace[0]["grounded_before"], "unsupported control start"
    )
    for index, sample in enumerate(trace):
        if not sample["grounded_after"]:
            require(
                index > 0
                and sample["grounded_before"]
                and all(s["grounded_after"] for s in trace[:index]),
                "unproven initial support interval",
            )
            return sample["time"]
    raise ValueError("control never left support")


def matrix_payload(name, source, project, rejection):
    manifest, report = Path(source["manifest"]), Path(source["report60"])
    points, rows = checked(manifest, report, REFERENCE_HZ, project)
    cases, anchors = [], {}
    for scheme in SCHEMES:
        templates = [
            p for p in points.values() if p["scheme"] == scheme and p["kind"] == "edge"
        ]
        controls = {
            m: [p for p in templates if p["trial_mode"] == m]
            for m in ("no_jump", "walk")
        }
        require(
            all(len(v) == 1 for v in controls.values()), "unique edge controls required"
        )
        control = controls["no_jump"][0]
        require(edge_context(control, rows[control["id"]]), "unproven drop context")
        for path, digest in control["probe_sha256"].items():
            require(
                sha(project / path.removeprefix("res://")) == digest,
                "author probe drift",
            )
        anchor = round(support_loss(rows[control["id"]]) * REFERENCE_HZ)
        require(anchor > 2, "no positive early request time")
        anchors[scheme] = anchor
        for mode in ("no_jump", "walk"):
            point = copy.deepcopy(controls[mode][0])
            point.update(
                id=f"control__{scheme}__{mode}",
                source_case=point["id"],
                parent_case="edge_lip",
                rejection_path=str(rejection),
            )
            cases.append(point)
        for offset in OFFSETS:
            point = copy.deepcopy(control)
            at = (anchor + offset) / REFERENCE_HZ
            point.update(
                id=f"lip__{scheme}__{offset:+d}",
                parent_case="edge_lip",
                source_case=control["id"],
                trial_mode="jump",
                lip_offset_ticks60=offset,
                request_time=at,
                rejection_path=str(rejection),
                native_timeline=[
                    dict(at=0, keys=["W"], mouse_dx=0),
                    dict(at=at, keys=["W", "Space"], mouse_dx=0),
                    dict(at=at + 1 / REFERENCE_HZ, keys=["W"], mouse_dx=0),
                    dict(at=1.5, keys=[], mouse_dx=0),
                ],
            )
            cases.append(point)
    return dict(
        read(manifest),
        cases=cases,
        stage="frozen_edge_lip_window",
        map_label=name,
        anchors_ticks60=anchors,
        offsets_ticks60=list(OFFSETS),
        anchor_policy="original_no_jump_support_loss_60Hz_not_rebased_at120",
        source_manifest_sha256=sha(manifest),
        source_report60_sha256=sha(report),
        formal_qualification=False,
        route_status="not_requalified",
    )


def prefix_matches(point, row, control):
    requested = [s for s in row["trace"] if s["input"]["jump"]]
    require(
        len(requested) == 1
        and abs(requested[0]["time"] - point["request_time"]) < 1e-6,
        "edge request missing or shifted",
    )
    count = next(i for i, s in enumerate(row["trace"]) if s["input"]["jump"])
    require(count > 0 and len(control["trace"]) >= count, "missing pre-request control")
    require_unchanged_current(
        dict(trace=row["trace"][:count]), dict(trace=control["trace"][:count])
    )
    return requested[0]


def first_contact(point, row):
    airborne = False
    for sample in row["trace"]:
        if airborne and sample["grounded_after"]:
            return dict(time=sample["time"], inside_goal=inside(point, sample))
        airborne = airborne or not sample["grounded_after"]
    return dict(time=None, inside_goal=False)


def observe(point, row, control, rate):
    sample = prefix_matches(point, row, control)
    loss = support_loss(control)
    action = action_gate(point, row, rate)
    outcome = outcomes(point, row)
    grounded = sample["grounded_before"] is True
    classification = (
        ("supported_takeoff" if grounded else "airborne_takeoff")
        if action["passed"]
        else ("supported_request_rejected" if grounded else "airborne_request_rejected")
    )
    return dict(
        offset_ticks60=point["lip_offset_ticks60"],
        request_time=sample["time"],
        actual_control_offset_ticks=round((sample["time"] - loss) * rate),
        request_grounded_before=grounded,
        takeoff=action["passed"],
        classification=classification,
        prefix_matches_control=True,
        physical_first_contact=first_contact(point, row),
        **outcome,
    )


def bracket(samples) -> dict[str, Any]:
    accepted = [
        s["request_time"] for s in samples if s["classification"] == "supported_takeoff"
    ]
    rejected = [
        s["request_time"]
        for s in samples
        if s["classification"] == "airborne_request_rejected"
    ]
    ordered = all(
        s["classification"] in ("supported_takeoff", "airborne_request_rejected")
        for s in samples
    )
    found = bool(ordered and accepted and rejected and max(accepted) < min(rejected))
    return dict(
        found=found,
        latest_sampled_takeoff=max(accepted) if accepted else None,
        earliest_sampled_rejection=min(rejected) if rejected else None,
        interval_seconds=min(rejected) - max(accepted) if found else None,
    )


def freeze_matrix(directory, sources, project):
    config = read(sources)
    require(set(config) == set(MAPS), "three map sources required")
    hashes = {}
    for name in MAPS:
        path = directory / f"{name}-matrix-v1.json"
        freeze(
            path,
            matrix_payload(
                name, config[name], project, directory / f"{name}-rejected.json"
            ),
        )
        hashes[path.name] = sha(path)
    freeze(
        directory / "matrix-lock.json",
        dict(sources_sha256=sha(sources), manifests_sha256=hashes),
    )


def verify(directory, sources, project):
    config = read(sources)
    require(set(config) == set(MAPS), "three map sources required")
    paths = [directory / f"{name}-matrix-v1.json" for name in MAPS]
    lock = directory / "matrix-lock.json"
    require(
        read(lock)
        == dict(
            sources_sha256=sha(sources),
            manifests_sha256={p.name: sha(p) for p in paths},
        ),
        "matrix lock changed",
    )
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        human_acceptance=False,
        edge_lip_timing_accepted=False,
        precision_equivalence_accepted=False,
        route_status="not_requalified",
        spawn_connectivity="unproven",
        trials=0,
        control_traces60_match_source=0,
        groups=[],
        evidence_sha256={lock.name: sha(lock)},
        checker_sha256=sha(Path(__file__)),
        sources_sha256=sha(sources),
    )
    for name, path in zip(MAPS, paths):
        manifest = read(path)
        require(
            manifest
            == matrix_payload(
                name, config[name], project, directory / f"{name}-rejected.json"
            ),
            "edge matrix changed",
        )
        result["evidence_sha256"][path.name] = sha(path)
        baseline = {r["id"]: r for r in read(Path(config[name]["report60"]))["results"]}
        for rate in (60, 120):
            report = directory / f"{name}-{rate}.json"
            points, rows = checked(path, report, rate, project)
            result["evidence_sha256"][report.name] = sha(report)
            result["trials"] += len(rows)
            for scheme in SCHEMES:
                control = rows[f"control__{scheme}__no_jump"]
                loss = support_loss(control)
                for mode in ("no_jump", "walk"):
                    p = points[f"control__{scheme}__{mode}"]
                    if rate == 60:
                        require_unchanged_current(
                            baseline[p["source_case"]], rows[p["id"]]
                        )
                        result["control_traces60_match_source"] += 1
                controls = {}
                for mode in ("no_jump", "walk"):
                    key = f"control__{scheme}__{mode}"
                    controls[mode] = dict(
                        physical_first_contact=first_contact(points[key], rows[key]),
                        **outcomes(points[key], rows[key]),
                    )
                samples = [
                    observe(
                        points[f"lip__{scheme}__{o:+d}"],
                        rows[f"lip__{scheme}__{o:+d}"],
                        control,
                        rate,
                    )
                    for o in OFFSETS
                ]
                result["groups"].append(
                    dict(
                        map=name,
                        scheme=scheme,
                        physics_hz=rate,
                        original_anchor_seconds=manifest["anchors_ticks60"][scheme]
                        / REFERENCE_HZ,
                        observed_control_loss=loss,
                        bracket=bracket(samples),
                        controls=controls,
                        samples=samples,
                    )
                )
    result["sampled_boundaries_all_groups"] = len(result["groups"]) == 18 and all(
        g["bracket"]["found"] for g in result["groups"]
    )
    samples = [s for g in result["groups"] for s in g["samples"]]
    result["supported_takeoffs"] = sum(
        s["classification"] == "supported_takeoff" for s in samples
    )
    result["airborne_requests_rejected"] = sum(
        s["classification"] == "airborne_request_rejected" for s in samples
    )
    result["qualified_first_landings_among_takeoffs"] = sum(
        s["takeoff"] and s["first_landing"] for s in samples
    )
    result["supported_arrivals_with_takeoff"] = sum(
        s["takeoff"] and s["supported_arrival"] for s in samples
    )
    result["supported_arrivals_without_takeoff"] = sum(
        not s["takeoff"] and s["supported_arrival"] for s in samples
    )
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
    print("EDGE_LIP_WINDOW_OK", args.mode)
