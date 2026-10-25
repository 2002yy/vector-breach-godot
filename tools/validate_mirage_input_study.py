"""Separate first-landing precision, supported arrival and unchanged baseline motion."""

import argparse
import hashlib
import json
import math
from pathlib import Path

SCHEMES = ("current", "legacy_16", "modern_cs")
PHYSICS_FIELDS = ("time", "jumped", "grounded_before", "grounded_after", "position", "velocity",
                  "input", "speed_limit", "crouching", "capsule_height")


def require(ok, message):
    if not ok:
        raise ValueError(message)


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare_unchanged(before, after):
    for key, left in before.items():
        if key[1] not in ("current", "legacy_16"):
            continue
        right = after[key]
        require([[row[field] for field in PHYSICS_FIELDS] for row in left["trace"]] ==
                [[row[field] for field in PHYSICS_FIELDS] for row in right["trace"]],
                "Current/Legacy physical trace changed")
        require(left["reason"] == right["reason"] and
                left["route_arrival_reached"] == right["route_arrival_reached"],
                "unchanged reference outcome changed")


def check_outcomes(row):
    require(row["target_reached"] == (row["reason"] == "reached"), "first landing score mismatch")
    if row["route_arrival_reached"]:
        require(row["target_entry"].get("grounded_after") is True and row["goal_entry_support"],
                "arrival lacks independent frozen collision support")
    # Arrival is deliberately not used to overwrite the first-landing verdict.
    if row["target_reached"]:
        require(row["support"] and row["start_valid"], "unbacked first landing")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("parent", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    study_path = args.directory / "input-study-v3.json"
    study, parent = load(study_path), load(args.parent)
    require(study["schema"] == 3 and study["formal_qualification"] is False,
            "input study cannot become formal qualification")
    require(study["parent_manifest_sha256"] == sha(args.parent) and
            study["discovery_sha256"] == sha(args.directory / "route-discovery.json"),
            "study provenance mismatch")
    originals = {p["id"]: p for p in parent["cases"]}
    for point in study["cases"]:
        original = originals[point["parent_case"]]
        require(all(point[key] == original[key] for key in
                    ("start", "yaw", "target_feet", "target_radius", "target_height_tolerance")),
                "geometry or target tolerance changed")
    expected = {(p["id"], scheme) for p in study["cases"] for scheme in SCHEMES}
    require(len(study["cases"]) == 6 and len(expected) == 18, "study case coverage changed")
    summary = {"formal_release_ready": False, "study_sha256": sha(study_path),
               "current_and_legacy_traces_unchanged": True, "results": [], "modern_crouch": []}
    for rate in (60, 120):
        reports = {}
        for phase in ("before", "after"):
            report = load(args.directory / f"{phase}-{rate}.json")
            require(report["manifest_sha256"] == sha(study_path) and
                    report["identity"] == study["identity"] and report["physics_hz"] == rate,
                    "replay does not match frozen study")
            rows = report["results"]
            require(len(rows) == 18 and {(r["id"], r["scheme"]) for r in rows} == expected,
                    "replay coverage incomplete")
            reports[phase] = {(r["id"], r["scheme"]): r for r in rows}
            if phase == "before":
                require(report["runtime_sha256"] == study["reference_runtime_sha256"],
                        "baseline runtime drift")
            for row in rows:
                check_outcomes(row)
                summary["results"].append({"phase": phase, "physics_hz": rate,
                    "case": row["id"], "scheme": row["scheme"],
                    "first_landing_or_control_goal": row["target_reached"],
                    "supported_route_arrival": row["route_arrival_reached"],
                    "first_landing_time": row["landing"].get("time"),
                    "arrival_time": row["target_entry"].get("time"), "reason": row["reason"]})
        compare_unchanged(reports["before"], reports["after"])
        for phase, rows in reports.items():
            crouch = rows[("crouch_jump_original", "modern_cs")]
            samples = [s for s in crouch["trace"] if s["time"] < 0.1 - 1e-6]
            peak = max(math.hypot(s["velocity"][0], s["velocity"][2]) for s in samples)
            limit = samples[-1]["speed_limit"]
            require(peak < limit * 0.2 if phase == "before" else peak >= limit * 0.99,
                    "modern stall counterexample/repair not reproduced")
            summary["modern_crouch"].append({"phase": phase, "physics_hz": rate,
                                             "ground_speed": peak, "speed_limit": limit})
        for name in ("route_no_jump", "route_walk"):
            route = reports["after"][(name, "current")]
            require(not route["jumped"] and route["route_arrival_reached"],
                    "frozen Current non-jump route not established")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("MIRAGE_INPUT_STUDY_OK 72 trials; Current/Legacy unchanged; formal_release_ready=false")


if __name__ == "__main__":
    main()
