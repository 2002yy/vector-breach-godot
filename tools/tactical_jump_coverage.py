"""Candidate coverage is evidence-bound and remains separate from full-map acceptance."""

import argparse
import copy
import json
from pathlib import Path

from build_native_route_study import SCHEMES, read, sha
from validate_mirage_input_study import PHYSICS_FIELDS
from map_jump_qualification import clear_corridor
from native_jump_candidates import RUNTIME, check_report, freeze
from validate_native_route_study import require

MAPS = ("dust2", "mirage", "inferno")


def matrix_payload(source_path):
    source = read(source_path)
    require(
        source["schema"] == 4 and source["formal_qualification"] is False,
        "matrix cannot grant formal qualification",
    )
    require(
        source["cases"] and all(p["scheme"] == "current" for p in source["cases"]),
        "matrix source must be Current-only",
    )
    groups = {}
    for point in source["cases"]:
        groups.setdefault(point["parent_case"], []).append(point["trial_mode"])
    require(
        all(sorted(modes) == ["jump", "no_jump", "walk"] for modes in groups.values()),
        "source needs exactly one jump and two walking controls per point",
    )
    cases = []
    for point in source["cases"]:
        for scheme in SCHEMES:
            row = copy.deepcopy(point)
            row.update(id=scheme + "__" + point["id"], scheme=scheme)
            cases.append(row)
    require(len({p["id"] for p in cases}) == len(cases), "duplicate source identifiers")
    return dict(
        source,
        stage="same_inputs_all_profiles",
        source_manifest_sha256=sha(source_path),
        cases=cases,
    )


def require_unchanged_current(before, after):
    fields = (*PHYSICS_FIELDS, "native_command", "yaw")
    require(
        [[r[k] for k in fields] for r in before["trace"]]
        == [[r[k] for k in fields] for r in after["trace"]],
        "Current physical/input trace changed",
    )


def verify_matrix(directory, source_directory, project, approaches=False):
    summary = dict(
        formal_release_ready=False,
        same_inputs_all_profiles=True,
        current_traces_unchanged=True,
        trials=0,
        results=[],
        first_landing_passes={s: 0 for s in SCHEMES},
        jump_trials={s: 0 for s in SCHEMES},
        control_trials={s: 0 for s in SCHEMES},
        control_arrivals={s: 0 for s in SCHEMES},
    )
    for name in ("mirage", "inferno") if approaches else MAPS:
        source_path = source_directory / (
            f"{name}-approaches-v1.json" if approaches else f"{name}-candidates-v1.json"
        )
        path = directory / (
            f"{name}-approach-matrix-v1.json"
            if approaches
            else f"{name}-matrix-v1.json"
        )
        manifest = read(path)
        require(
            manifest == matrix_payload(source_path),
            "matrix geometry/inputs/source changed",
        )
        source_cases = read(source_path)["cases"]
        for rate in (60, 120):
            report_path = directory / (
                f"{name}-approach-matrix-{rate}.json"
                if approaches
                else f"{name}-{rate}.json"
            )
            results = check_report(path, report_path, rate, project)
            baseline_path = source_directory / (
                f"{name}-approaches-{rate}.json"
                if approaches
                else f"{name}-{rate}.json"
            )
            check_report(source_path, baseline_path, rate, project)
            baseline = {r["id"]: r for r in read(baseline_path)["results"]}
            rows = {r["id"]: r for r in read(report_path)["results"]}
            summary["trials"] += len(results)
            for point in source_cases:
                current = rows["current__" + point["id"]]
                require_unchanged_current(baseline[point["id"]], current)
            for point in manifest["cases"]:
                result = results[point["id"]]
                if point["trial_mode"] == "jump":
                    summary["jump_trials"][point["scheme"]] += 1
                    summary["first_landing_passes"][point["scheme"]] += int(
                        result["first_landing"]
                    )
                else:
                    summary["control_trials"][point["scheme"]] += 1
                    summary["control_arrivals"][point["scheme"]] += int(
                        result["supported_arrival"]
                    )
                summary["results"].append(
                    dict(
                        map=name,
                        case=point["parent_case"],
                        scheme=point["scheme"],
                        mode=point["trial_mode"],
                        physics_hz=rate,
                        **result,
                    )
                )
    return summary


