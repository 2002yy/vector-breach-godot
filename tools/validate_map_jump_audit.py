"""Validate frozen local map trials and publish a coordinate-free audit summary."""

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from map_jump_qualification import require, validate_review, validate_revision

MAPS = ("dust2", "mirage", "inferno")
SCHEMES = ("current", "legacy_16", "modern_cs")
KINDS = {"ordinary", "critical_landing", "edge", "run_up", "crouch_jump"}


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--require-acceptance", action="store_true")
    parser.add_argument("--review", type=Path)
    parser.add_argument("--qualified-directory", type=Path)
    args = parser.parse_args()
    freeze = load(args.directory / "freeze.json")
    manifests, digests = {}, {}
    summary = {"measurement_complete": True, "shared_route_pass": True,
               "frequency_outcome_changes": [], "frequency_pass_changes": [],
               "maps": {}, "results": []}
    for map_name in MAPS:
        manifest_path = args.directory / f"{map_name}-manifest.json"
        manifest = load(manifest_path)
        digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
        manifests[map_name], digests[map_name] = manifest, digest
        require(digest == freeze[map_name]["sha256"], "frozen points changed")
        require({case["id"] for case in manifest["cases"]} == KINDS, "wrong case coverage")
        reports = []
        counts = {}
        for rate in (60, 120):
            report = load(args.directory / f"{map_name}-{rate}.json")
            require(report["manifest_sha256"] == digest, "wrong matrix manifest")
            require(report["identity"] == manifest["identity"], "wrong matrix identity")
            require(report["physics_hz"] == rate, "wrong matrix rate")
            require({(r["id"], r["scheme"]) for r in report["results"]} == {
                (kind, scheme) for kind in KINDS for scheme in SCHEMES
            }, "wrong matrix combinations")
            require(len(report["results"]) == 15, "incomplete matrix")
            reports.append({(r["id"], r["scheme"]): r for r in report["results"]})
            counts[str(rate)] = dict(Counter(r["reason"] for r in report["results"]))
            for row in report["results"]:
                valid = row["start_valid"] and row["jumped"] and row["airborne"]
                summary["measurement_complete"] &= valid and bool(row["trace"])
                summary["shared_route_pass"] &= row["target_reached"]
                require(row["target_reached"] == (row["reason"] == "reached"), "score contradicts reason")
                if row["target_reached"]:
                    require(row["support"] and row["supported_by_frozen_collision"], "missing original support")
                    require(row["landed"], "missing landing")
                summary["results"].append({
                    "map": map_name, "rate": rate, "case": row["id"],
                    "scheme": row["scheme"], "reason": row["reason"],
                    "start_valid": row["start_valid"], "airborne": row["airborne"],
                    "landing_distance_error_m": row["landing_distance"],
                    "landing_height_error_m": row["landing_height_error"],
                })
        for key in reports[0]:
            left, right = reports[0][key], reports[1][key]
            if left["reason"] != right["reason"]:
                summary["frequency_outcome_changes"].append({
                    "map": map_name, "case": key[0], "scheme": key[1],
                    "hz60": left["reason"], "hz120": right["reason"],
                })
            if left["target_reached"] != right["target_reached"]:
                summary["frequency_pass_changes"].append({"map": map_name,
                    "case": key[0], "scheme": key[1]})
        summary["maps"][map_name] = {"frozen_manifest_sha256": digest,
            "collision_sha256": manifest["identity"]["collision_sha256"],
            "counts": counts}
    qualification_error = None
    try:
        summary["point_qualification"] = validate_review(
            load(args.review) if args.review else {}, args.directory, manifests, digests, load)
        if args.qualified_directory:
            summary["qualified_replay"] = validate_revision(args.qualified_directory,
                args.review, manifests, digests, summary["point_qualification"], load)
    except (ValueError, KeyError, TypeError, OSError) as error:
        qualification_error = str(error)
        summary["point_qualification"] = {"schema": 2, "eligible": False, "error": qualification_error}
    summary["release_ready"] = (summary["point_qualification"]["eligible"]
                                and summary["measurement_complete"]
                                and summary["shared_route_pass"]
                                and not summary["frequency_outcome_changes"])
    if args.qualified_directory:
        summary["release_ready"] &= summary.get("qualified_replay", {}).get("all_variants_reached", False)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("MAP_JUMP_AUDIT_WRITTEN trials=90 measurement_complete=%s release_ready=%s" %
          (summary["measurement_complete"], summary["release_ready"]))
    if qualification_error or not summary["point_qualification"]["eligible"]:
        raise SystemExit(1)
    if args.require_acceptance and not summary["release_ready"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
