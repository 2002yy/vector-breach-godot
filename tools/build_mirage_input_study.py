"""Freeze route discovery inputs and predeclared posture/timing comparisons."""

import argparse
import copy
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parent", type=Path)
    parser.add_argument("discovery", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    parent, discovery = read(args.parent), read(args.discovery)
    if discovery["manifest_sha256"] != sha(args.parent) or discovery["identity"] != parent["identity"]:
        raise ValueError("discovery does not belong to frozen parent")
    original = {p["id"]: p for p in parent["cases"]}
    cases = []
    for row in discovery["results"]:
        if row.get("control_type") != "feedback_discovery_not_acceptance" or not row["trace"]:
            raise ValueError("missing discovery trace")
        point = copy.deepcopy(original["run_up"])
        point.update(id="route_" + row["mode"], parent_case="run_up", trial_mode=row["mode"], duration=12.0)
        point["timeline"] = [r["input"] for r in row["trace"]]
        cases.append(point)
    if {p["trial_mode"] for p in cases} != {"no_jump", "walk"}:
        raise ValueError("both discovery controls must be retained")
    for name in ("run_up", "crouch_jump"):
        point = copy.deepcopy(original[name])
        point.update(id=name + "_original", parent_case=name, trial_mode="jump")
        cases.append(point)
    point = copy.deepcopy(original["crouch_jump"])
    point.update(id="crouch_ground_warmup", parent_case="crouch_jump", trial_mode="jump")
    for event in point["timeline"]:
        if "jump" in event:
            event["at"] = 0.5 if event["jump"] else 0.6
    cases.append(point)
    point = copy.deepcopy(original["crouch_jump"])
    point.update(id="run_jump_air_crouch", parent_case="crouch_jump", trial_mode="jump")
    point["timeline"] = [{"at": 0.0, "direction": [0, -1], "crouch": False},
        {"at": 0.1, "jump": True}, {"at": 7 / 60, "crouch": True},
        {"at": 0.2, "jump": False}, {"at": 1.5, "direction": [0, 0]}]
    cases.append(point)
    output = {"schema": 3, "revision": "mirage-route-inputs-r2-v3", "formal_qualification": False,
        "level": parent["level"], "identity": parent["identity"],
        "parent_manifest_sha256": sha(args.parent), "discovery_sha256": sha(args.discovery),
        "reference_runtime_sha256": discovery["runtime_sha256"], "cases": cases}
    payload = (json.dumps(output, indent=2) + "\n").encode("utf-8")
    if args.output.resolve() == args.parent.resolve():
        raise ValueError("cannot overwrite parent")
    if args.output.exists() and args.output.read_bytes() != payload:
        raise ValueError("study is frozen; choose a new file")
    if not args.output.exists():
        args.output.write_bytes(payload)
    print("MIRAGE_INPUT_STUDY_FROZEN", len(cases), hashlib.sha256(payload).hexdigest())


if __name__ == "__main__":
    main()
