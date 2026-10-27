"""Freeze a support-only candidate against immutable horizontal+vertical evidence."""

import argparse
import copy
import math
from pathlib import Path

from build_native_route_study import read, sha
from edge_drop_revision import checked
from modern_ground_quadrature import check_cache_receipt
from movement_evidence_bank import LEVELS, geometry_matches, paired_timeline
from native_jump_candidates import freeze, outcomes
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require
from vertical_candidate_map_audit import check_vertical_receipt, delta_summary

MODES = ("jump", "no_jump", "walk")
PROBES = (
    "tools/authoring/ModernSnapSupportPlayer.gd",
    "tools/authoring/audit_modern_snap_support.gd",
)


def payload(name, source, project, rejection):
    path = source / f"{name}-matrix-v1.json"
    data = read(path)
    require(name in LEVELS and data["level"] == LEVELS[name], "wrong source map")
    require(
        data["schema"] == 4 and data["formal_qualification"] is False,
        "physical source required",
    )
    parents = [p for p in data["cases"] if p["id"] in {"vertical__" + m for m in MODES}]
    require(
        len(parents) == 3 and {p["trial_mode"] for p in parents} == set(MODES),
        "all controls required",
    )
    jump = next(p for p in parents if p["trial_mode"] == "jump")
    for p in parents:
        require(
            p["vertical_enabled"] is True
            and p["quadrature_enabled"] is True
            and p["scheme"] == "modern_cs",
            "horizontal and vertical must stay on",
        )
        require(geometry_matches(jump, p), "paired geometry changed")
        if p["trial_mode"] != "jump":
            require(paired_timeline(jump, p, p["trial_mode"]), "paired input changed")
        require(
            all(
                sha(project / key.removeprefix("res://")) == value
                for key, value in p["probe_sha256"].items()
            ),
            "old producer drift",
        )
    cases = []
    for variant in ("baseline", "support"):
        for p in parents:
            point = copy.deepcopy(p)
            point.update(
                id=variant + "__" + p["trial_mode"],
                source_case=p["id"],
                support_enabled=variant == "support",
                rejection_path=str(rejection),
            )
            point["probe_sha256"].update(
                {"res://" + key: sha(project / key) for key in PROBES}
            )
            cases.append(point)
    return dict(
        data,
        cases=cases,
        stage="snap_support_only_candidate",
        source_manifest_sha256=sha(path),
        source_reports_sha256={
            str(r): sha(source / f"{name}-{r}.json") for r in (60, 120)
        },
    )


def lock(source, directory, project):
    return dict(
        matrices={name: sha(directory / f"{name}-matrix-v1.json") for name in LEVELS},
        probes={p: sha(project / p) for p in PROBES},
        sources={
            name: {
                suffix: sha(source / f"{name}-{suffix}.json")
                for suffix in ("matrix-v1", "60", "120")
            }
            for name in LEVELS
        },
    )


def check_receipts(row, enabled):
    previous = None
    for sample in row["trace"]:
        receipt = sample["support"]
        require(receipt["enabled"] is enabled, "support toggle changed")
        if receipt["attempted"]:
            require(
                enabled
                and math.dist(receipt["position_before"], receipt["position_after"])
                > 1e-6,
                "support requires actual snap",
            )
            require(
                receipt["grounded_after"] == sample["grounded_after"],
                "engine support receipt differs",
            )
            require(
                math.dist(receipt["position_after"], sample["position"]) < 1e-5,
                "support endpoint differs from actual body position",
            )
            if receipt["grounded_after"]:
                require(
                    receipt["floor_normal"][1] >= math.cos(math.pi / 4) - 1e-5,
                    "walkable support required",
                )
        if previous is not None:
            events = sample["landing_events"] - previous["landing_events"]
            expected = int(not sample["grounded_before"] and sample["grounded_after"])
            require(
                events == expected, "landed event must match real floor transition once"
            )
        previous = sample


def verify(source, directory, project):
    require(
        read(directory / "matrix-lock.json") == lock(source, directory, project),
        "source/matrix/probe lock drift",
    )
    results = {}
    for name in LEVELS:
        matrix = directory / f"{name}-matrix-v1.json"
        require(
            read(matrix)
            == payload(name, source, project, directory / f"{name}-rejected.json"),
            "frozen candidate changed",
        )
        reports = {}
        for rate in (60, 120):
            _, old = checked(
                source / f"{name}-matrix-v1.json",
                source / f"{name}-{rate}.json",
                rate,
                project,
            )
            points, reports[rate] = checked(
                matrix, directory / f"{name}-{rate}.json", rate, project
            )
            for mode in MODES:
                require_unchanged_current(
                    old["vertical__" + mode], reports[rate]["baseline__" + mode]
                )
            for point in points.values():
                row = reports[rate][point["id"]]
                check_cache_receipt(row["trace"])
                check_receipts(row, point["support_enabled"])
                for sample in row["trace"]:
                    check_vertical_receipt(sample, True, rate)
        variants = {}
        for variant in ("baseline", "support"):
            point = points[variant + "__jump"]
            rows = {r: reports[r][point["id"]] for r in reports}
            variants[variant] = dict(
                **delta_summary(rows),
                first_landings={
                    str(r): outcomes(point, rows[r])["first_landing"] for r in rows
                },
                controls={
                    str(r): {
                        m: outcomes(
                            points[variant + "__" + m], reports[r][variant + "__" + m]
                        )["supported_arrival"]
                        for m in ("no_jump", "walk")
                    }
                    for r in rows
                },
                support_sync_count={
                    str(r): sum(
                        s["support"]["attempted"]
                        and s["support"].get("grounded_after", False)
                        for s in rows[r]["trace"]
                    )
                    for r in rows
                },
            )
        results[name] = variants
    return dict(
        schema=1,
        results=results,
        trials=36,
        baseline_unchanged=18,
        formal_release_ready=False,
        production_changed=False,
        source_report_sha256={
            f"{n}-{r}": sha(directory / f"{n}-{r}.json")
            for n in LEVELS
            for r in (60, 120)
        },
        matrix_lock_sha256=sha(directory / "matrix-lock.json"),
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
        for name in LEVELS:
            freeze(
                args.directory / f"{name}-matrix-v1.json",
                payload(
                    name,
                    args.source,
                    args.project,
                    args.directory / f"{name}-rejected.json",
                ),
            )
        freeze(
            args.directory / "matrix-lock.json",
            lock(args.source, args.directory, args.project),
        )
        print("SNAP_SUPPORT_MATRIX_FROZEN 36")
    else:
        result = verify(args.source, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print("SNAP_SUPPORT_VERIFIED", result["trials"])
