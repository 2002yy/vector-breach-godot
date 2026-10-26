"""Close edge reference gaps with paired controls and current body envelopes."""

import argparse
import copy
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from edge_drop_revision import checked
from movement_evidence_bank import geometry_matches, paired_timeline, profile_evidence
from native_jump_candidates import freeze, outcomes
from tactical_jump_coverage import require_unchanged_current
from validate_native_route_study import require

MAPS = ("dust2", "mirage", "inferno")
REFERENCES = {
    "current": ("edge", "current__reverse_hold"),
    "legacy_16": ("edge", "legacy_16__reverse_010"),
    "modern_cs": ("modern", "modern_cs__brake_2"),
}
PROBES = (
    "tools/authoring/audit_edge_paired.gd",
    "tools/authoring/ClassicJumpSurvey.gd",
)


def control_timeline(timeline, mode):
    require(mode in ("jump", "no_jump", "walk"), "unknown paired control mode")
    result = copy.deepcopy(timeline)
    if mode != "jump":
        for event in result:
            event["keys"] = [
                key
                for key in event["keys"]
                if key != "Space" and not (mode == "walk" and key == "Ctrl")
            ]
            if mode == "walk" and "Shift" not in event["keys"]:
                event["keys"].append("Shift")
    return result


def retain_walkability(profile, observations):
    """A failed braking control cannot erase an already verified walking route."""
    require(set(observations) == {60, 120}, "both walking-context rates required")
    known = all(any(row.values()) for row in observations.values())
    result = dict(profile)
    result["paired_input_route_status"] = profile["status"]
    result["geometry_role"] = "walk_only" if known else profile["status"]
    result["known_forward_walk_arrival_both_rates"] = known
    result["status"] = result["geometry_role"]
    result["jump_route_passed"] = profile["jump_route_passed"] and not known
    result["jump_necessity_accepted"] = False
    return result


def payload(name, config, project, rejection):
    require(name in MAPS, "unknown map")
    cases, references = [], {}
    representative: dict[str, Any] = {}
    base: dict[str, Any] = {}
    for scheme in SCHEMES:
        family, case_id = REFERENCES[scheme]
        provider = config["providers"][family + "/" + name]
        path = Path(provider["manifest"])
        source = read(path)
        for rate in (60, 120):
            points, _ = checked(path, Path(provider[f"report{rate}"]), rate, project)
        parent = points[case_id]
        require(
            parent["kind"] == "edge"
            and parent["trial_mode"] == "jump"
            and parent["scheme"] == scheme,
            "edge reference relabelled",
        )
        for key, digest in parent["probe_sha256"].items():
            require(
                sha(project / key.removeprefix("res://")) == digest,
                "reference probe drift",
            )
        if not representative:
            representative, base = parent, source
        require(geometry_matches(representative, parent), "profile geometries differ")
        require(
            base["identity"] == source["identity"]
            and base["runtime_sha256"] == source["runtime_sha256"]
            and base["input_map_sha256"] == source["input_map_sha256"],
            "reference scope differs",
        )
        references[scheme] = dict(
            provider=family + "/" + name,
            case=case_id,
            manifest_sha256=sha(path),
            reports_sha256={
                str(r): sha(Path(provider[f"report{r}"])) for r in (60, 120)
            },
        )
        for mode in ("jump", "no_jump", "walk"):
            point = copy.deepcopy(parent)
            point.pop("corridor", None)
            point.update(
                id=f"edge__{scheme}__{mode}",
                source_case=case_id,
                parent_case="edge_paired_reference",
                trial_mode=mode,
                native_timeline=control_timeline(parent["native_timeline"], mode),
                rejection_path=str(rejection),
                probe_sha256=dict(
                    parent["probe_sha256"],
                    **{"res://" + p: sha(project / p) for p in PROBES},
                ),
            )
            cases.append(point)
    return dict(
        base,
        cases=cases,
        stage="paired_edge_controls_and_current_corridors",
        map_label=name,
        formal_qualification=False,
        source_references=references,
    )


def freeze_matrix(directory, sources, project):
    config = read(sources)
    hashes = {}
    for name in MAPS:
        path = directory / f"{name}-paired-v1.json"
        freeze(
            path, payload(name, config, project, directory / f"{name}-rejected.json")
        )
        hashes[name] = sha(path)
    freeze(
        directory / "matrix-lock.json",
        dict(source_config_sha256=sha(sources), manifests_sha256=hashes),
    )
    freeze(directory / "walking-context-lock.json", walking_lock(config))


