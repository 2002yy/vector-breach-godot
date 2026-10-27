"""Complete predeclared critical/ordinary/edge candidate cohorts, preserving failures."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from modern_ground_quadrature import PROBES as PREVIOUS_PROBES, check_cache_receipt
from movement_dimension_gates import action_gate
from movement_evidence_bank import LEVELS, geometry_matches, paired_timeline
from native_jump_candidates import freeze, outcomes
from queued_three_map_audit import CADENCE_PROBES, PROBES as BASE_PROBES, QUEUE_PROBES
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

FAMILIES = {"critical": "critical_landing", "ordinary": "ordinary", "edge": "edge"}
PROBES = (
    *PREVIOUS_PROBES,
    "tools/authoring/ModernGroundQuadratureV2Player.gd",
    "tools/authoring/audit_modern_ground_quadrature_v2.gd",
)
EXPECTED_SITES = {"dust2": 3, "mirage": 3, "inferno": 4}
MODES = {"jump", "no_jump", "walk"}


def choose_groups(source, family):
    require(
        source.get("schema") == 4
        and source.get("formal_qualification") is False
        and not source.get("camera_only"),
        "physical queued source required",
    )
    chosen = [
        p
        for p in source["cases"]
        if p["scheme"] == "modern_cs"
        and p.get("queued_input") is True
        and p["kind"] == FAMILIES[family]
    ]
    groups: dict[str, list[dict[str, Any]]] = {}
    for point in chosen:
        groups.setdefault(point["parent_case"], []).append(point)
    require(bool(groups), "missing selected source category")
    for parent, points in groups.items():
        require(
            len(points) == 3 and {p["trial_mode"] for p in points} == MODES,
            "each frozen site needs all three modes exactly once",
        )
        jump = next(p for p in points if p["trial_mode"] == "jump")
        require(
            all(geometry_matches(jump, p) for p in points),
            "source control geometry differs",
        )
        require(
            all(
                paired_timeline(jump, p, p["trial_mode"])
                for p in points
                if p["trial_mode"] != "jump"
            ),
            "source control timeline differs",
        )
    return groups


def payload(name, providers, project, rejection) -> dict[str, Any]:
    require(
        name in LEVELS and set(providers) == set(FAMILIES),
        "wrong map/category coverage",
    )
    base: dict[str, Any] = {}
    cases, refs = [], {}
    groups_count = 0
    hashes = {
        "res://" + p: sha(project / p)
        for p in (*BASE_PROBES, *QUEUE_PROBES, *CADENCE_PROBES, *PROBES)
    }
    for family in FAMILIES:
        provider = providers[family]
        path = Path(provider["manifest"])
        source = read(path)
        require(source["level"] == LEVELS[name], "source map label differs")
        if base:
            require(
                all(
                    source[k] == base[k]
                    for k in ("identity", "runtime_sha256", "input_map_sha256")
                ),
                "mixed map/runtime sources",
            )
        else:
            base = source
        groups = choose_groups(source, family)
        groups_count += len(groups)
        refs[family] = {
            field: sha(Path(provider[field]))
            for field in ("manifest", "report60", "report120")
        }
        for parent, points in groups.items():
            for original in points:
                for path_name, digest in original["probe_sha256"].items():
                    require(
                        sha(project / path_name.removeprefix("res://")) == digest,
                        "source probe drift",
                    )
                for enabled in (False, True):
                    point = copy.deepcopy(original)
                    variant = "candidate" if enabled else "baseline"
                    point.update(
                        id=f"{family}__{parent}__{variant}__{point['trial_mode']}",
                        source_family=family,
                        source_case=original["id"],
                        study_site=f"{family}__{parent}",
                        quadrature_enabled=enabled,
                        rejection_path=str(rejection),
                        probe_sha256=hashes,
                    )
                    cases.append(point)
    require(
        groups_count == EXPECTED_SITES[name], "selected source site coverage changed"
    )
    return dict(
        base,
        cases=cases,
        source_references=refs,
        stage="predeclared_cross_category_quadrature",
        diagnostic_only=True,
        native_acceptance=False,
    )


def lock(config_path, directory, project):
    return dict(
        schema=1,
        config_sha256=sha(config_path),
        manifests={name: sha(directory / f"{name}-matrix-v1.json") for name in LEVELS},
        candidate_probe_sha256={p: sha(project / p) for p in PROBES},
    )


def verify(config_path, directory, project) -> dict[str, Any]:
    config = read(config_path)
    require(
        read(directory / "matrix-lock.json") == lock(config_path, directory, project),
        "frozen matrix/probe lock changed",
    )
    sites, source_hashes = [], {}
    for name in LEVELS:
        path = directory / f"{name}-matrix-v1.json"
        manifest = read(path)
        require(
            manifest
            == payload(
                name,
                config["providers"][name],
                project,
                directory / f"{name}-rejected.json",
            ),
            "frozen cross-category inputs changed",
        )
        rows, originals = {}, {}
        for rate in (60, 120):
            points, rows[rate] = checked(
                path, directory / f"{name}-{rate}.json", rate, project
            )
            originals[rate] = {}
            for family, provider in config["providers"][name].items():
                _, originals[rate][family] = checked(
                    Path(provider["manifest"]),
                    Path(provider[f"report{rate}"]),
                    rate,
                    project,
                )
            for point in points.values():
                row = rows[rate][point["id"]]
                if not point["quadrature_enabled"]:
                    require_unchanged_current(
                        originals[rate][point["source_family"]][point["source_case"]],
                        row,
                    )
                else:
                    check_cache_receipt(row["trace"])
                require(
                    all(
                        s["quadrature"]["enabled"] is point["quadrature_enabled"]
                        for s in row["trace"]
                    ),
                    "candidate toggle changed",
                )
        for site in sorted({p["study_site"] for p in points.values()}):
            variants = {}
            for variant in ("baseline", "candidate"):
                selected = {
                    p["trial_mode"]: p
                    for p in points.values()
                    if p["study_site"] == site
                    and p["quadrature_enabled"] is (variant == "candidate")
                }
                jump = selected["jump"]
                jump_rows = {r: rows[r][jump["id"]] for r in (60, 120)}
                a, b = (jump_rows[r]["landing"] for r in (60, 120))
                variants[variant] = dict(
                    actions={
                        str(r): action_gate(jump, jump_rows[r], r)["passed"]
                        for r in (60, 120)
                    },
                    first_landings={
                        str(r): outcomes(jump, jump_rows[r])["first_landing"]
                        for r in (60, 120)
                    },
                    first_landing_delta_m=math.dist(a["position"], b["position"])
                    if a and b
                    else None,
                    controls={
                        str(r): {
                            m: outcomes(p, rows[r][p["id"]])["supported_arrival"]
                            for m, p in selected.items()
                            if m != "jump"
                        }
                        for r in (60, 120)
                    },
                )
            sites.append(
                dict(
                    map=name,
                    site=site,
                    kind=jump["kind"],
                    variants=variants,
                    human_review="pending",
                    precision_accepted=False,
                )
            )
        source_hashes[name] = dict(
            manifest=sha(path),
            reports={str(r): sha(directory / f"{name}-{r}.json") for r in (60, 120)},
        )
    return dict(
        schema=1,
        sites=sites,
        selected_sites=10,
        new_native_trials=120,
        baseline_physical_replays_identical=60,
        candidate_trials=60,
        source_hashes=source_hashes,
        production_changed=False,
        formal_release_ready=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        scope="predeclared_limited_cross_category_candidate_not_release_or_new_jump_coverage",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("config", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        config = read(args.config)
        require(set(config["providers"]) == set(LEVELS), "three maps required")
        for name in LEVELS:
            freeze(
                args.directory / f"{name}-matrix-v1.json",
                payload(
                    name,
                    config["providers"][name],
                    args.project,
                    args.directory / f"{name}-rejected.json",
                ),
            )
        freeze(
            args.directory / "matrix-lock.json",
            lock(args.config, args.directory, args.project),
        )
    else:
        result = verify(args.config, args.directory, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print("CROSS_CATEGORY_QUADRATURE_VERIFIED", result["new_native_trials"])
