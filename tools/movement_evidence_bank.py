"""Recompute observed movement coverage; curate manual inputs without granting release."""

import argparse
import copy
import math
from functools import lru_cache
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from edge_lip_window import MAPS
from map_jump_qualification import KINDS, clear_corridor
from movement_dimension_gates import action_gate, route_gate
from native_jump_candidates import GEOMETRY, freeze, outcomes
from navigation_ingress_margin import margin_score
from validate_native_route_study import require

OBSERVER = "tools/authoring/JumpPlaytestSession.gd"
LEVELS = {
    "dust2": "dustline-depths-original-local",
    "mirage": "mirage-classic-local",
    "inferno": "inferno-classic-local",
}


def geometry_matches(left, right):
    return all(left[k] == right[k] for k in GEOMETRY)


def paired_timeline(jump, control, mode):
    if not geometry_matches(jump, control) or jump["scheme"] != control["scheme"]:
        return False
    expected = []
    for event in jump["native_timeline"]:
        keys = [
            k
            for k in event["keys"]
            if k != "Space" and not (mode == "walk" and k == "Ctrl")
        ]
        if mode == "walk" and "Shift" not in keys:
            keys.append("Shift")
        expected.append((event["at"], keys, event.get("mouse_dx", 0)))
    return expected == [
        (e["at"], e["keys"], e.get("mouse_dx", 0)) for e in control["native_timeline"]
    ]


def coverage(sites) -> list[dict[str, Any]]:
    return [
        dict(
            map=name,
            kind=kind,
            action_covered=any(
                s["map"] == name
                and s["kind"] == kind
                and set(s["profiles"]) == set(SCHEMES)
                and all(p["category_action_passed"] for p in s["profiles"].values())
                for s in sites
            ),
            jump_route_covered=any(
                s["map"] == name
                and s["kind"] == kind
                and set(s["profiles"]) == set(SCHEMES)
                and all(p["jump_route_passed"] for p in s["profiles"].values())
                for s in sites
            ),
        )
        for name in MAPS
        for kind in sorted(KINDS)
    ]


def profile_evidence(point, rows, controls, control_points, require_margin=False):
    actions = {r: action_gate(point, rows[r], r) for r in (60, 120)}
    landings = {r: outcomes(point, rows[r]) for r in (60, 120)}
    require(
        all(geometry_matches(point, control_points[m]) for m in ("no_jump", "walk")),
        "walking evidence has different frozen geometry",
    )
    paired = all(
        paired_timeline(point, control_points[m], m) for m in ("no_jump", "walk")
    )
    walking = {
        r: {
            m: outcomes(control_points[m], controls[r][m])["supported_arrival"]
            for m in ("no_jump", "walk")
        }
        for r in (60, 120)
    }
    corridors = {}
    for r in (60, 120):
        proof = point.get("corridor", rows[r].get("ingress_corridor"))
        if proof is not None:
            corridors[r] = clear_corridor(point, proof)
    extra = {
        r: margin_score(point, rows[r], r)["passed"] if require_margin else True
        for r in (60, 120)
    }
    effective = {
        r: dict(actions[r], passed=actions[r]["passed"] and extra[r]) for r in (60, 120)
    }
    gate = (
        route_gate(
            corridors,
            effective,
            {r: landings[r]["first_landing"] for r in (60, 120)},
            walking,
        )
        if paired and len(corridors) == 2
        else dict(status="route_unproven", jump_route_passed=False)
    )
    return dict(
        source_kind=point["kind"],
        action_passed=all(a["passed"] for a in actions.values()),
        category_action_passed=all(a["passed"] for a in effective.values()),
        first_landings={str(r): v["first_landing"] for r, v in landings.items()},
        walking_observed_both_rates=all(any(v.values()) for v in walking.values()),
        paired_controls_available=paired,
        body_envelope_available=len(corridors) == 2,
        status=gate["status"],
        jump_route_passed=gate["jump_route_passed"],
        extra_approach_margin={str(r): v for r, v in extra.items()}
        if require_margin
        else None,
        source_case=point["id"],
        controls={str(r): v for r, v in walking.items()},
    )


class Sources:
    def __init__(self, providers, project):
        self.providers, self.project = providers, project
        self.counts, self.identities = {}, {}

    @lru_cache(maxsize=4)
    def load(self, key):
        source = self.providers[key]
        manifest = Path(source["manifest"])
        rows = {}
        points = {}
        for rate in (60, 120):
            report = Path(source[f"report{rate}"])
            points, rows[rate] = checked(manifest, report, rate, self.project)
            self.counts[str(report)] = len(rows[rate])
        for path, digest in {
            (p, d) for v in points.values() for p, d in v["probe_sha256"].items()
        }:
            require(
                sha(self.project / path.removeprefix("res://")) == digest,
                "live source probe drift",
            )
        data = read(manifest)
        name = source["map"]
        require(data["level"] == LEVELS[name], "source map label differs from level")
        binding = (data["identity"], data["input_map_sha256"], data["runtime_sha256"])
        require(
            name not in self.identities or self.identities[name] == binding,
            "mixed map/runtime identities",
        )
        self.identities[name] = binding
        return data, points, rows