def approach_payload(source_path):
    source = read(source_path)
    require(
        all(p["scheme"] == "current" for p in source["cases"]),
        "approach source must be Current-only",
    )
    cases = []
    for original in source["cases"]:
        if original["trial_mode"] != "jump":
            continue
        for mode in ("jump", "no_jump", "walk"):
            point = copy.deepcopy(original)
            point.pop(
                "corridor"
            )  # The old sweep cannot certify a changed starting point.
            direction = point["geometry"]["direction"]
            point["start"] = [a - 1.2 * b for a, b in zip(point["start"], direction)]
            point.update(
                id="runup_" + original["parent_case"] + "__" + mode,
                parent_case="runup_" + original["parent_case"],
                kind="run_up",
                coverage_role="run_up_approach",
                trial_mode=mode,
            )
            point["native_timeline"] = [
                dict(at=t, keys=keys, mouse_dx=0.0)
                for t, keys in (
                    (0, ["W"]),
                    (0.35, ["W", "Space"]),
                    (0.35 + 2 / 60, ["W", "Space", "Ctrl"]),
                    (0.45, ["W", "Ctrl"]),
                    (1.5, ["Ctrl"]),
                )
            ]
            point["timeline"] = [
                dict(at=0, direction=[0, -1], crouch=False),
                dict(at=0.35, jump=True),
                dict(at=0.35 + 2 / 60, crouch=True),
                dict(at=0.45, jump=False),
                dict(at=1.5, direction=[0, 0]),
            ]
            for event in point["native_timeline"]:
                if mode != "jump":
                    event["keys"] = [k for k in event["keys"] if k != "Space"]
                if mode == "walk":
                    event["keys"] = [k for k in event["keys"] if k != "Ctrl"] + [
                        "Shift"
                    ]
            cases.append(point)
    return dict(
        source,
        stage="new_1p2m_runup_requires_fresh_corridor",
        source_manifest_sha256=sha(source_path),
        cases=cases,
    )


def verify_approaches(directory, source_directory, project):
    summary = dict(
        formal_release_ready=False, reference_profile="current", trials=0, points=[]
    )
    for name in ("mirage", "inferno"):
        source = source_directory / f"{name}-candidates-v1.json"
        path = directory / f"{name}-approaches-v1.json"
        manifest = read(path)
        require(manifest == approach_payload(source), "approach inputs/source changed")
        reports = {
            rate: check_report(
                path, directory / f"{name}-approaches-{rate}.json", rate, project
            )
            for rate in (60, 120)
        }
        proofs = {}
        for rate in (60, 120):
            proof = read(directory / f"{name}-corridor-{rate}.json")
            proof_path = directory / f"{name}-corridor-source-v1.json"
            require(
                read(proof_path)
                == dict(
                    manifest,
                    cases=[p for p in manifest["cases"] if p["trial_mode"] == "jump"],
                    source_matrix_sha256=sha(path),
                ),
                "fresh corridor input changed",
            )
            require(
                proof["manifest_sha256"] == sha(proof_path)
                and proof["identity"] == manifest["identity"]
                and proof["physics_hz"] == rate,
                "new body corridor provenance mismatch",
            )
            expected = {p["id"] for p in manifest["cases"] if p["trial_mode"] == "jump"}
            require(
                len(proof["points"]) == len(expected)
                and {p["case"] for p in proof["points"]} == expected,
                "missing/duplicate fresh body corridors",
            )
            proofs[rate] = {p["case"]: p for p in proof["points"]}
        summary["trials"] += sum(len(r) for r in reports.values())
        for point in manifest["cases"]:
            if point["trial_mode"] != "jump":
                continue
            corridors = {
                rate: clear_corridor(point, proofs[rate][point["id"]]["corridor"])
                for rate in (60, 120)
            }
            jumping = {
                rate: reports[rate][point["id"]]["first_landing"] for rate in (60, 120)
            }
            walking = {
                rate: any(
                    reports[rate][point["parent_case"] + "__" + mode][
                        "supported_arrival"
                    ]
                    for mode in ("no_jump", "walk")
                )
                for rate in (60, 120)
            }
            summary["points"].append(
                dict(
                    map=name,
                    case=point["parent_case"],
                    status=classify(corridors, jumping, walking),
                    body_corridor_clear={
                        str(rate): corridors[rate][0] for rate in (60, 120)
                    },
                    first_landing={str(k): v for k, v in jumping.items()},
                    walking_arrival={str(k): v for k, v in walking.items()},
                )
            )
    return summary


