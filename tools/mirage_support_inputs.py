"""Predeclare bounded new Mirage inputs on the unchanged support-candidate target."""

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from modern_ground_quadrature import check_cache_receipt
from movement_evidence_bank import LEVELS, geometry_matches, paired_timeline
from native_jump_candidates import backstep_input, freeze, outcomes
from snap_support_candidate import check_receipts
from validate_native_route_study import require
from vertical_candidate_map_audit import check_vertical_receipt

MODES = ("jump", "no_jump", "walk")
TICKS = (1, 2, 3)


def payload(source, directory):
    parent = source / "mirage-matrix-v1.json"
    data = read(parent)
    require(data["level"] == LEVELS["mirage"], "Mirage source required")
    originals = {
        m: next(p for p in data["cases"] if p["id"] == "support__" + m) for m in MODES
    }
    cases = []
    for ticks in TICKS:
        for mode in MODES:
            p = copy.deepcopy(originals[mode])
            timeline: list[dict[str, Any]] = backstep_input(0.15, 0.2 + ticks / 60)
            for event in timeline:
                if mode != "jump":
                    event["keys"] = [k for k in event["keys"] if k != "Space"]
                if mode == "walk":
                    event["keys"] = [k for k in event["keys"] if k != "Ctrl"]
                    event["keys"].append("Shift")
            p.update(
                id=f"run_plus_{ticks}__{mode}",
                variant=f"run_plus_{ticks}",
                source_case=originals[mode]["id"],
                native_timeline=timeline,
                rejection_path=str(directory / "rejected.json"),
            )
            cases.append(p)
    return dict(
        data,
        cases=cases,
        stage="predeclared_mirage_support_new_inputs",
        source_manifest_sha256=sha(parent),
        source_reports_sha256={
            str(r): sha(source / f"mirage-{r}.json") for r in (60, 120)
        },
        selection_policy="all_three_predeclared_variants_dual_rate_no_selection",
        rationale="Original first support is 24.54 mm short; forward speed 2.60088 m/s. Add 1/2/3 native 60 Hz ticks before takeoff; preserve relative crouch/release.",
        new_trial_limit=18,
    )


def require_first_support_event(landing):
    require(bool(landing), "real first support required")
    require(
        landing["landing_events"] == 1
        and not landing["grounded_before"]
        and landing["grounded_after"],
        "first support and event must be same frame",
    )


def versioned_input_set(mirage, unchanged):
    require(set(unchanged) == {"dust2", "inferno"}, "both unchanged maps required")
    rows = {"mirage": mirage, **unchanged}
    require(
        all(set(rates) == {"60", "120"} for rates in rows.values()),
        "both rates required",
    )
    return dict(
        version="r30_mirage_run_plus_1_other_maps_r29",
        first_landing_count=sum(
            row["first_landing"] for rates in rows.values() for row in rates.values()
        ),
        total=6,
        outcomes=rows,
        original_frozen_input_set_replaced=False,
        global_adoption=False,
        formal_release_ready=False,
    )


def target_hash(point):
    return hashlib.sha256(
        json.dumps(
            {
                k: point[k]
                for k in (
                    "start",
                    "yaw",
                    "target_feet",
                    "target_radius",
                    "target_height_tolerance",
                    "duration",
                )
            },
            sort_keys=True,
        ).encode()
    ).hexdigest()


def check_named_source(data, name, project):
    require(data["level"] == LEVELS[name], "named map source differs")
    for point in data["cases"]:
        for path, expected in point["probe_sha256"].items():
            require(
                sha(project / path.removeprefix("res://")) == expected,
                "producer probe drift",
            )


