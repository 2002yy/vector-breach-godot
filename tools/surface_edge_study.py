"""Bind surface-seeded Dust II trials to geometry survey and a pre-holdout lock."""

import argparse
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked, grid_payload, selected_payload
from movement_dimension_gates import action_gate
from native_jump_candidates import freeze
from ordinary_edge_actions import edge_context
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

PROBE = "tools/authoring/survey_surface_edges.gd"


def make_grid(source, survey_path, project, rejection):
    survey, parent = read(survey_path), read(source)
    require(
        survey["parent_sha256"] == sha(source)
        and survey["identity"] == parent["identity"]
        and survey["survey_sha256"] == sha(project / PROBE)
        and survey["formal_qualification"] is False
        and survey["surface_accessibility"] == "unproven",
        "surface survey provenance or acceptance changed",
    )
    require(0 < len(survey["candidates"]) <= 8, "bounded nonempty survey required")
    require(
        survey["policy"]
        == dict(
            column_limit=1024,
            candidate_limit=8,
            offsets=[-2, -1, 0, 1, 2],
            distances=[0.8, 1.2, 1.6],
            goal_ray_up=0.15,
        ),
        "surface sampling policy changed",
    )
    require(0 < survey["diagnostics"]["columns"] <= 1024, "column bound exceeded")
    for record in survey["candidates"]:
        sweep = record["horizontal_sweep"]
        require(
            sweep["radius"] == 0.4
            and sweep["height"] == 1.8
            and sweep["clearance"] == 0.04
            and sweep["free_fraction"] >= 0.999
            and sweep["distance"] in (0.8, 1.2, 1.6)
            and record["surface_accessibility"] == "unproven",
            "wrong body sweep or unsupported surface accessibility",
        )
    grid = grid_payload(source, project, rejection, records=survey["candidates"])
    for point in grid["cases"]:
        point["source_surface_anchor"] = point.pop("source_nav_node")
    return dict(
        grid,
        surface_survey_sha256=sha(survey_path),
        surface_accessibility="unproven",
        input_surface="placed_not_approach_verified",
    )


def verify(directory, source, project):
    grid = directory / "grid-v1.json"
    survey = directory / "surface-survey.json"
    grid_report = directory / "grid-60.json"
    selected = directory / "selected-v1.json"
    lock = directory / "selection-lock.json"
    require(
        read(grid) == make_grid(source, survey, project, directory / "rejected.json"),
        "frozen surface grid changed",
    )
    choice = selected_payload(grid, grid_report, project)
    require(
        read(selected) == choice and read(lock) == {"selected_sha256": sha(selected)},
        "selection not bound to Current60 and lock",
    )
    result: dict[str, Any] = dict(
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        edge_lip_timing_accepted=False,
        human_acceptance=False,
        surface_accessibility="unproven",
        route_status="not_requalified",
        selected=choice["selected"],
        observations=choice["observations"],
        exploration_trials=len(read(grid_report)["results"]),
        replay_trials=0,
        results=[],
        evidence_sha256={
            p.name: sha(p) for p in (grid, survey, grid_report, selected, lock)
        },
        parent_sha256=sha(source),
        checker_sha256=sha(Path(__file__)),
    )
    if choice["selected"] is None:
        require(not choice["cases"], "empty selection contains replay cases")
        return result
    reports = {}
    for rate in (60, 120):
        path = directory / f"replay-{rate}.json"
        _, reports[rate] = checked(selected, path, rate, project)
        result["evidence_sha256"][path.name] = sha(path)
        result["replay_trials"] += len(reports[rate])
    baseline = {r["id"]: r for r in read(grid_report)["results"]}
    for point in choice["cases"]:
        key = point["id"]
        if point["scheme"] == "current":
            require_unchanged_current(baseline[key], reports[60][key])
        if point["trial_mode"] != "jump":
            continue
        parent, scheme = point["parent_case"], point["scheme"]
        result["results"].append(
            dict(
                scheme=scheme,
                actions={
                    str(r): action_gate(point, reports[r][key], r) for r in (60, 120)
                },
                drop_context={
                    str(r): edge_context(
                        point, reports[r][f"{parent}__{scheme}__no_jump"]
                    )
                    for r in (60, 120)
                },
            )
        )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "select", "verify"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(
            args.directory / "grid-v1.json",
            make_grid(
                args.source,
                args.directory / "surface-survey.json",
                args.project,
                args.directory / "rejected.json",
            ),
        )
    elif args.mode == "select":
        path = args.directory / "selected-v1.json"
        freeze(
            path,
            selected_payload(
                args.directory / "grid-v1.json",
                args.directory / "grid-60.json",
                args.project,
            ),
        )
        freeze(args.directory / "selection-lock.json", {"selected_sha256": sha(path)})
    else:
        if args.out is None:
            parser.error("--out required")
        freeze(
            args.out,
            verify(args.directory, args.source, args.project),
            tuple(args.directory.glob("*.json")) + (args.source,),
        )
    print("SURFACE_EDGE_STUDY_OK", args.mode)
