"""Reconnect frozen body sweeps without borrowing controls or accepting old cadence."""

import argparse
import copy
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from map_jump_qualification import clear_corridor
from movement_evidence_bank import (
    LEVELS,
    Sources,
    collect,
    coverage,
    geometry_matches,
    paired_timeline,
    profile_evidence,
)
from native_jump_candidates import check_report, freeze, outcomes
from validate_native_route_study import require


def unique(rows, predicate, message):
    found = [row for row in rows if predicate(row)]
    require(len(found) == 1, message)
    return found[0]


def load_channels(manifest_path, report_paths, level, identity):
    manifest = read(manifest_path)
    require(
        manifest.get("schema") == 1
        and manifest["level"] == level
        and manifest["identity"] == identity,
        "corridor source map identity differs",
    )
    require(set(report_paths) == {60, 120}, "both corridor rates required")
    points = manifest["cases"]
    require(len({p["id"] for p in points}) == len(points), "duplicate source point")
    channels = {}
    for rate, path in report_paths.items():
        data = read(path)
        require(
            data.get("schema") == 1
            and data.get("kind") == "map_jump_qualification_evidence_v1"
            and data.get("physics_hz") == rate
            and data.get("manifest_sha256") == sha(manifest_path)
            and data.get("level") == level
            and data.get("identity") == identity,
            "corridor report scope or frozen manifest mismatch",
        )
        rows = data["points"]
        require(
            len(rows) == len(points)
            and {r["case"] for r in rows} == {p["id"] for p in points},
            "corridor point coverage missing or duplicated",
        )
        channels[rate] = {r["case"]: r["corridor"] for r in rows}
        # Recompute every body envelope, including blocked source points.
        for point in points:
            clear_corridor(point, channels[rate][point["id"]])
    return manifest, channels


def attach(point, originals, channels):
    matches = [
        p
        for p in originals
        if p["kind"] == point["kind"] and geometry_matches(point, p)
    ]
    require(len(matches) <= 1, "ambiguous historical body corridor")
    if not matches:
        return None
    original = matches[0]
    proofs = {r: channels[r][original["id"]] for r in (60, 120)}
    for proof in proofs.values():
        clear_corridor(point, proof)
    return original["id"], proofs


def historical_category(manifest_path, reports, project):
    """Observe old successes separately; never invent queued cadence or walk trials."""
    manifest = read(manifest_path)
    rows = {}
    for rate in (60, 120):
        check_report(manifest_path, reports[rate], rate, project)
        rows[rate] = {r["id"]: r for r in read(reports[rate])["results"]}
    records = []
    for point in manifest["cases"]:
        if point["trial_mode"] != "jump":
            continue
        control = unique(
            manifest["cases"],
            lambda p: (
                p["parent_case"] == point["parent_case"]
                and p["scheme"] == point["scheme"]
                and p["trial_mode"] == "no_jump"
            ),
            "missing paired historical no-jump trial",
        )
        require(
            paired_timeline(point, control, "no_jump"), "historical control mismatch"
        )
        observations = {}
        for rate in (60, 120):
            row = rows[rate][point["id"]]
            takeoffs = [s for s in row["trace"] if s["jumped"]]
            observations[str(rate)] = dict(
                actual_takeoffs=len(takeoffs),
                first_landing=outcomes(point, row)["first_landing"],
                crouched_in_air=any(
                    not s["grounded_after"]
                    and s["crouching"]
                    and abs(s["capsule_height"] - 1.2) < 1e-5
                    for s in row["trace"]
                ),
                no_jump_arrival=outcomes(control, rows[rate][control["id"]])[
                    "supported_arrival"
                ],
            )
        records.append(
            dict(
                case=point["id"],
                kind=point["kind"],
                scheme=point["scheme"],
                observations=observations,
                queued_cadence_present=point.get("queued_input") is True,
                paired_standing_walk_present=any(
                    p["trial_mode"] == "walk" and paired_timeline(point, p, "walk")
                    for p in manifest["cases"]
                ),
                current_category_credit=False,
            )
        )
    return records