def verify(source, directory, project):
    matrix = directory / "mirage-matrix-v1.json"
    require(read(matrix) == payload(source, directory), "frozen inputs/source drift")
    check_named_source(read(matrix), "mirage", project)
    check_named_source(read(source / "mirage-matrix-v1.json"), "mirage", project)
    reports = {}
    old_outcomes = {}
    for rate in (60, 120):
        old_points, old = checked(
            source / "mirage-matrix-v1.json",
            source / f"mirage-{rate}.json",
            rate,
            project,
        )
        for mode in MODES:
            check_receipts(old["support__" + mode], True)
        old_outcomes[str(rate)] = outcomes(
            old_points["support__jump"], old["support__jump"]
        )
        points, reports[rate] = checked(
            matrix, directory / f"mirage-{rate}.json", rate, project
        )
        for p in points.values():
            require(
                geometry_matches(p, old_points["support__" + p["trial_mode"]]),
                "old geometry changed",
            )
            require(
                all(
                    p[k] is True
                    for k in (
                        "support_enabled",
                        "vertical_enabled",
                        "quadrature_enabled",
                    )
                ),
                "candidate must stay on",
            )
            row = reports[rate][p["id"]]
            check_receipts(row, True)
            check_cache_receipt(row["trace"])
            for sample in row["trace"]:
                check_vertical_receipt(sample, True, rate)
    results = {}
    for ticks in TICKS:
        key = f"run_plus_{ticks}"
        jump = points[key + "__jump"]
        for mode in ("no_jump", "walk"):
            require(
                paired_timeline(jump, points[key + "__" + mode], mode),
                "controls not paired",
            )
        rates = {}
        for rate in (60, 120):
            row = reports[rate][jump["id"]]
            verdict = outcomes(jump, row)
            landing = row["landing"]
            require_first_support_event(landing)
            distance = math.hypot(
                landing["position"][0] - jump["target_feet"][0],
                landing["position"][2] - jump["target_feet"][2],
            )
            rates[str(rate)] = dict(
                **verdict,
                radial_margin_m=jump["target_radius"] - distance,
                same_frame_first_support_and_event=True,
                controls={
                    m: outcomes(points[key + "__" + m], reports[rate][key + "__" + m])[
                        "supported_arrival"
                    ]
                    for m in ("no_jump", "walk")
                },
            )
        results[key] = rates
        results[key]["dual_rate_difference"] = dict(
            first_support_time_s=abs(
                rates["60"]["landing_time"] - rates["120"]["landing_time"]
            ),
            first_support_position_m=math.dist(
                reports[60][jump["id"]]["landing"]["position"],
                reports[120][jump["id"]]["landing"]["position"],
            ),
        )
    unchanged = {}
    bindings = {}
    for name in ("dust2", "inferno"):
        unchanged[name] = {}
        matrix_path = source / f"{name}-matrix-v1.json"
        check_named_source(read(matrix_path), name, project)
        bindings[name] = dict(manifest_sha256=sha(matrix_path), reports={})
        for rate in (60, 120):
            report_path = source / f"{name}-{rate}.json"
            old_points, old_rows = checked(matrix_path, report_path, rate, project)
            p, row = old_points["support__jump"], old_rows["support__jump"]
            check_receipts(row, True)
            require_first_support_event(row["landing"])
            unchanged[name][str(rate)] = outcomes(p, row)
            bindings[name]["reports"][str(rate)] = sha(report_path)
        bindings[name].update(
            runtime_sha256=read(matrix_path)["runtime_sha256"],
            probe_sha256=p["probe_sha256"],
            geometry_identity=read(matrix_path)["identity"],
            target_sha256=target_hash(p),
        )
    return dict(
        schema=1,
        trials=18,
        variants=results,
        unchanged_old_input=old_outcomes,
        formal_release_ready=False,
        production_changed=False,
        global_adoption=False,
        original_target_changed=False,
        versioned_input_set=versioned_input_set(
            {r: results["run_plus_1"][r] for r in ("60", "120")}, unchanged
        ),
        unchanged_source_bindings=bindings,
        selection_policy=read(matrix)["selection_policy"],
        source_manifest_sha256=sha(source / "mirage-matrix-v1.json"),
        matrix_sha256=sha(matrix),
        mirage_target_sha256=target_hash(points["run_plus_1__jump"]),
        report_sha256={str(r): sha(directory / f"mirage-{r}.json") for r in (60, 120)},
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
            args.directory / "mirage-matrix-v1.json",
            payload(args.source, args.directory),
        )
        print("MIRAGE_SUPPORT_INPUTS_FROZEN 18")
    else:
        result = verify(args.source, args.directory, args.project)
        freeze(args.directory / "qualified-summary-v2.json", result)
        print("MIRAGE_SUPPORT_INPUTS_VERIFIED", result["trials"])
