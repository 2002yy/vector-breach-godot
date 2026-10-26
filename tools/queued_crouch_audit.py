"""Replay frozen historical crouch inputs with queued cadence and standing controls."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from map_jump_qualification import clear_corridor
from movement_corridor_provenance import (
    attach,
    evaluate as prior_evaluate,
    input_lock,
    load_channels,
)
from movement_dimension_gates import action_gate, route_gate
from movement_evidence_bank import LEVELS, coverage, geometry_matches, paired_timeline
from native_jump_candidates import RUNTIME, freeze, outcomes
from queued_three_map_audit import CADENCE_PROBES, PROBES, QUEUE_PROBES
from validate_native_route_study import require

MODES = ("jump", "no_jump", "walk")


def payload(source_path, project, rejection):
    source = read(source_path)
    require(
        source.get("schema") == 4
        and source.get("formal_qualification") is False
        and not source.get("camera_only"),
        "physical source required",
    )
    parents = [
        p
        for p in source["cases"]
        if p["kind"] == "crouch_jump" and p["trial_mode"] == "jump"
    ]
    require(
        len(parents) == 3 and {p["scheme"] for p in parents} == set(SCHEMES),
        "exactly three crouch profiles required",
    )
    require(
        all(geometry_matches(parents[0], p) for p in parents),
        "profile geometries differ",
    )
    hashes = {
        "res://" + p: sha(project / p)
        for p in (*PROBES, *QUEUE_PROBES, *CADENCE_PROBES)
    }
    cases = []
    for parent in parents:
        require(
            any("Space" in e["keys"] for e in parent["native_timeline"])
            and any("Ctrl" in e["keys"] for e in parent["native_timeline"]),
            "source lacks jump/crouch inputs",
        )
        for mode in MODES:
            point = copy.deepcopy(parent)
            timeline = point["native_timeline"]
            if mode != "jump":
                for event in timeline:
                    event["keys"] = [
                        k
                        for k in event["keys"]
                        if k != "Space" and not (mode == "walk" and k == "Ctrl")
                    ]
                    if mode == "walk" and "Shift" not in event["keys"]:
                        event["keys"].append("Shift")
            point.update(
                id=f"crouch__{parent['scheme']}__{mode}",
                source_case=parent["id"],
                parent_case="crouch_jump",
                trial_mode=mode,
                queued_input=True,
                ablation="baseline",
                enforce_cadence=True,
                rejection_path=str(rejection),
                probe_sha256=hashes,
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


def posture(row):
    trace = row["trace"]
    for sample in trace:
        height = sample["capsule_height"]
        require(
            type(sample["crouching"]) is bool
            and type(height) in (int, float)
            and math.isfinite(height)
            and abs(height - (1.2 if sample["crouching"] else 1.8)) < 1e-5,
            "capsule height contradicts physical posture",
        )
    return dict(
        crouched_in_air=any(
            s["input"]["crouch"] and s["crouching"] and not s["grounded_after"]
            for s in trace
        ),
        standing_throughout=all(
            not s["crouching"] and not s["input"]["crouch"] for s in trace
        ),
        capsule_heights=sorted({round(s["capsule_height"], 5) for s in trace}),
    )


def profile(point, rows, control_points, controls, proofs):
    require(
        all(paired_timeline(point, control_points[m], m) for m in ("no_jump", "walk")),
        "controls must match jump geometry and input timeline",
    )
    actions, landings, walking, body, poses = {}, {}, {}, {}, {}
    for rate in (60, 120):
        poses[rate] = posture(rows[rate])
        for m in ("no_jump", "walk"):
            pose = posture(controls[rate][m])
            if m == "walk":
                require(
                    pose["standing_throughout"], "walk control did not remain standing"
                )
        actions[rate] = action_gate(point, rows[rate], rate)
        actions[rate]["passed"] &= poses[rate]["crouched_in_air"]
        landings[rate] = outcomes(point, rows[rate])["first_landing"]
        walking[rate] = {
            m: outcomes(control_points[m], controls[rate][m])["supported_arrival"]
            for m in ("no_jump", "walk")
        }
        body[rate] = clear_corridor(point, proofs[rate])
    gate = route_gate(body, actions, landings, walking)
    contacts = {r: rows[r].get("landing") for r in (60, 120)}
    frequency_delta = None
    if all(contacts.values()):
        frequency_delta = dict(
            position_metres=math.dist(
                contacts[60]["position"], contacts[120]["position"]
            ),
            time_seconds=abs(contacts[60]["time"] - contacts[120]["time"]),
            vertical_metres=abs(
                contacts[60]["position"][1] - contacts[120]["position"][1]
            ),
            precision_accepted=False,
        )
    return dict(
        source_case=point["id"],
        scheme=point["scheme"],
        category_action_passed=all(a["passed"] for a in actions.values()),
        actions={str(r): a for r, a in actions.items()},
        first_landings={str(r): v for r, v in landings.items()},
        postures={str(r): v for r, v in poses.items()},
        controls={str(r): v for r, v in walking.items()},
        body_envelope_available=True,
        paired_controls_available=True,
        cross_frequency_first_landing=frequency_delta,
        **gate,
    )


def evaluate(directory, source_config, project) -> dict[str, Any]:
    require(
        read(directory / "matrix-lock.json")
        == matrix_lock(directory, source_config, project),
        "matrix or source lock changed",
    )
    config = read(source_config)
    baseline = prior_evaluate(config, project)
    sites = copy.deepcopy(baseline["sites"])
    sources, results = {}, []
    for name, level in LEVELS.items():
        parent = Path(config["historical"][name]["manifest"])
        path = directory / f"{name}-queued-v1.json"
        manifest = read(path)
        require(
            manifest == payload(parent, project, directory / f"{name}-rejected.json"),
            "frozen crouch inputs or source changed",
        )
        require(manifest["level"] == level, "map label mismatch")
        reports = {r: directory / f"{name}-{r}.json" for r in (60, 120)}
        rows = {}
        for rate in (60, 120):
            points, rows[rate] = checked(path, reports[rate], rate, project)
        source = config["corridors"][name]
        old, channels = load_channels(
            Path(source["manifest"]),
            {r: Path(source[f"report{r}"]) for r in (60, 120)},
            level,
            manifest["identity"],
        )
        profiles = {}
        for scheme in SCHEMES:
            point = points[f"crouch__{scheme}__jump"]
            recovered = attach(point, old["cases"], channels)
            require(recovered is not None, "missing exact crouch body corridor")
            assert recovered is not None
            control_points = {
                m: points[f"crouch__{scheme}__{m}"] for m in ("no_jump", "walk")
            }
            profiles[scheme] = profile(
                point,
                {r: rows[r][point["id"]] for r in (60, 120)},
                control_points,
                {
                    r: {m: rows[r][p["id"]] for m, p in control_points.items()}
                    for r in (60, 120)
                },
                recovered[1],
            )
        site = dict(
            map=name,
            site="crouch__queued_original_geometry",
            kind="crouch_jump",
            profiles=profiles,
            human_review="pending",
            precision_accepted=False,
            spawn_connectivity="unproven",
        )
        sites.append(site)
        results.append(site)
        sources[name] = dict(
            manifest_sha256=sha(path),
            parent_sha256=sha(parent),
            reports={str(r): sha(p) for r, p in reports.items()},
        )
    categories = coverage(sites)
    return dict(
        schema=1,
        source_config_sha256=sha(source_config),
        baseline_records_revalidated=576,
        new_native_trials=54,
        sites=results,
        combined_category_coverage=categories,
        action_categories=sum(c["action_covered"] for c in categories),
        jump_route_categories=sum(c["jump_route_covered"] for c in categories),
        sources=sources,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        scope="queued_synthetic_InputMap_crouch_envelope_not_human_or_crouch_necessity",
    )


def matrix_lock(directory, source_config, project):
    return dict(
        schema=1,
        source_inputs=input_lock(source_config, project),
        manifests={n: sha(directory / f"{n}-queued-v1.json") for n in LEVELS},
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source_config", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        config = read(args.source_config)
        for name in LEVELS:
            freeze(
                args.directory / f"{name}-queued-v1.json",
                payload(
                    Path(config["historical"][name]["manifest"]),
                    args.project,
                    args.directory / f"{name}-rejected.json",
                ),
            )
        freeze(
            args.directory / "matrix-lock.json",
            matrix_lock(args.directory, args.source_config, args.project),
        )
    else:
        summary = evaluate(args.directory, args.source_config, args.project)
        freeze(args.out or args.directory / "validated-summary.json", summary)
        print(
            "QUEUED_CROUCH_VERIFIED",
            summary["new_native_trials"],
            summary["action_categories"],
            summary["jump_route_categories"],
        )


if __name__ == "__main__":
    main()
