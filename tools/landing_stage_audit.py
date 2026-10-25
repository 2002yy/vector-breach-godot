"""Observe and ablate step/snap stages without editing production movement."""

import argparse
import copy
import json
import math
from pathlib import Path

from build_native_route_study import read, sha
from native_jump_candidates import check_report, freeze
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

PROBES = (
    "tools/authoring/LandingStageProbePlayer.gd",
    "tools/authoring/audit_landing_stages.gd",
)
STAGES = {"pre_step": "no_pre", "post_step": "no_try", "snap": "no_snap"}
EDGE_PROBES = (
    "tools/authoring/JumpEdgeProbePlayer.gd",
    "tools/authoring/audit_jump_edge.gd",
)
QUEUE_PROBES = (
    "tools/authoring/QueuedKeyProbePlayer.gd",
    "tools/authoring/audit_queued_key.gd",
)


def payload(source_path, project):
    source = read(source_path)
    require(
        source["schema"] == 4
        and source["formal_qualification"] is False
        and not source.get("camera_only"),
        "physical diagnostic source required",
    )
    parents = {p["parent_case"] for p in source["cases"]}
    expected = {
        (parent, scheme, mode)
        for parent in parents
        for scheme in ("current", "legacy_16", "modern_cs")
        for mode in ("jump", "no_jump", "walk")
    }
    require(
        len(parents) == 2
        and len(source["cases"]) == 18
        and len({p["id"] for p in source["cases"]}) == 18
        and {(p["parent_case"], p["scheme"], p["trial_mode"]) for p in source["cases"]}
        == expected,
        "retain complete reference matrix",
    )
    hashes = {"res://" + p: sha(project / p) for p in PROBES}
    cases = []
    for original in source["cases"]:
        base = copy.deepcopy(original)
        base.update(
            ablation="baseline", source_case=original["id"], probe_sha256=hashes
        )
        cases.append(base)
        if original["scheme"] == "modern_cs" and original["trial_mode"] == "jump":
            for variant in ("no_pre", "no_try", "no_snap"):
                case = copy.deepcopy(base)
                case.update(id=original["id"] + "__" + variant, ablation=variant)
                cases.append(case)
    require(len(cases) == 24, "expected two Modern jumps for stage ablation")
    return dict(
        source,
        cases=cases,
        source_manifest_sha256=sha(source_path),
        diagnostic_only=True,
        diagnostic_variants=["baseline", "no_pre", "no_try", "no_snap"],
    )


def stage_changes(row, point):
    require(
        row["trace"][0]["probe_sha256"] == point["probe_sha256"],
        "probe identity changed",
    )
    events = []
    for sample in row["trace"]:
        seen = set()
        for stage in sample["stages"]:
            name = stage["stage"]
            require(name in STAGES and name not in seen, "invalid/duplicate stage")
            seen.add(name)
            enabled = point["ablation"] != STAGES[name]
            require(stage["enabled"] is enabled, "ablation switch not respected")
            before, after = stage["before"], stage["after"]
            if not enabled:
                require(before == after, "disabled stage changed physics")
            dy = after["position"][1] - before["position"][1]
            displacement = math.dist(before["position"], after["position"])
            velocity_change = math.dist(before["velocity"], after["velocity"])
            if (
                displacement > 1e-6
                or velocity_change > 1e-6
                or before["grounded"] != after["grounded"]
            ):
                events.append(
                    dict(
                        time=sample["time"],
                        stage=name,
                        delta_y=dy,
                        displacement=displacement,
                        velocity_change=velocity_change,
                        grounded_before=before["grounded"],
                        grounded_after=after["grounded"],
                        velocity_y_before=before["velocity"][1],
                        velocity_y_after=after["velocity"][1],
                    )
                )
    return events


