"""Compose current three-map evidence from original validators, never old summaries."""

import argparse
import copy
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_paired_qualification import verify as verify_edges
from inferno_current_brake import composite
from mirage_legacy_early import verify as verify_legacy
from movement_corridor_provenance import evaluate as provenance, input_lock
from movement_evidence_bank import LEVELS, geometry_matches, paired_timeline
from native_jump_candidates import freeze
from queued_crouch_audit import evaluate as verify_crouch
from runup_profile_inputs import verify as verify_modern
from runup_route_revision import verify as verify_runup
from validate_native_route_study import require

KINDS = ("critical_landing", "crouch_jump", "run_up", "ordinary", "edge")
JUMP_KINDS = KINDS[:3]


def default_config(evidence):
    return dict(
        schema=1,
        provenance=str(
            evidence / "movement-corridor-provenance-20261026/sources-v1.json"
        ),
        crouch=str(evidence / "queued-crouch-three-map-20261027"),
        edge=str(evidence / "edge-paired-qualification-20261027"),
        runup=str(evidence / "runup-route-revision-20261027/v2"),
        modern=str(evidence / "mirage-runup-profile-inputs-20261027"),
        legacy=str(evidence / "mirage-legacy-early-20261027"),
        inferno=str(evidence / "inferno-clear-inputs-20261027/v3"),
        surveys=str(evidence / "three-map-movement-points-20261025"),
    )


def source_ref(directory, manifest="selected-v1.json", prefix=""):
    return dict(
        manifest=str(directory / manifest),
        report60=str(directory / f"{prefix}60.json"),
        report120=str(directory / f"{prefix}120.json"),
    )


def selected_controls(point, cases):
    """Keep controls in the selected input family and frozen parent case."""
    controls = {}
    for mode in ("no_jump", "walk"):
        matches = [
            p
            for p in cases
            if p["trial_mode"] == mode
            and p["kind"] == point["kind"]
            and p["parent_case"] == point["parent_case"]
            and p["queued_input"] == point["queued_input"]
            and paired_timeline(point, p, mode)
        ]
        require(
            len(matches) == 1,
            f"selected control missing or ambiguous: {point['id']} {mode} "
            f"matches={[p['id'] for p in matches]}",
        )
        controls[mode] = matches[0]["id"]
    return controls


def select_categories(sites):
    """One frozen site per map/kind; never combine different targets by profile."""
    selected, archive, categories = [], [], []
    for name in LEVELS:
        for kind in KINDS:
            candidates = sorted(
                (s for s in sites if s["map"] == name and s["kind"] == kind),
                key=lambda s: s["site"],
            )
            require(bool(candidates), "current category has no source")
            eligible = []
            for site in candidates:
                profiles = site["profiles"]
                require(set(profiles) == set(SCHEMES), "incomplete formal schemes")
                first = profiles[SCHEMES[0]]["point"]
                require(
                    all(geometry_matches(first, p["point"]) for p in profiles.values()),
                    "cross-profile frozen geometry differs",
                )
                strong = all(
                    p["category_action_passed"]
                    and p["body_envelope_available"]
                    and p["paired_controls_available"]
                    and p["first_landings"] == {"60": True, "120": True}
                    and p["status"]
                    == ("qualified_jump" if kind in JUMP_KINDS else "walk_only")
                    for p in profiles.values()
                )
                if strong:
                    eligible.append(site)
            # Fixed lexical order, independent of frequency error or subjective scores.
            chosen = eligible[0] if eligible else candidates[0]
            selected.append(chosen)
            archive.extend(s for s in candidates if s is not chosen)
            categories.append(
                dict(
                    map=name,
                    kind=kind,
                    selected_site=chosen["site"],
                    status=("qualified_jump" if kind in JUMP_KINDS else "walk_only")
                    if eligible
                    else "unproven",
                    qualified=bool(eligible),
                    jump_required=kind in JUMP_KINDS,
                )
            )
    return selected, archive, categories