def source_lock(config, project):
    return dict(
        schema=1,
        observer_sha256=sha(project / OBSERVER),
        providers={
            key: {
                field: sha(Path(source[field]))
                for field in ("manifest", "report60", "report120")
            }
            for key, source in config["providers"].items()
        },
    )


def collect(config, project):
    require(config["schema"] == 1, "wrong bank schema")
    expected = {
        family + "/" + name
        for family in ("critical", "ordinary", "edge", "modern", "walking")
        for name in MAPS
    } | {"run_up/dust2"}
    require(
        set(config["providers"]) == expected
        and all(s["map"] == k.split("/")[-1] for k, s in config["providers"].items()),
        "wrong provider coverage or map",
    )
    reader = Sources(config["providers"], project)
    sites, manual = [], {}

    def add(name, site_id, kind, refs, paired_source=None, margin=False):
        profiles, references, representative = {}, {}, None
        for scheme, (key, case_id) in refs.items():
            data, points, rows = reader.load(key)
            point = points[case_id]
            require(
                point["kind"] == kind
                and point["scheme"] == scheme
                and point["trial_mode"] == "jump",
                "source case relabelled",
            )
            if representative is None:
                representative = point
            require(geometry_matches(representative, point), "profile goals differ")
            control_key = paired_source or key
            _, cp, cr = reader.load(control_key)
            candidates = [
                p
                for p in cp.values()
                if p["queued_input"]
                and p["scheme"] == scheme
                and (
                    p["parent_case"] == point["parent_case"]
                    if paired_source is None
                    else True
                )
            ]
            control_points = {}
            for mode in ("no_jump", "walk"):
                matches = [p for p in candidates if p["trial_mode"] == mode]
                require(len(matches) == 1, "missing or ambiguous controls")
                control_points[mode] = matches[0]
            controls = {
                r: {m: cr[r][p["id"]] for m, p in control_points.items()}
                for r in (60, 120)
            }
            profiles[scheme] = profile_evidence(
                point,
                {r: rows[r][case_id] for r in (60, 120)},
                controls,
                control_points,
                margin,
            )
            profiles[scheme]["source_provider"] = key
            references[scheme] = dict(
                provider=key,
                case=case_id,
                manifest_sha256=sha(Path(config["providers"][key]["manifest"])),
                native_timeline=point["native_timeline"],
            )
            if name not in manual:
                manual[name] = dict(
                    data,
                    cases=[],
                    stage="manual_observation_bank",
                    formal_qualification=False,
                )
        require(set(profiles) == set(SCHEMES), "incomplete three-profile site")
        sites.append(
            dict(
                map=name,
                site=site_id,
                kind=kind,
                profiles=profiles,
                human_review="pending",
                precision_accepted=False,
                spawn_connectivity="unproven",
            )
        )
        assert representative is not None
        p = copy.deepcopy(representative)
        p.update(id=site_id, parent_case=site_id, manual_reference_inputs=references)
        manual[name]["cases"].append(p)

    for name in MAPS:
        for family, kind in (
            ("critical", "critical_landing"),
            ("ordinary", "ordinary"),
        ):
            key = family + "/" + name
            _, points, _ = reader.load(key)
            parents = sorted(
                {
                    p["parent_case"]
                    for p in points.values()
                    if p["queued_input"]
                    and p["trial_mode"] == "jump"
                    and p["kind"] == kind
                }
            )
            require(bool(parents), "missing source category")
            for parent in parents:
                refs = {}
                for scheme in SCHEMES:
                    matches = [
                        p
                        for p in points.values()
                        if p["queued_input"]
                        and p["parent_case"] == parent
                        and p["scheme"] == scheme
                        and p["trial_mode"] == "jump"
                    ]
                    require(len(matches) == 1, "ambiguous action reference")
                    refs[scheme] = (key, matches[0]["id"])
                add(name, family + "__" + parent, kind, refs)
        add(
            name,
            "edge__braking",
            "edge",
            {
                "current": ("edge/" + name, "current__reverse_hold"),
                "legacy_16": ("edge/" + name, "legacy_16__reverse_010"),
                "modern_cs": ("modern/" + name, "modern_cs__brake_2"),
            },
            paired_source="walking/" + name,
        )
    key = "run_up/dust2"
    _, points, _ = reader.load(key)
    refs = {
        p["scheme"]: (key, p["id"])
        for p in points.values()
        if p["trial_mode"] == "jump"
    }
    add("dust2", "run_up__navigation_ingress", "run_up", refs, margin=True)
    categories = coverage(sites)
    return dict(
        schema=1,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        new_native_matrix_trials=0,
        curation_scope="listed_current_verified_cohorts_not_exhaustive_repository_search",
        selection_scope="known_success_reference_curation_not_independent_validation",
        source_rows_revalidated=sum(reader.counts.values()),
        sites=sites,
        category_coverage=categories,
        action_categories=sum(c["action_covered"] for c in categories),
        jump_route_categories=sum(c["jump_route_covered"] for c in categories),
    ), manual


