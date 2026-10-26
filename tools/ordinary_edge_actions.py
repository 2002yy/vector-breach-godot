"""Freeze ordinary/edge action inputs without upgrading old route qualification."""

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from movement_dimension_gates import action_gate, check_control
from native_jump_candidates import RUNTIME, check_report, digital, freeze
from queued_three_map_audit import (
    CADENCE_PROBES,
    MAPS,
    PROBES,
    QUEUE_PROBES,
    check_cadence,
)
from validate_native_route_study import require

KINDS = ("ordinary", "edge")
MODES = ("jump", "no_jump", "walk")


def payload(source_path, project, rejection_path):
    source = read(source_path)
    parents = [p for p in source["cases"] if p["id"] in KINDS]
    require(
        len(parents) == 2 and {p["kind"] for p in parents} == set(KINDS),
        "ordinary and edge source points required exactly once",
    )
    cases = []
    for parent in parents:
        require(parent["id"] == parent["kind"], "source category mismatch")
        native = digital(parent["timeline"])
        if parent["kind"] == "ordinary":
            require(
                not any(set(e["keys"]) & {"W", "A", "S", "D"} for e in native),
                "ordinary action must have stationary inputs",
            )
        for scheme in SCHEMES:
            for mode in MODES:
                point = copy.deepcopy(parent)
                timeline = copy.deepcopy(native)
                if mode != "jump":
                    for event in timeline:
                        event["keys"] = [k for k in event["keys"] if k != "Space"]
                        if mode == "walk" and "Shift" not in event["keys"]:
                            event["keys"].append("Shift")
                point.update(
                    id=f"{parent['id']}__{scheme}__{mode}",
                    parent_case=parent["id"],
                    scheme=scheme,
                    trial_mode=mode,
                    native_timeline=timeline,
                    queued_input=True,
                    ablation="baseline",
                    enforce_cadence=True,
                    rejection_path=str(rejection_path),
                    probe_sha256={
                        "res://" + p: sha(project / p)
                        for p in (*PROBES, *QUEUE_PROBES, *CADENCE_PROBES)
                    },
                )
                cases.append(point)
    return dict(
        schema=4,
        formal_qualification=False,
        diagnostic_only=True,
        native_acceptance=False,
        level=source["level"],
        identity=source["identity"],
        parent_sha256=sha(source_path),
        input_map_sha256=sha(project / "project.godot"),
        runtime_sha256={"res://" + p: sha(project / p) for p in RUNTIME},
        cases=cases,
    )


def edge_context(point, control):
    """A labelled drop is only context when the paired body actually leaves support."""
    geometry = point["geometry"]
    require(
        len(geometry["feet"]) == len(geometry["near_feet"]) == 3,
        "missing surveyed edge context",
    )
    check_control(control)
    trace = control["trace"]
    return bool(
        control["start_valid"]
        and trace[0]["grounded_before"]
        and geometry["near_feet"][1] < geometry["feet"][1] - 0.5
        and any(not s["grounded_after"] for s in trace)
        and min(s["position"][1] for s in trace) < control["settled_start"][1] - 0.5
    )


def verify(directory, sources, project):
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        route_qualification_replaced=False,
        trials=0,
        points=[],
        evidence_sha256={},
        checker_sha256=sha(Path(__file__)),
    )
    for name in MAPS:
        path = directory / f"{name}-actions-v1.json"
        source = sources / f"{name}-manifest.json"
        manifest = read(path)
        require(
            manifest == payload(source, project, directory / f"{name}-rejected.json"),
            "frozen action inputs or source changed",
        )
        result["evidence_sha256"][path.name] = sha(path)
        result["evidence_sha256"][f"source/{source.name}"] = sha(source)
        cases = {p["id"]: p for p in manifest["cases"]}
        rows, outcomes = {}, {}
        for rate in (60, 120):
            report = directory / f"{name}-{rate}.json"
            outcomes[rate] = check_report(path, report, rate, project)
            rows[rate] = {r["id"]: r for r in read(report)["results"]}
            result["evidence_sha256"][report.name] = sha(report)
            result["trials"] += len(rows[rate])
            for key, point in cases.items():
                check_cadence(rows[rate][key], point)
                trace = rows[rate][key]["trace"]
                for a, b in zip(trace, trace[1:]):
                    require(
                        b["cadence"]["process_frame"] - a["cadence"]["process_frame"]
                        == 1
                        and b["cadence"]["physics_frame"]
                        - a["cadence"]["physics_frame"]
                        == 1,
                        "control or action engine counters contradict cadence",
                    )
                if point["trial_mode"] != "jump":
                    check_control(rows[rate][key])
        for kind in KINDS:
            for scheme in SCHEMES:
                key = f"{kind}__{scheme}__jump"
                point = cases[key]
                actions = {r: action_gate(point, rows[r][key], r) for r in (60, 120)}
                contexts = {
                    r: edge_context(point, rows[r][f"{kind}__{scheme}__no_jump"])
                    if kind == "edge"
                    else True
                    for r in (60, 120)
                }
                result["points"].append(
                    dict(
                        map=name,
                        kind=kind,
                        scheme=scheme,
                        actions={str(r): a for r, a in actions.items()},
                        edge_context={str(r): c for r, c in contexts.items()},
                        edge_observation={
                            str(r): dict(
                                control_first_loss_time=next(
                                    (
                                        s["time"]
                                        for s in rows[r][f"{kind}__{scheme}__no_jump"][
                                            "trace"
                                        ]
                                        if not s["grounded_after"]
                                    ),
                                    None,
                                ),
                                control_drop_metres=rows[r][
                                    f"{kind}__{scheme}__no_jump"
                                ]["settled_start"][1]
                                - min(
                                    s["position"][1]
                                    for s in rows[r][f"{kind}__{scheme}__no_jump"][
                                        "trace"
                                    ]
                                ),
                            )
                            for r in (60, 120)
                        }
                        if kind == "edge"
                        else {},
                        edge_lip_timing_accepted=False,
                        category_action_passed=all(
                            a["passed"] for a in actions.values()
                        )
                        and all(contexts.values()),
                        route_status="not_requalified",
                        control_arrivals={
                            str(r): {
                                m: outcomes[r][f"{kind}__{scheme}__{m}"][
                                    "supported_arrival"
                                ]
                                for m in ("no_jump", "walk")
                            }
                            for r in (60, 120)
                        },
                    )
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
        for name in MAPS:
            source = args.sources / f"{name}-manifest.json"
            freeze(
                args.directory / f"{name}-actions-v1.json",
                payload(source, args.project, args.directory / f"{name}-rejected.json"),
                (source,),
            )
        print("ORDINARY_EDGE_INPUTS_FROZEN")
    else:
        if args.out is None:
            parser.error("--out is required for verification")
        require(not args.out.exists(), "fresh output required")
        result = verify(args.directory, args.sources, args.project)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("ORDINARY_EDGE_ACTIONS_WRITTEN", result["trials"])
