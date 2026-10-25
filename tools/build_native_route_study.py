"""Freeze profile-specific key/mouse routes without changing old point qualification."""

import argparse
import copy
import hashlib
import json
from pathlib import Path

SCHEMES = ("current", "legacy_16", "modern_cs")


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze(seed, discovery, output):
    source, found = read(seed), read(discovery)
    if found["manifest_sha256"] != sha(seed) or found["identity"] != source["identity"]:
        raise ValueError("discovery provenance mismatch")
    if found.get("feedback") is not True:
        raise ValueError("missing explicit discovery identity")
    rows = {(r["scheme"], r["mode"]): r for r in found["results"]}
    if len(rows) != 6 or len(found["results"]) != 6:
        raise ValueError("missing/duplicate profile discovery")
    originals = {p["id"]: p for p in source["cases"]}
    cases = []
    for scheme in SCHEMES:
        for mode in ("no_jump", "walk"):
            row = rows[(scheme, mode)]
            if not row["feedback"] or not row["route_arrival_reached"] or not row["trace"]:
                raise ValueError("route discovery did not establish supported arrival")
            point = copy.deepcopy(originals["run_up"])
            point.update(id=f"{scheme}_route_{mode}", scheme=scheme, parent_case="run_up",
                         trial_mode=mode, goal_kind="supported_arrival", duration=12.0,
                         native_timeline=[dict(at=s["time"], **s["native_command"]) for s in row["trace"]])
            cases.append(point)
        for name in ("run_up", "crouch_jump"):
            point = copy.deepcopy(originals[name])
            point.update(id=f"{scheme}_{name}", scheme=scheme, parent_case=name,
                         trial_mode="jump", goal_kind="first_landing")
            held = {"direction": [0, 0], "jump": False, "crouch": False, "walk": False}
            point["native_timeline"] = []
            for event in point["timeline"]:
                held.update({k: v for k, v in event.items() if k in held})
                x, y = held["direction"]
                if x not in (-1, 0, 1) or y not in (-1, 0, 1):
                    raise ValueError("original direction cannot be represented by digital keys")
                keys = (["W"] if y < 0 else ["S"] if y > 0 else [])
                keys += ["A"] if x < 0 else ["D"] if x > 0 else []
                keys += [k for k, flag in (("Space", "jump"), ("Ctrl", "crouch"), ("Shift", "walk")) if held[flag]]
                point["native_timeline"].append({"at": event["at"], "keys": keys, "mouse_dx": 0.0})
            cases.append(point)
        point = copy.deepcopy(originals["run_up"])
        point.update(id=f"{scheme}_input_contract", scheme=scheme, parent_case="run_up",
                     trial_mode="jump", goal_kind="input_contract", duration=1.5)
        point["native_timeline"] = [
            {"at": i / 10, "keys": keys, "mouse_dx": dx}
            for i, (keys, dx) in enumerate([
                (["W"], 0), (["D"], 20), (["S"], -20), (["A"], 0),
                (["W", "D"], 0), (["W", "Shift"], 0), (["W", "Ctrl"], 0),
                (["W", "Space"], 0), (["W"], 0), ([], 0)])]
        cases.append(point)
    payload = {"schema": 4, "formal_qualification": False, "level": source["level"],
               "identity": source["identity"], "seed_sha256": sha(seed),
               "discovery_sha256": sha(discovery), "runtime_sha256": found["runtime_sha256"],
               "input_map_sha256": found["input_map_sha256"], "cases": cases}
    data = (json.dumps(payload, indent=2) + "\n").encode()
    if output.resolve() in (seed.resolve(), discovery.resolve()):
        raise ValueError("cannot overwrite source evidence")
    if output.exists() and output.read_bytes() != data:
        raise ValueError("study frozen; use a new revision")
    output.write_bytes(data)
    return payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seed", type=Path)
    parser.add_argument("discovery", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    study = freeze(args.seed, args.discovery, args.output)
    print("NATIVE_ROUTE_STUDY_FROZEN", len(study["cases"]), sha(args.output))