def evaluate(config, project) -> dict[str, Any]:
    require(config["schema"] == 1, "wrong provenance config schema")
    bank_config = read(Path(config["bank_config"]))
    previous: dict[str, Any]
    previous, _ = collect(bank_config, project)
    reader = Sources(bank_config["providers"], project)
    require(
        set(config["corridors"]) == set(config["historical"]) == set(LEVELS),
        "three maps required",
    )
    sites = copy.deepcopy(previous["sites"])
    bindings, historical = {}, {}
    for name in LEVELS:
        channel_source = config["corridors"][name]
        manifest_path = Path(channel_source["manifest"])
        reports = {r: Path(channel_source[f"report{r}"]) for r in (60, 120)}
        identity = reader.load("ordinary/" + name)[0]["identity"]
        original, channels = load_channels(
            manifest_path, reports, LEVELS[name], identity
        )
        bindings[name] = dict(
            manifest_sha256=sha(manifest_path),
            reports={str(r): sha(p) for r, p in reports.items()},
        )
        for site in sites:
            if site["map"] != name or site["kind"] not in {"ordinary", "edge"}:
                continue
            for scheme, prior in site["profiles"].items():
                key = prior["source_provider"]
                _, points, rows = reader.load(key)
                point = points[prior["source_case"]]
                recovered = attach(point, original["cases"], channels)
                prior["corridor_recovery"] = dict(
                    matched=recovered is not None,
                    reason="exact_frozen_geometry" if recovered else "geometry_changed",
                    reference=bindings[name],
                )
                if recovered is None:
                    continue
                source_case, proofs = recovered
                point = dict(point)
                point.pop("corridor", None)
                control_key = "walking/" + name if site["kind"] == "edge" else key
                _, cp, cr = reader.load(control_key)
                controls = {
                    mode: unique(
                        cp.values(),
                        lambda p: (
                            p["trial_mode"] == mode
                            and p["scheme"] == scheme
                            and geometry_matches(point, p)
                        ),
                        "ambiguous matching control",
                    )
                    for mode in ("no_jump", "walk")
                }
                # Keep each rate's own proof. Do not copy one report over the other.
                refreshed = profile_evidence(
                    point,
                    {
                        r: dict(rows[r][point["id"]], ingress_corridor=proofs[r])
                        for r in (60, 120)
                    },
                    {
                        r: {m: cr[r][p["id"]] for m, p in controls.items()}
                        for r in (60, 120)
                    },
                    controls,
                )
                prior.update(refreshed)
                prior["corridor_recovery"]["source_case"] = source_case
        source = config["historical"][name]
        path = Path(source["manifest"])
        data = read(path)
        require(
            data["identity"] == identity and data["level"] == LEVELS[name],
            "historical map identity differs",
        )
        reports = {r: Path(source[f"report{r}"]) for r in (60, 120)}
        records = historical_category(path, reports, project)
        require(
            {p["scheme"] for p in records if p["kind"] == "crouch_jump"}
            == set(SCHEMES),
            "historical crouch profile coverage missing",
        )
        historical[name] = dict(
            manifest_sha256=sha(path),
            reports={str(r): sha(p) for r, p in reports.items()},
            records=records,
            scope="historical_native_input_without_current_queued_cadence_or_standing_walk",
        )
    categories = coverage(sites)
    return dict(
        schema=1,
        bank_config_sha256=sha(Path(config["bank_config"])),
        source_rows_revalidated=previous["source_rows_revalidated"],
        sites=sites,
        category_coverage=categories,
        action_categories=sum(c["action_covered"] for c in categories),
        jump_route_categories=sum(c["jump_route_covered"] for c in categories),
        corridor_bindings=bindings,
        historical=historical,
        new_native_trials=0,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
    )


def input_lock(config_path, project):
    config = read(config_path)
    bank = read(Path(config["bank_config"]))
    paths = {config_path, Path(config["bank_config"])}
    for source in (
        *bank["providers"].values(),
        *config["corridors"].values(),
        *config["historical"].values(),
    ):
        paths.update(Path(source[f]) for f in ("manifest", "report60", "report120"))
    return dict(
        files={str(p): sha(p) for p in sorted(paths)},
        checker_sha256={
            p: sha(project / p)
            for p in (
                "tools/movement_corridor_provenance.py",
                "tools/movement_evidence_bank.py",
                "tools/map_jump_qualification.py",
                "tools/movement_dimension_gates.py",
                "tools/native_jump_candidates.py",
                "tools/edge_drop_revision.py",
                "tools/queued_three_map_audit.py",
                "tools/authoring/ClassicJumpSurvey.gd",
            )
        },
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "verify"))
    parser.add_argument("config", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    summary = evaluate(read(args.config), args.project)
    lock = input_lock(args.config, args.project)
    for filename, data in (("source-lock.json", lock), ("summary.json", summary)):
        path = args.directory / filename
        if args.mode == "build":
            freeze(path, data)
        else:
            require(read(path) == data, "frozen provenance or summary changed")
    print(
        "CORRIDOR_PROVENANCE_VERIFIED",
        len(summary["sites"]),
        summary["action_categories"],
        summary["jump_route_categories"],
    )


if __name__ == "__main__":
    main()