def walking_lock(config):
    return {
        name: {
            field: sha(Path(config["providers"]["walking/" + name][field]))
            for field in ("manifest", "report60", "report120")
        }
        for name in MAPS
    }


def verify(directory, sources, project) -> dict[str, Any]:
    config = read(sources)
    require(
        read(directory / "walking-context-lock.json") == walking_lock(config),
        "forward walking context changed",
    )
    paths = {name: directory / f"{name}-paired-v1.json" for name in MAPS}
    require(
        read(directory / "matrix-lock.json")
        == dict(
            source_config_sha256=sha(sources),
            manifests_sha256={name: sha(path) for name, path in paths.items()},
        ),
        "paired input lock changed",
    )
    sites = []
    for name, path in paths.items():
        manifest = read(path)
        require(
            manifest
            == payload(name, config, project, directory / f"{name}-rejected.json"),
            "frozen paired inputs changed",
        )
        rows = {}
        for rate in (60, 120):
            points, rows[rate] = checked(
                path, directory / f"{name}-{rate}.json", rate, project
            )
        profiles = {}
        for scheme in SCHEMES:
            jump = points[f"edge__{scheme}__jump"]
            family, original_id = REFERENCES[scheme]
            source = config["providers"][family + "/" + name]
            controls = {m: points[f"edge__{scheme}__{m}"] for m in ("no_jump", "walk")}
            require(
                all(paired_timeline(jump, p, m) for m, p in controls.items()),
                "unpaired control inputs",
            )
            for rate in (60, 120):
                _, old = checked(
                    Path(source["manifest"]),
                    Path(source[f"report{rate}"]),
                    rate,
                    project,
                )
                require_unchanged_current(old[original_id], rows[rate][jump["id"]])
            profiles[scheme] = profile_evidence(
                jump,
                {r: rows[r][jump["id"]] for r in (60, 120)},
                {
                    r: {m: rows[r][p["id"]] for m, p in controls.items()}
                    for r in (60, 120)
                },
                controls,
            )
            profiles[scheme]["baseline_physical_trace_identical"] = True
            profiles[scheme]["source_evidence"] = manifest["source_references"][scheme]
            walking = config["providers"]["walking/" + name]
            observed = {}
            for rate in (60, 120):
                wp, wr = checked(
                    Path(walking["manifest"]),
                    Path(walking[f"report{rate}"]),
                    rate,
                    project,
                )
                observed[rate] = {}
                for mode in ("no_jump", "walk"):
                    matches = [
                        p
                        for p in wp.values()
                        if p["scheme"] == scheme
                        and p["trial_mode"] == mode
                        and geometry_matches(jump, p)
                    ]
                    require(
                        len(matches) == 1,
                        "walking-context geometry missing or ambiguous",
                    )
                    control = matches[0]
                    observed[rate][mode] = outcomes(control, wr[control["id"]])[
                        "supported_arrival"
                    ]
            profiles[scheme] = retain_walkability(profiles[scheme], observed)
            profiles[scheme]["forward_walk_context"] = {
                str(r): v for r, v in observed.items()
            }
            profiles[scheme]["forward_walk_source_sha256"] = dict(
                manifest=sha(Path(walking["manifest"])),
                reports={str(r): sha(Path(walking[f"report{r}"])) for r in (60, 120)},
            )
        sites.append(
            dict(map=name, kind="edge", profiles=profiles, human_review="pending")
        )
    return dict(
        schema=1,
        sites=sites,
        new_native_trials=54,
        new_control_trials=36,
        repeated_jump_trials=18,
        original_geometry_body_envelopes=6,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        production_changed=False,
        checker_sha256=sha(Path(__file__)),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("sources", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze_matrix(args.directory, args.sources, args.project)
    else:
        result = verify(args.directory, args.sources, args.project)
        freeze(args.directory / "validated-summary.json", result)
        print(
            "EDGE_PAIRED_VERIFIED",
            [
                (s["map"], {p: v["status"] for p, v in s["profiles"].items()})
                for s in result["sites"]
            ],
        )


if __name__ == "__main__":
    main()
