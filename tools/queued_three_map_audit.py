"""Bind three-map queued comparisons to observed cadence, not declared frame rate."""

import argparse
import copy
import json
import math
from pathlib import Path

from build_native_route_study import SCHEMES, read, sha
from landing_stage_audit import PROBES, QUEUE_PROBES
from native_jump_candidates import check_report, freeze
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

CADENCE_PROBES = (
    "tools/authoring/QueueCadenceProbePlayer.gd",
    "tools/authoring/audit_queue_cadence.gd",
)
MAPS = ("dust2", "mirage", "inferno")


def payload(source_path, project, rejection_path):
    source = read(source_path)
    require(
        source["schema"] == 4
        and source["formal_qualification"] is False
        and not source.get("camera_only"),
        "physical source required",
    )
    parents = {p["parent_case"] for p in source["cases"]}
    expected = {
        (p, s, m) for p in parents for s in SCHEMES for m in ("jump", "no_jump", "walk")
    }
    require(
        parents
        and len(source["cases"]) == len(expected)
        and {(p["parent_case"], p["scheme"], p["trial_mode"]) for p in source["cases"]}
        == expected
        and len({p["id"] for p in source["cases"]}) == len(expected),
        "incomplete source cohort",
    )
    hashes = {
        "res://" + p: sha(project / p)
        for p in (*PROBES, *QUEUE_PROBES, *CADENCE_PROBES)
    }
    cases = []
    for original in source["cases"]:
        for queued in (False, True):
            point = copy.deepcopy(original)
            point.update(
                id=("queued__" if queued else "native__") + original["id"],
                source_case=original["id"],
                queued_input=queued,
                ablation="baseline",
                enforce_cadence=queued,
                rejection_path=str(rejection_path),
                probe_sha256=hashes,
            )
            cases.append(point)
    return dict(
        source,
        cases=cases,
        source_manifest_sha256=sha(source_path),
        diagnostic_only=True,
        cadence_policy="one_process_frame_per_physics_sample_after_initial_tick",
        native_acceptance=False,
    )


def check_cadence(row, point):
    require(row["trace"][0]["probe_sha256"] == point["probe_sha256"], "probe drift")
    require(row["queued_input"] == point["queued_input"], "producer mode changed")
    if not point["queued_input"]:
        return
    for index, sample in enumerate(row["trace"]):
        cadence = sample["cadence"]
        require(
            cadence["tick"] == index and cadence["violation"] is False,
            "observed unsupported cadence",
        )
        if index:
            require(
                cadence["process_delta"] == 1
                and cadence["prequeued"]
                and cadence["inline_events"] == 0,
                "queued sample used inline fallback or unsupported process ratio",
            )
        if sample["input"]["jump"]:
            require(
                abs(sample["jump_requested_time"] - sample["time"]) < 1e-6,
                "jump did not consume at the intended queued boundary",
            )


def verify(directory, sources, project):
    result = dict(
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        historical_traces_unchanged=True,
        trials=0,
        jump_results=[],
        scores=[],
        cross_rate=[],
    )
    for name in MAPS:
        source_path = sources / f"{name}-matrix-v1.json"
        path = directory / f"{name}-queued-v1.json"
        manifest = read(path)
        require(
            manifest
            == payload(source_path, project, directory / f"{name}-rejected.json"),
            "frozen cohort changed",
        )
        cases = {p["id"]: p for p in manifest["cases"]}
        reports = {}
        counts = {
            (q, s): dict(
                jump_passes=0, jump_trials=0, control_arrivals=0, control_trials=0
            )
            for q in (False, True)
            for s in SCHEMES
        }
        for rate in (60, 120):
            output_path = directory / f"{name}-{rate}.json"
            outcomes = check_report(path, output_path, rate, project)
            baseline_path = sources / f"{name}-{rate}.json"
            check_report(source_path, baseline_path, rate, project)
            baseline = {r["id"]: r for r in read(baseline_path)["results"]}
            rows = {r["id"]: r for r in read(output_path)["results"]}
            reports[rate] = rows
            result["trials"] += len(rows)
            for key, point in cases.items():
                row, outcome = rows[key], outcomes[key]
                check_cadence(row, point)
                if not point["queued_input"]:
                    require_unchanged_current(baseline[point["source_case"]], row)
                score = counts[(point["queued_input"], point["scheme"])]
                if point["trial_mode"] == "jump":
                    score["jump_passes"] += int(outcome["first_landing"])
                    score["jump_trials"] += 1
                    result["jump_results"].append(
                        dict(
                            map=name,
                            case=point["parent_case"],
                            scheme=point["scheme"],
                            queued=point["queued_input"],
                            physics_hz=rate,
                            **outcome,
                        )
                    )
                else:
                    score["control_arrivals"] += int(outcome["supported_arrival"])
                    score["control_trials"] += 1
        result["scores"] += [
            dict(map=name, queued=q, scheme=s, **score)
            for (q, s), score in counts.items()
        ]
        for key, point in cases.items():
            if not point["queued_input"] or point["trial_mode"] != "jump":
                continue
            left, right = (reports[r][key] for r in (60, 120))
            result["cross_rate"].append(
                dict(
                    map=name,
                    case=point["parent_case"],
                    scheme=point["scheme"],
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
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode == "freeze":
        source, out, rejection = args.paths
        freeze(out, payload(source, args.project, rejection), (source,))
        print("QUEUED_MAP_STUDY_FROZEN", sha(out))
    else:
        directory, sources, out = args.paths
        summary = verify(directory, sources, args.project)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print("QUEUED_MAP_VERIFY_OK", summary["trials"])
