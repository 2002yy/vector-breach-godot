"""Freeze a vertical-only comparison against R25 horizontal candidate evidence."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from modern_ground_quadrature import check_cache_receipt
from movement_dimension_gates import action_gate
from movement_evidence_bank import LEVELS, geometry_matches, paired_timeline
from native_jump_candidates import freeze, outcomes
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

PROBES = (
    "tools/authoring/ModernGroundQuadratureV2Player.gd",
    "tools/authoring/audit_modern_ground_quadrature_v2.gd",
    "tools/authoring/ModernVerticalQuadraturePlayer.gd",
    "tools/authoring/audit_modern_vertical_quadrature.gd",
)
MODES = ("jump", "no_jump", "walk")
VARIANTS = ("baseline", "vertical")


def source_paths(sources, name):
    directory = sources / name
    return directory / "matrix-v1.json", {
        rate: directory / f"{rate}.json" for rate in (60, 120)
    }


def selected_source(source, name):
    require(
        name in LEVELS
        and source.get("level") == LEVELS[name]
        and source.get("schema") == 4
        and source.get("formal_qualification") is False
        and not source.get("camera_only"),
        "physical source map label required",
    )
    points = [
        p for p in source["cases"] if p.get("id") in {"candidate__" + m for m in MODES}
    ]
    require(
        len(points) == 3
        and {p["trial_mode"] for p in points} == set(MODES)
        and all(
            p["scheme"] == "modern_cs"
            and p["queued_input"] is True
            and p["quadrature_enabled"] is True
            for p in points
        ),
        "complete horizontal-on Modern source controls required",
    )
    jump = next(p for p in points if p["trial_mode"] == "jump")
    require(
        all(geometry_matches(jump, p) for p in points),
        "source paired geometry changed",
    )
    require(
        all(
            paired_timeline(jump, p, p["trial_mode"])
            for p in points
            if p["trial_mode"] != "jump"
        ),
        "source paired timeline changed",
    )
    return points


def payload(name, sources, project, rejection) -> dict[str, Any]:
    source, reports = source_paths(sources, name)
    data = read(source)
    parents = selected_source(data, name)
    hashes = {"res://" + p: sha(project / p) for p in PROBES}
    cases = []
    for variant in VARIANTS:
        for parent in parents:
            for path, digest in parent["probe_sha256"].items():
                require(
                    sha(project / path.removeprefix("res://")) == digest,
                    "original producer probe drift",
                )
            point = copy.deepcopy(parent)
            point.update(
                id=variant + "__" + parent["trial_mode"],
                source_case=parent["id"],
                quadrature_enabled=True,
                vertical_enabled=variant == "vertical",
                rejection_path=str(rejection),
            )
            point["probe_sha256"].update(hashes)
            cases.append(point)
    return dict(
        data,
        cases=cases,
        stage="predeclared_vertical_only_comparison",
        vertical_source_sha256=sha(source),
        vertical_source_reports_sha256={str(r): sha(p) for r, p in reports.items()},
        diagnostic_only=True,
        native_acceptance=False,
    )


def lock(sources, directory, project):
    return dict(
        schema=1,
        matrix_sha256={
            name: sha(directory / f"{name}-matrix-v1.json") for name in LEVELS
        },
        probe_sha256={p: sha(project / p) for p in PROBES},
        sources={
            name: {
                "manifest": sha(source_paths(sources, name)[0]),
                **{str(r): sha(p) for r, p in source_paths(sources, name)[1].items()},
            }
            for name in LEVELS
        },
    )


def delta_summary(rows) -> dict[str, Any]:
    a, b = (rows[r]["landing"] for r in (60, 120))
    jumps = {
        r: [s["time"] for s in row["trace"] if s["jumped"]] for r, row in rows.items()
    }
    common = {}
    if (
        all(len(v) == 1 for v in jumps.values())
        and abs(jumps[60][0] - jumps[120][0]) < 1e-6
    ):
        for offset in (1 / 60, 0.1, 0.3):
            end = jumps[60][0] + offset
            states = {
                r: [s for s in row["trace"] if abs(s["time"] + 1 / r - end) < 1e-6]
                for r, row in rows.items()
            }
            if all(len(v) == 1 and not v[0]["grounded_after"] for v in states.values()):
                left, right = states[60][0], states[120][0]
                common[str(offset)] = dict(
                    y_delta_m=left["position"][1] - right["position"][1],
                    vertical_velocity_delta_mps=left["velocity"][1]
                    - right["velocity"][1],
                )
    return dict(
        common_air_end_states=common,
        landing_position_delta_m=math.dist(a["position"], b["position"])
        if a and b
        else None,
        landing_physics_end_delta_seconds=abs(a["time"] + 1 / 60 - b["time"] - 1 / 120)
        if a and b
        else None,
        apex_height_delta_m=max(s["position"][1] for s in rows[60]["trace"])
        - max(s["position"][1] for s in rows[120]["trace"]),
    )


def check_vertical_receipt(sample, enabled, rate):
    receipt = sample["vertical"]
    require(receipt["enabled"] is enabled, "vertical candidate toggle changed")
    require(abs(receipt["delta"] - 1 / rate) < 1e-6, "vertical receipt rate differs")
    if not enabled:
        require(receipt["phase"] == "baseline", "disabled vertical receipt changed")
        return
    require(
        receipt["phase"] in {"grounded", "postkick", "collision_reset"},
        "unknown vertical phase",
    )
    if receipt["phase"] == "grounded":
        require(
            sample["grounded_before"] and not sample["jumped"],
            "grounded receipt cannot hide an air or jump step",
        )
        return
    require(
        ("jump_impulse" in receipt) is sample["jumped"],
        "jump impulse receipt differs from observed jump",
    )
    require(
        abs(receipt["endpoint_velocity_y"] - sample["velocity"][1]) < 1e-5,
        "vertical endpoint receipt differs",
    )
    half = receipt["gravity"] * receipt["delta"] / 2
    start = receipt.get("jump_impulse", receipt["start_velocity_y"])
    require(
        abs(receipt["motion_velocity_y"] - start + half) < 1e-5,
        "vertical first half-kick differs",
    )
    if receipt["phase"] == "postkick":
        require(not sample["grounded_after"], "postkick cannot overwrite floor support")
        require(
            abs(receipt["endpoint_velocity_y"] - receipt["motion_velocity_y"] + half)
            < 1e-5,
            "vertical second half-kick differs",
        )


def verify(sources, directory, project) -> dict[str, Any]:
    require(
        read(directory / "matrix-lock.json") == lock(sources, directory, project),
        "vertical matrix/source/probe lock changed",
    )
    results = {}
    for name in LEVELS:
        matrix = directory / f"{name}-matrix-v1.json"
        require(
            read(matrix)
            == payload(name, sources, project, directory / f"{name}-rejected.json"),
            "frozen vertical inputs changed",
        )
        source, originals = source_paths(sources, name)
        reports = {}
        for rate in (60, 120):
            _, old = checked(source, originals[rate], rate, project)
            points, reports[rate] = checked(
                matrix, directory / f"{name}-{rate}.json", rate, project
            )
            for mode in MODES:
                point = points["baseline__" + mode]
                require_unchanged_current(
                    old[point["source_case"]], reports[rate][point["id"]]
                )
            for point in points.values():
                row = reports[rate][point["id"]]
                check_cache_receipt(row["trace"])
                for sample in row["trace"]:
                    require(
                        sample["quadrature"]["enabled"] is True,
                        "horizontal integration must remain enabled",
                    )
                    check_vertical_receipt(sample, point["vertical_enabled"], rate)
        variants = {}
        for variant in VARIANTS:
            point = points[variant + "__jump"]
            rows = {r: reports[r][point["id"]] for r in (60, 120)}
            variants[variant] = dict(
                **delta_summary(rows),
                actions={
                    str(r): action_gate(point, rows[r], r)["passed"] for r in (60, 120)
                },
                first_landings={
                    str(r): outcomes(point, rows[r])["first_landing"] for r in (60, 120)
                },
                controls={
                    str(r): {
                        mode: outcomes(
                            points[variant + "__" + mode],
                            reports[r][variant + "__" + mode],
                        )["supported_arrival"]
                        for mode in ("no_jump", "walk")
                    }
                    for r in (60, 120)
                },
            )
        results[name] = variants
    return dict(
        schema=1,
        results=results,
        trials=36,
        baseline_physics_input_traces_unchanged=18,
        production_changed=False,
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        scope="vertical_only_author_candidate_not_original_engine_parity",
        reports_sha256={
            f"{name}-{rate}": sha(directory / f"{name}-{rate}.json")
            for name in LEVELS
            for rate in (60, 120)
        },
        lock_sha256=sha(directory / "matrix-lock.json"),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("sources", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        for name in LEVELS:
            freeze(
                args.directory / f"{name}-matrix-v1.json",
                payload(
                    name,
                    args.sources,
                    args.project,
                    args.directory / f"{name}-rejected.json",
                ),
            )
        freeze(
            args.directory / "matrix-lock.json",
            lock(args.sources, args.directory, args.project),
        )
        print("VERTICAL_MAP_MATRIX_FROZEN 36")
    else:
        result = verify(args.sources, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print("VERTICAL_MAP_COMPARISON_VERIFIED", result["trials"])