def manifest_payload(parent_path, survey_path, project):
    parent, survey = read(parent_path), read(survey_path)
    require(
        survey["parent_sha256"] == sha(parent_path)
        and survey["identity"] == parent["identity"],
        "survey does not belong to original frozen map",
    )
    require(
        survey["formal_qualification"] is False
        and survey["survey_sha256"]
        == sha(project / "tools/authoring/survey_tactical_jumps.gd"),
        "survey code/authority changed",
    )
    cases = []
    for original in survey["cases"]:
        for mode in ("jump", "no_jump", "walk"):
            point = copy.deepcopy(original)
            point.update(
                id=original["id"] + "__" + mode,
                parent_case=original["id"],
                trial_mode=mode,
                scheme="current",
            )
            point["native_timeline"] = [
                dict(at=t, keys=keys, mouse_dx=0.0)
                for t, keys in (
                    (0, ["W"]),
                    (0.1, ["W", "Space"]),
                    (0.1 + 2 / 60, ["W", "Space", "Ctrl"]),
                    (0.2, ["W", "Ctrl"]),
                    (1.5, ["Ctrl"]),
                )
            ]
            for event in point["native_timeline"]:
                if mode != "jump":
                    event["keys"] = [k for k in event["keys"] if k != "Space"]
                if mode == "walk":
                    event["keys"] = [k for k in event["keys"] if k != "Ctrl"] + [
                        "Shift"
                    ]
            cases.append(point)
    return dict(
        schema=4,
        formal_qualification=False,
        level=parent["level"],
        identity=parent["identity"],
        parent_sha256=sha(parent_path),
        survey_sha256=sha(survey_path),
        input_map_sha256=sha(project / "project.godot"),
        runtime_sha256={"res://" + path: sha(project / path) for path in RUNTIME},
        cases=cases,
    )


def classify(corridors, jumping, walking):
    require(
        set(corridors) == set(jumping) == set(walking) == {60, 120},
        "both rates required",
    )
    if all(walking.values()) and all(c[0] for c in corridors.values()):
        return "walk_only"
    if (
        not any(walking.values())
        and all(c[0] for c in corridors.values())
        and all(jumping.values())
    ):
        return "qualified_jump"
    if not any(walking.values()) and all(c[1] for c in corridors.values()):
        return "blocked_direct_route"
    return "route_unproven"


def inventory(original_review):
    rows = original_review["points"]
    expected = {
        (name, kind)
        for name in MAPS
        for kind in ("ordinary", "critical_landing", "edge", "run_up", "crouch_jump")
    }
    require(
        len(rows) == 15 and {(r["map"], r["case"]) for r in rows} == expected,
        "original category inventory incomplete",
    )
    return [
        {
            "map": r["map"],
            "category": r["case"],
            "original_status": r["status"],
            "jump_route_covered": r["status"] == "qualified_jump",
            "mechanics_or_walk_reference_only": r["status"] == "walk_only",
        }
        for r in rows
    ]