def compose(config, project) -> dict[str, Any]:
    require(config["schema"] == 1, "unknown current registry config")
    paths = {k: Path(v) for k, v in config.items() if k != "schema"}
    provenance_config = read(paths["provenance"])
    bank_path = Path(provenance_config["bank_config"])
    bank = read(bank_path)
    base = provenance(provenance_config, project)
    crouch = verify_crouch(paths["crouch"], paths["provenance"], project)
    edges = verify_edges(paths["edge"], bank_path, project)
    runup = paths["runup"]
    mirage = verify_runup(
        "mirage", paths["surveys"] / "mirage-manifest.json", runup, project
    )
    modern = verify_modern(runup, paths["modern"], project)
    legacy_result = verify_legacy(runup, paths["modern"], paths["legacy"], project)
    require(
        legacy_result["mirage_all_three_schemes_qualified"],
        "Mirage composite not qualified",
    )
    legacy = dict(profiles={"legacy_16": legacy_result["legacy"]})
    inferno = composite(runup, paths["inferno"], project)
    require(inferno["category_closed"], "Inferno run-up composite not qualified")
    sources = dict(bank["providers"])
    sites = [s for s in base["sites"] if s["kind"] != "edge"]
    for site in sites:
        for profile in site["profiles"].values():
            profile["source_reference"] = sources[profile["source_provider"]]
    for name in LEVELS:
        for result, kind, directory, filename in (
            (crouch, "crouch_jump", paths["crouch"], f"{name}-queued-v1.json"),
            (edges, "edge", paths["edge"], f"{name}-paired-v1.json"),
        ):
            site = copy.deepcopy(next(s for s in result["sites"] if s["map"] == name))
            site.setdefault("site", "edge__paired_current_geometry")
            ref = source_ref(directory, filename, name + "-")
            key = kind + "/" + name
            sources[key] = ref
            for scheme, profile in site["profiles"].items():
                profile.update(source_provider=key, source_reference=ref)
                profile["source_case"] = (
                    "crouch" if kind == "crouch_jump" else "edge"
                ) + f"__{scheme}__jump"
            sites.append(site)
    for name in ("mirage", "inferno"):
        profiles = {}
        for scheme in SCHEMES:
            if name == "mirage":
                result, directory = {
                    "current": (mirage, runup),
                    "modern_cs": (modern, paths["modern"]),
                    "legacy_16": (legacy, paths["legacy"]),
                }[scheme]
                ref = (
                    source_ref(directory, "mirage-selected-v1.json", "mirage-")
                    if scheme == "current"
                    else source_ref(directory)
                )
            else:
                result = inferno
                directory = {
                    "legacy_16": paths["inferno"].parent,
                    "modern_cs": paths["inferno"].parent / "v2",
                    "current": paths["inferno"],
                }[scheme]
                ref = source_ref(directory)
            profile = copy.deepcopy(result["profiles"][scheme])
            key = "run_up/" + name + "/" + scheme
            sources[key] = ref
            profile.update(source_provider=key, source_reference=ref)
            profiles[scheme] = profile
        sites.append(
            dict(
                map=name,
                kind="run_up",
                site="run_up__" + ("rise_05" if name == "mirage" else "rise_03"),
                profiles=profiles,
            )
        )

    bindings, source_files = {}, {}
    for site in sites:
        for scheme, profile in site["profiles"].items():
            ref = profile["source_reference"]
            manifest_path = Path(ref["manifest"])
            data = read(manifest_path)
            name = site["map"]
            require(data["level"] == LEVELS[name], "source map label differs")
            binding = {
                k: data[k] for k in ("identity", "runtime_sha256", "input_map_sha256")
            }
            require(
                name not in bindings or bindings[name] == binding,
                "mixed map/runtime/input identities",
            )
            bindings[name] = binding
            point = next(p for p in data["cases"] if p["id"] == profile["source_case"])
            require(
                point["scheme"] == scheme
                and point["kind"] == site["kind"]
                and point["trial_mode"] == "jump",
                "selected profile relabelled",
            )
            for path, digest in point["probe_sha256"].items():
                require(
                    sha(project / path.removeprefix("res://")) == digest,
                    "live selected probe drift",
                )
            profile["point"] = copy.deepcopy(point)
            profile["manifest"] = {
                k: data[k]
                for k in (
                    "schema",
                    "level",
                    "identity",
                    "runtime_sha256",
                    "input_map_sha256",
                    "formal_qualification",
                )
            }
            for field in ("manifest", "report60", "report120"):
                path = Path(ref[field])
                source_files[str(path)] = sha(path)
            # Exact paired IDs are resolved from geometry and frozen timelines.
            profile["control_cases"] = selected_controls(point, data["cases"])
    selected, archive, categories = select_categories(sites)
    lock = input_lock(paths["provenance"], project)
    source_files.update(lock["files"])
    return dict(
        schema=1,
        version="movement-current-registry-v1",
        config=config,
        selection_policy="first_strong_site_by_lexical_site_id_per_map_kind",
        sites=selected,
        archive_sites=archive,
        categories=categories,
        source_lock=source_files,
        provenance_checker_lock=lock["checker_sha256"],
        jump_required_categories=sum(
            c["qualified"] and c["jump_required"] for c in categories
        ),
        jump_required_denominator=9,
        walking_categories=sum(
            c["qualified"] and not c["jump_required"] for c in categories
        ),
        walking_denominator=6,
        action_categories=sum(
            all(p["category_action_passed"] for p in s["profiles"].values())
            for s in selected
        ),
        historical_route_denominator=15,
        new_native_trials=0,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        historical_exposure=True,
        selection_scope="known_success_reference_not_blind_validation",
    )


def build_registry(path, config, project):
    registry = compose(config, project)
    freeze(path, registry)
    return registry


def verify_registry(path, project):
    registry = read(path)
    for filename, digest in registry["source_lock"].items():
        require(sha(Path(filename)) == digest, "current source lock changed")
    require(
        compose(registry["config"], project) == registry, "current registry changed"
    )
    return registry


def public_summary(registry):
    return {
        k: registry[k]
        for k in (
            "schema",
            "version",
            "selection_policy",
            "categories",
            "jump_required_categories",
            "jump_required_denominator",
            "walking_categories",
            "walking_denominator",
            "action_categories",
            "historical_route_denominator",
            "new_native_trials",
            "formal_release_ready",
            "human_acceptance",
            "precision_equivalence_accepted",
            "movement5_frozen",
            "historical_exposure",
            "selection_scope",
        )
    } | dict(
        selected_sites=len(registry["sites"]),
        archived_duplicate_sites=len(registry["archive_sites"]),
        profiles=[
            dict(
                map=s["map"],
                site=s["site"],
                kind=s["kind"],
                scheme=scheme,
                case=p["source_case"],
                controls=p["control_cases"],
                status=p["status"],
            )
            for s in registry["sites"]
            for scheme, p in s["profiles"].items()
        ],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "verify"))
    parser.add_argument("registry", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument(
        "--evidence", type=Path, default=Path("D:/AgentGamePipeline/evidence")
    )
    args = parser.parse_args()
    value = (
        build_registry(args.registry, default_config(args.evidence), args.project)
        if args.mode == "build"
        else verify_registry(args.registry, args.project)
    )
    print(
        "CURRENT_REGISTRY_VERIFIED",
        len(value["sites"]),
        value["jump_required_categories"],
        value["walking_categories"],
    )
