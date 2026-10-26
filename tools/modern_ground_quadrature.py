"""Opt-in author candidate and paired baseline receipts; production rules stay frozen."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from movement_dimension_gates import action_gate
from native_jump_candidates import freeze, outcomes
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

PROBES = (
    "tools/authoring/ModernGroundQuadraturePlayer.gd",
    "tools/authoring/audit_modern_ground_quadrature.gd",
)


def payload(source, project, rejection) -> dict[str, Any]:
    data = read(source)
    require(
        data.get("schema") == 4
        and data.get("formal_qualification") is False
        and not data.get("camera_only"),
        "physical Modern source required",
    )
    parents = [p for p in data["cases"] if p["scheme"] == "modern_cs"]
    require(
        len(parents) == 3
        and {p["trial_mode"] for p in parents} == {"jump", "no_jump", "walk"},
        "complete Modern controls required",
    )
    cases = []
    for enabled in (False, True):
        for original in parents:
            p = copy.deepcopy(original)
            p.update(
                id=("candidate" if enabled else "baseline") + "__" + p["trial_mode"],
                source_case=original["id"],
                quadrature_enabled=enabled,
                rejection_path=str(rejection),
            )
            p["probe_sha256"].update({"res://" + f: sha(project / f) for f in PROBES})
            cases.append(p)
    return dict(
        data, cases=cases, parent_sha256=sha(source), stage="opt_in_ground_quadrature"
    )


def runup_decomposition(point, rows):
    direction = [-math.sin(point["yaw"]), 0, -math.cos(point["yaw"])]
    progress = lambda v: sum(a * b for a, b in zip(v, direction))
    takeoff = next(s["time"] for s in rows[60]["trace"] if s["jumped"])
    require(
        abs(takeoff * 60 - round(takeoff * 60)) < 1e-6,
        "run-up comparison boundary not common",
    )
    n = round(takeoff * 60)
    v60 = [progress(s["velocity"]) for s in rows[60]["trace"][:n]]
    v120 = [progress(s["velocity"]) for s in rows[120]["trace"][: 2 * n]]
    rule = sum((v60[i] - v120[2 * i + 1]) / 60 for i in range(n))
    quadrature = sum(
        (v120[2 * i + 1] - (v120[2 * i] + v120[2 * i + 1]) / 2) / 60 for i in range(n)
    )
    actual = progress(
        [
            a - b
            for a, b in zip(
                rows[60]["trace"][n - 1]["position"],
                rows[120]["trace"][2 * n - 1]["position"],
            )
        ]
    )
    return dict(
        boundary_seconds=takeoff,
        actual_position_delta_m=actual,
        end_velocity_rule_contribution_m=rule,
        displacement_quadrature_contribution_m=quadrature,
        integrated_delta_m=rule + quadrature,
        residual_m=actual - rule - quadrature,
    )


def check_cache_receipt(trace):
    previous = None
    for sample in trace:
        q = sample["quadrature"]
        valid = bool(previous and previous["quadrature"]["substeps"])
        matches = False
        if valid and previous is not None:
            expected = previous["quadrature"]["motion_velocity"]
            velocity = previous["velocity"]
            matches = (
                math.hypot(expected[0] - velocity[0], expected[2] - velocity[2])
                < 0.00001
            )
        require(
            q["restored"] is matches,
            "candidate restored stale endpoint after collision",
        )
        require(
            q["cache_discarded"] is (valid and not matches),
            "cache discard receipt differs",
        )
        previous = sample


def verify(source, directory, project) -> dict[str, Any]:
    matrix = directory / "matrix-v1.json"
    expected = payload(source, project, directory / "rejected.json")
    require(read(matrix) == expected, "candidate source/inputs changed")
    reports, original = {}, {}
    for rate in (60, 120):
        _, original[rate] = checked(
            source,
            source.parent / f"{source.name.split('-')[0]}-{rate}.json",
            rate,
            project,
        )
        points, reports[rate] = checked(
            matrix, directory / f"{rate}.json", rate, project
        )
        for mode in ("jump", "no_jump", "walk"):
            p = points["baseline__" + mode]
            require_unchanged_current(
                original[rate][p["source_case"]], reports[rate][p["id"]]
            )
        for p in points.values():
            if p["quadrature_enabled"]:
                check_cache_receipt(reports[rate][p["id"]]["trace"])
            for s in reports[rate][p["id"]]["trace"]:
                q = s["quadrature"]
                require(
                    q["enabled"] is p["quadrature_enabled"], "candidate toggle changed"
                )
                require(
                    not q["enabled"] or q["substeps"] in (0, 1, 2),
                    "unbounded candidate substeps",
                )
    results = {}
    for variant in ("baseline", "candidate"):
        rows = {r: reports[r][variant + "__jump"] for r in (60, 120)}
        point = points[variant + "__jump"]
        a, b = (rows[r]["landing"] for r in (60, 120))
        results[variant] = dict(
            actions={
                str(r): action_gate(point, rows[r], r)["passed"] for r in (60, 120)
            },
            first_landings={
                str(r): outcomes(point, rows[r])["first_landing"] for r in (60, 120)
            },
            first_landing_delta_m=math.dist(a["position"], b["position"])
            if a and b
            else None,
            controls={
                str(r): {
                    m: outcomes(
                        points[variant + "__" + m], reports[r][variant + "__" + m]
                    )["supported_arrival"]
                    for m in ("no_jump", "walk")
                }
                for r in (60, 120)
            },
        )
    return dict(
        schema=1,
        results=results,
        runup_decomposition=runup_decomposition(
            points["baseline__jump"],
            {r: reports[r]["baseline__jump"] for r in (60, 120)},
        ),
        baseline_physics_unchanged=True,
        production_changed=False,
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        scope="author_only_displacement_quadrature_not_full_physics_substeps",
        source_sha256=sha(source),
        matrix_sha256=sha(matrix),
        reports_sha256={str(r): sha(directory / f"{r}.json") for r in (60, 120)},
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(
            args.directory / "matrix-v1.json",
            payload(args.source, args.project, args.directory / "rejected.json"),
        )
    else:
        result = verify(args.source, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print("MODERN_QUADRATURE_VERIFIED", result["results"])
