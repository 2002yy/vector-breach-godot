"""Candidate coverage is evidence-bound and remains separate from full-map acceptance."""

import argparse
import copy
import json
from pathlib import Path

from build_native_route_study import read, sha
from map_jump_qualification import clear_corridor
from native_jump_candidates import RUNTIME, check_report, freeze
from validate_native_route_study import require

MAPS = ("dust2", "mirage", "inferno")


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
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode == "freeze":
        parent, survey, output = args.paths
        freeze(output, manifest_payload(parent, survey, args.project), (parent, survey))
        print("TACTICAL_CANDIDATES_FROZEN", sha(output))
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