def edge_payload(source_path, project):
    base = payload(source_path, project)
    hashes = {"res://" + p: sha(project / p) for p in (*PROBES, *EDGE_PROBES)}
    cases = []
    for point in base["cases"]:
        if point["ablation"] != "baseline":
            continue
        point = copy.deepcopy(point)
        point.update(immediate_jump=False, probe_sha256=hashes)
        cases.append(point)
        if point["scheme"] == "modern_cs" and point["trial_mode"] == "jump":
            control = copy.deepcopy(point)
            control.update(id=point["id"] + "__immediate_jump", immediate_jump=True)
            cases.append(control)
    return dict(
        base,
        cases=cases,
        jump_consumption_diagnostic=True,
        native_acceptance=False,
        diagnostic_variants=["native", "immediate_jump"],
    )


def queued_payload(source_path, project):
    data = edge_payload(source_path, project)
    hashes = {"res://" + p: sha(project / p) for p in (*PROBES, *QUEUE_PROBES)}
    for point in data["cases"]:
        point["queued_input"] = point.pop("immediate_jump")
        point["id"] = point["id"].replace("__immediate_jump", "__queued_input")
        point["probe_sha256"] = hashes
    return dict(
        data, diagnostic_variants=["native", "queued_input"], fixed_fps_diagnostic=True
    )


def verify_edge(directory, source_path, source_directory, project, queued=False):
    prefix = "queue" if queued else "edge"
    mode_key = "queued_input" if queued else "immediate_jump"
    path = directory / f"{prefix}-study-v1.json"
    manifest = read(path)
    require(
        manifest == (queued_payload if queued else edge_payload)(source_path, project),
        "frozen edge diagnostic changed",
    )
    summary = dict(
        formal_release_ready=False,
        native_acceptance=False,
        baseline_traces_unchanged=True,
        production_changed=False,
        trials=0,
        results=[],
        cross_rate=[],
    )
    reports = {}
    for rate in (60, 120):
        report_path = directory / f"{prefix}-{rate}.json"
        outcomes = check_report(path, report_path, rate, project)
        baseline_path = source_directory / f"selected-{rate}.json"
        check_report(source_path, baseline_path, rate, project)
        originals = {r["id"]: r for r in read(baseline_path)["results"]}
        rows = {r["id"]: r for r in read(report_path)["results"]}
        reports[rate] = rows
        summary["trials"] += len(rows)
        if queued:
            edge_path = directory / "edge-study-v1.json"
            edge_report = directory / f"edge-{rate}.json"
            require(
                read(edge_path) == edge_payload(source_path, project),
                "counterfactual source changed",
            )
            check_report(edge_path, edge_report, rate, project)
            counterfactual = {r["id"]: r for r in read(edge_report)["results"]}
        for point in manifest["cases"]:
            row = rows[point["id"]]
            require(row[mode_key] == point[mode_key], "edge mode changed")
            changes = stage_changes(row, point)
            if not point[mode_key]:
                require_unchanged_current(originals[point["source_case"]], row)
            else:
                require(
                    row["input_kind"]
                    == (
                        "diagnostic_native_keys_queued_before_physics_not_OS"
                        if queued
                        else "diagnostic_immediate_jump_not_native_edge_or_human"
                    ),
                    "immediate diagnostic mislabelled as native",
                )
                if queued:
                    other = counterfactual[
                        point["id"].replace("__queued_input", "__immediate_jump")
                    ]
                    require_unchanged_current(other, row)
            if point["scheme"] == "modern_cs" and point["trial_mode"] == "jump":
                summary["results"].append(
                    dict(
                        case=point["parent_case"],
                        physics_hz=rate,
                        timing_mode=mode_key if point[mode_key] else "native",
                        stage_changes=changes,
                        jump_times=[s["time"] for s in row["trace"] if s["jumped"]],
                        **outcomes[point["id"]],
                    )
                )
    for point in manifest["cases"]:
        if point["scheme"] != "modern_cs" or point["trial_mode"] != "jump":
            continue
        left, right = (reports[r][point["id"]] for r in (60, 120))
        summary["cross_rate"].append(
            dict(
                case=point["parent_case"],
                timing_mode=mode_key if point[mode_key] else "native",
                landing_position_difference=math.dist(
                    left["landing"]["position"], right["landing"]["position"]
                )
                if left["landing"] and right["landing"]
                else None,
                landing_time_difference=abs(
                    left["landing"]["time"] - right["landing"]["time"]
                )
                if left["landing"] and right["landing"]
                else None,
            )
        )
    if queued:
        summary["native_queued_matches_counterfactual_traces"] = True
    return summary