def verify(directory, parents, review_path, project):
    output = dict(
        formal_release_ready=False,
        all_map_coverage_complete=False,
        original_review_sha256=sha(review_path),
        original_inventory=inventory(read(review_path)),
        input_kind="synthetic InputMap Current reference, not human acceptance",
        points=[],
        bounded_gap_search=[],
        trial_count=0,
    )
    for name in MAPS:
        parent_path = parents / f"{name}-manifest.json"
        survey_path = directory / f"{name}-survey.json"
        manifest_path = directory / f"{name}-candidates-v1.json"
        survey, manifest = read(survey_path), read(manifest_path)
        require(
            manifest == manifest_payload(parent_path, survey_path, project),
            "candidate inputs changed",
        )
        outputs = {
            rate: check_report(
                manifest_path, directory / f"{name}-{rate}.json", rate, project
            )
            for rate in (60, 120)
        }
        output["trial_count"] += sum(len(rows) for rows in outputs.values())
        for point in survey["cases"]:
            corridor = clear_corridor(point, point["corridor"])
            jumping = {
                rate: outputs[rate][point["id"] + "__jump"]["first_landing"]
                for rate in (60, 120)
            }
            walking = {
                rate: any(
                    outputs[rate][point["id"] + "__" + mode]["supported_arrival"]
                    for mode in ("no_jump", "walk")
                )
                for rate in (60, 120)
            }
            status = classify({60: corridor, 120: corridor}, jumping, walking)
            output["points"].append(
                dict(
                    map=name,
                    case=point["id"],
                    role=point["coverage_role"],
                    objective_distance=point["objective_distance"],
                    body_corridor_clear=corridor[0],
                    status=status,
                    jump_first_landing={str(k): v for k, v in jumping.items()},
                    walking_arrival={str(k): v for k, v in walking.items()},
                    later_jump_arrival={
                        str(rate): outputs[rate][point["id"] + "__jump"][
                            "supported_arrival"
                        ]
                        for rate in (60, 120)
                    },
                )
            )
        output["bounded_gap_search"].append(
            dict(
                map=name,
                nodes_examined=survey["nodes_examined"],
                gap_found=survey["gap_found"],
                policy=survey["scan_policy"],
                whole_map_exhaustive=False,
            )
        )
    output["qualified_new_points"] = sum(
        p["status"] == "qualified_jump" for p in output["points"]
    )
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=(
            "freeze",
            "verify",
            "matrix",
            "verify-matrix",
            "verify-approach-matrix",
            "approaches",
            "verify-approaches",
        ),
    )
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode == "freeze":
        parent, survey, output = args.paths
        freeze(output, manifest_payload(parent, survey, args.project), (parent, survey))
        print("TACTICAL_CANDIDATES_FROZEN", sha(output))
    elif args.mode == "matrix":
        source, output = args.paths
        freeze(output, matrix_payload(source), (source,))
        print("TACTICAL_MATRIX_FROZEN", sha(output))
    elif args.mode in ("verify-matrix", "verify-approach-matrix"):
        directory, source_directory, output = args.paths
        data = verify_matrix(
            directory,
            source_directory,
            args.project,
            approaches=args.mode == "verify-approach-matrix",
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print("TACTICAL_MATRIX_VERIFIED", data["trials"], data["first_landing_passes"])
    elif args.mode == "approaches":
        source, output = args.paths
        freeze(output, approach_payload(source), (source,))
        print("TACTICAL_APPROACHES_FROZEN", sha(output))
    elif args.mode == "verify-approaches":
        directory, source_directory, output = args.paths
        data = verify_approaches(directory, source_directory, args.project)
        output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print("TACTICAL_APPROACHES_VERIFIED", data["trials"], data["points"])
    else:
        directory, parents, review, output = args.paths
        data = verify(directory, parents, review, args.project)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(
            "TACTICAL_COVERAGE_VERIFIED trials=",
            data["trial_count"],
            "new_qualified=",
            data["qualified_new_points"],
        )