def manual_plan(hashes, observer):
    return dict(
        schema=1,
        human_review="pending",
        formal_release_ready=False,
        observer_sha256=observer,
        manifests_sha256=hashes,
        axes=[
            "movement_response",
            "jump",
            "air_control",
            "stopping",
            "map_reachability",
            "comfort",
        ],
        unavailable_in_observer=[
            "scoped_weapon_speed",
            "gunfight",
            "AI",
            "complete_match",
        ],
        ratings={},
        notes=[],
        reference_inputs_are_not_required_human_pulse_timings=True,
    )


def validate_manual_plan(plan, hashes, observer):
    require(
        plan == manual_plan(hashes, observer), "manual plan changed or falsely accepted"
    )


def write_bank(directory, sources, project):
    config = read(sources)
    lock = source_lock(config, project)
    summary, manual = collect(config, project)
    require(lock == source_lock(config, project), "source changed during collection")
    freeze(directory / "source-lock.json", dict(lock, sources_sha256=sha(sources)))
    hashes = {}
    for name in MAPS:
        path = directory / f"{name}-manual-v1.json"
        freeze(path, manual[name])
        hashes[path.name] = sha(path)
    freeze(
        directory / "manual-plan-v1.json", manual_plan(hashes, lock["observer_sha256"])
    )
    summary.update(
        checker_sha256=sha(Path(__file__)),
        source_lock_sha256=sha(directory / "source-lock.json"),
        manual_plan_sha256=sha(directory / "manual-plan-v1.json"),
    )
    freeze(directory / "summary.json", summary)


def verify_bank(directory, sources, project):
    config = read(sources)
    require(
        read(directory / "source-lock.json")
        == dict(source_lock(config, project), sources_sha256=sha(sources)),
        "source lock changed",
    )
    summary, manual = collect(config, project)
    for name in MAPS:
        path = directory / f"{name}-manual-v1.json"
        require(read(path) == manual[name], "manual manifest changed")
    plan = read(directory / "manual-plan-v1.json")
    validate_manual_plan(
        plan,
        {f"{n}-manual-v1.json": sha(directory / f"{n}-manual-v1.json") for n in MAPS},
        sha(project / OBSERVER),
    )
    summary.update(
        checker_sha256=sha(Path(__file__)),
        source_lock_sha256=sha(directory / "source-lock.json"),
        manual_plan_sha256=sha(directory / "manual-plan-v1.json"),
    )
    require(read(directory / "summary.json") == summary, "bank summary changed")
    return summary


def validate_session_receipt(path, manifest_path, project, expected_mode):
    data, manifest = read(path), read(manifest_path)
    require(
        data["manifest_sha256"] == sha(manifest_path)
        and data["observer_sha256"] == sha(project / OBSERVER)
        and data["identity"] == manifest["identity"]
        and data["runtime_sha256"] == manifest["runtime_sha256"]
        and data["input_map_sha256"] == manifest["input_map_sha256"]
        and data["engine_hash"] == manifest["identity"]["engine_hash"],
        "observation identity drift",
    )
    require(
        data["session_mode"] == expected_mode
        and data["human_review"] == "pending"
        and data["formal_release_ready"] is False,
        "automatic receipt falsely accepted",
    )
    cases = {p["parent_case"] for p in manifest["cases"]}
    samples = 0
    crouch, walk, heights = False, False, set()
    for attempt in data["attempts"]:
        require(
            attempt["case"] in cases
            and attempt["scheme"] in SCHEMES
            and attempt["human_review"] == "pending",
            "unbound observation attempt",
        )
        previous = -1
        for sample in attempt["trace"]:
            require(sample["physics_frame"] > previous, "unordered observation trace")
            previous = sample["physics_frame"]
            require(
                all(
                    type(sample[k]) is bool
                    for k in (
                        "crouch_requested",
                        "walk_requested",
                        "grounded_before",
                        "grounded",
                    )
                )
                and math.isfinite(sample["capsule_height"])
                and sample["capsule_height"] > 0,
                "missing posture/support observation",
            )
            samples += 1
            crouch = crouch or sample["crouch_requested"]
            walk = walk or sample["walk_requested"]
            heights.add(sample["capsule_height"])
    require(samples > 0, "empty observation trace")
    return dict(
        mode=expected_mode,
        samples=samples,
        attempts=len(data["attempts"]),
        human_review="pending",
        formal_release_ready=False,
        receipt_sha256=sha(path),
        saw_crouch=crouch,
        saw_walk=walk,
        capsule_heights=sorted(heights),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "verify"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.mode == "build":
        write_bank(args.directory, args.sources, args.project)
    else:
        verify_bank(args.directory, args.sources, args.project)
    print("MOVEMENT_EVIDENCE_BANK_OK", args.mode)