def verify(directory, source_path, source_directory, project):
    path = directory / "stage-study-v1.json"
    manifest = read(path)
    require(manifest == payload(source_path, project), "frozen stage study changed")
    summary = dict(
        formal_release_ready=False,
        diagnostic_only=True,
        production_changed=False,
        baseline_traces_unchanged=True,
        trials=0,
        results=[],
        cross_rate=[],
    )
    reports = {}
    for rate in (60, 120):
        report_path = directory / f"stages-{rate}.json"
        results = check_report(path, report_path, rate, project)
        baseline_path = source_directory / f"selected-{rate}.json"
        check_report(source_path, baseline_path, rate, project)
        original = {r["id"]: r for r in read(baseline_path)["results"]}
        rows = {r["id"]: r for r in read(report_path)["results"]}
        reports[rate] = rows
        summary["trials"] += len(rows)
        for point in manifest["cases"]:
            row = rows[point["id"]]
            changes = stage_changes(row, point)
            if point["ablation"] == "baseline":
                require_unchanged_current(original[point["source_case"]], row)
            if point["scheme"] == "modern_cs" and point["trial_mode"] == "jump":
                summary["results"].append(
                    dict(
                        case=point["parent_case"],
                        variant=point["ablation"],
                        physics_hz=rate,
                        **results[point["id"]],
                        stage_changes=changes,
                    )
                )
    for point in manifest["cases"]:
        if point["scheme"] != "modern_cs" or point["trial_mode"] != "jump":
            continue
        left, right = (reports[r][point["id"]] for r in (60, 120))
        differences = []
        for index, row in enumerate(left["trace"]):
            # Align state at the end of each physics step, not its input sample time.
            other = right["trace"][index * 2 + 1]
            distance = math.dist(row["position"], other["position"])
            if distance > 0.1:
                differences.append(
                    dict(end_time=row["time"] + 1 / 60, distance=distance)
                )
        summary["cross_rate"].append(
            dict(
                case=point["parent_case"],
                variant=point["ablation"],
                first_10cm_difference=differences[0] if differences else None,
                landing_position_difference=math.dist(
                    left["landing"]["position"], right["landing"]["position"]
                )
                if left["landing"] and right["landing"]
                else None,
                landing_time_difference=abs(
                    left["landing"]["time"] - right["landing"]["time"]
                )
                if left["landing"] and right["landing"]
                else None,
            )
        )
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=(
            "freeze",
            "verify",
            "freeze-edge",
            "verify-edge",
            "freeze-queue",
            "verify-queue",
        ),
    )
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode in ("freeze", "freeze-edge", "freeze-queue"):
        source, output = args.paths
        frozen = (
            queued_payload(source, args.project)
            if args.mode == "freeze-queue"
            else edge_payload(source, args.project)
            if args.mode == "freeze-edge"
            else payload(source, args.project)
        )
        freeze(output, frozen, (source,))
        print("LANDING_STAGE_STUDY_FROZEN", sha(output))
    else:
        directory, source, source_directory, output = args.paths
        if args.mode == "verify-queue":
            result = verify_edge(
                directory, source, source_directory, args.project, queued=True
            )
        else:
            result = (verify_edge if args.mode == "verify-edge" else verify)(
                directory, source, source_directory, args.project
            )
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("LANDING_STAGE_AUDIT_OK trials=", result["trials"])
