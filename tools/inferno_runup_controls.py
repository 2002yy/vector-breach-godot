"""Bounded controls for fountain-rim overshoot; original inputs/results stay frozen."""

import argparse
import copy
import json
from pathlib import Path

from build_native_route_study import read, sha
from native_jump_candidates import check_report, freeze
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

VARIANTS = ("baseline", "jump_025", "crouch_with_jump", "air_brake_060_085")


def study_payload(source_path):
    source = read(source_path)
    require(
        source["schema"] == 4 and source["formal_qualification"] is False,
        "source cannot grant formal authority",
    )
    require(source["level"] == "inferno-classic-local", "Inferno study only")
    require(
        not source.get("camera_only", False),
        "diagnostic camera poses are not physical starts",
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
        "source must retain two points, all profiles and all controls",
    )
    cases = []
    for original in source["cases"]:
        if original["scheme"] != "modern_cs" or original["trial_mode"] != "jump":
            continue
        for variant in VARIANTS:
            for mode in ("jump", "no_jump", "walk"):
                point = copy.deepcopy(original)
                point.update(
                    id=f"{original['parent_case']}__{variant}__{mode}",
                    trial_mode=mode,
                    variant=variant,
                )
                if variant == "jump_025":
                    for event in point["native_timeline"] + point["timeline"]:
                        if 0.35 - 1e-6 <= event["at"] < 0.5:
                            event["at"] -= 0.1
                elif variant == "crouch_with_jump":
                    point["native_timeline"][1]["keys"].append("Ctrl")
                    for event in point["timeline"]:
                        if event.get("crouch") is True:
                            event["at"] = 0.35
                elif variant == "air_brake_060_085":
                    point["native_timeline"] += [
                        dict(at=0.6, keys=["S", "Ctrl"], mouse_dx=0.0),
                        dict(at=0.85, keys=["W", "Ctrl"], mouse_dx=0.0),
                    ]
                    point["timeline"] += [
                        dict(at=0.6, direction=[0, 1]),
                        dict(at=0.85, direction=[0, -1]),
                    ]
                point["native_timeline"].sort(key=lambda e: e["at"])
                point["timeline"].sort(key=lambda e: e["at"])
                for event in point["native_timeline"]:
                    if mode != "jump":
                        event["keys"] = [k for k in event["keys"] if k != "Space"]
                    if mode == "walk":
                        event["keys"] = [k for k in event["keys"] if k != "Ctrl"] + [
                            "Shift"
                        ]
                cases.append(point)
    require(
        len(cases) == 24 and len({p["id"] for p in cases}) == 24,
        "two points/four variants/three modes required",
    )
    return dict(
        source,
        cases=cases,
        stage="bounded_modern_controls",
        source_manifest_sha256=sha(source_path),
        baseline_selection_eligible=False,
        selection_hz=60,
    )


def choose(study, results):
    selected = {}
    for point in study["cases"]:
        if point["trial_mode"] != "jump" or point["variant"] == "baseline":
            continue
        prefix = point["id"].removesuffix("jump")
        if (
            point["parent_case"] not in selected
            and results[point["id"]]["first_landing"]
            and not any(
                results[prefix + mode]["supported_arrival"]
                for mode in ("no_jump", "walk")
            )
        ):
            selected[point["parent_case"]] = point["variant"]
    return selected


def selected_payload(source_path, study_path, discovery_path, project):
    source, study = read(source_path), read(study_path)
    require(study == study_payload(source_path), "frozen study changed")
    results = check_report(study_path, discovery_path, 60, project)
    choices = choose(study, results)
    expected = {p["parent_case"] for p in study["cases"]}
    require(choices.keys() == expected, "some point has no successful new control")
    index = {
        (p["parent_case"], p["variant"], p["trial_mode"]): p for p in study["cases"]
    }
    cases = []
    for original in source["cases"]:
        if original["scheme"] == "modern_cs":
            point = copy.deepcopy(
                index[
                    (
                        original["parent_case"],
                        choices[original["parent_case"]],
                        original["trial_mode"],
                    )
                ]
            )
            point["id"] = original["id"]
        else:
            point = copy.deepcopy(original)
        cases.append(point)
    return dict(
        source,
        cases=cases,
        stage="per_profile_selected_controls",
        source_manifest_sha256=sha(source_path),
        study_sha256=sha(study_path),
        discovery_sha256=sha(discovery_path),
        choices=choices,
        same_inputs_all_profiles=False,
    )


def verify(directory, source_path, source_directory, project):
    study_path, selected_path = (
        directory / "study-v1.json",
        directory / "selected-v1.json",
    )
    require(
        read(study_path) == study_payload(source_path), "study source/inputs changed"
    )
    discovery = directory / "study-60.json"
    require(
        read(selected_path)
        == selected_payload(source_path, study_path, discovery, project),
        "selection changed",
    )
    study_results = check_report(study_path, discovery, 60, project)
    baseline_60 = {
        r["id"]: r
        for r in read(source_directory / "inferno-approach-matrix-60.json")["results"]
    }
    study_rows = {r["id"]: r for r in read(discovery)["results"]}
    for point in read(study_path)["cases"]:
        if point["variant"] == "baseline":
            reference_id = (
                "modern_cs__" + point["parent_case"] + "__" + point["trial_mode"]
            )
            require_unchanged_current(
                baseline_60[reference_id], study_rows[point["id"]]
            )
    selected = read(selected_path)
    summary = dict(
        formal_release_ready=False,
        same_inputs_all_profiles=False,
        selection_hz=60,
        new_controls_holdout_hz=120,
        choices=selected["choices"],
        reference_traces_unchanged=True,
        original_modern_baseline_reproduced_60=True,
        study_results=[
            dict(
                case=p["parent_case"],
                variant=p["variant"],
                mode=p["trial_mode"],
                **study_results[p["id"]],
            )
            for p in read(study_path)["cases"]
        ],
        results=[],
    )
    for rate in (60, 120):
        report = directory / f"selected-{rate}.json"
        results = check_report(selected_path, report, rate, project)
        baseline_path = source_directory / f"inferno-approach-matrix-{rate}.json"
        check_report(source_path, baseline_path, rate, project)
        baseline = {r["id"]: r for r in read(baseline_path)["results"]}
        rows = {r["id"]: r for r in read(report)["results"]}
        for point in selected["cases"]:
            if point["scheme"] != "modern_cs":
                require_unchanged_current(baseline[point["id"]], rows[point["id"]])
            result = results[point["id"]]
            require(
                result["first_landing"]
                if point["trial_mode"] == "jump"
                else not result["supported_arrival"],
                "selected control failed holdout or walking control reached",
            )
            summary["results"].append(
                dict(
                    case=point["parent_case"],
                    scheme=point["scheme"],
                    mode=point["trial_mode"],
                    physics_hz=rate,
                    **result,
                )
            )
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "select", "verify"))
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode == "freeze":
        source, output = args.paths
        freeze(output, study_payload(source), (source,))
        print("INFERNO_CONTROLS_FROZEN", sha(output))
    elif args.mode == "select":
        source, study, discovery, output = args.paths
        payload = selected_payload(source, study, discovery, args.project)
        freeze(output, payload, (source, study, discovery))
        print("INFERNO_CONTROLS_SELECTED", payload["choices"])
    else:
        directory, source, source_directory, output = args.paths
        payload = verify(directory, source, source_directory, args.project)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print("INFERNO_CONTROLS_VERIFIED", len(payload["results"]))
