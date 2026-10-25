"""Version qualified subsets without editing the original frozen corpus."""

import argparse
import hashlib
import json
from pathlib import Path

from map_jump_qualification import require, validate_review

MAPS = ("dust2", "mirage", "inferno")


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parent", type=Path)
    parser.add_argument("review", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    require(args.output.resolve() != args.parent.resolve(), "cannot overwrite parent frozen corpus")
    manifests = {n: load(args.parent / f"{n}-manifest.json") for n in MAPS}
    digests = {n: sha(args.parent / f"{n}-manifest.json") for n in MAPS}
    verified = validate_review(load(args.review), args.parent, manifests, digests, load)
    args.output.mkdir(parents=True, exist_ok=True)
    receipt = {"schema": 2, "maps": {}}
    outputs = {}
    for name in MAPS:
        ids = {p["case"] for p in verified["validated_points"]
               if p["map"] == name and p["status"] == "qualified_jump"}
        parent = manifests[name]
        child = {"schema": 2, "revision": "movement4-r1-qualified-v2",
            "level": parent["level"], "identity": parent["identity"],
            "parent_manifest_sha256": digests[name], "qualification_sha256": sha(args.review),
            "cases": [p for p in parent["cases"] if p["id"] in ids]}
        if not child["cases"]:
            raise ValueError(f"No qualified jump for {name}; not freezing an empty map")
        path = args.output / f"{name}-manifest.json"
        payload = (json.dumps(child, indent=2) + "\n").encode("utf-8")
        if path.exists():
            require(load(path) == child, "cannot replace frozen revision; use a new output directory")
            payload = path.read_bytes()
        outputs[path] = payload
        receipt["maps"][name] = {"sha256": hashlib.sha256(payload).hexdigest(), "case_ids": sorted(ids)}
    outputs[args.output / "freeze.json"] = (json.dumps(receipt, indent=2) + "\n").encode("utf-8")
    freeze_path = args.output / "freeze.json"
    if freeze_path.exists():
        require(load(freeze_path) == receipt, "cannot replace frozen receipt")
        outputs[freeze_path] = freeze_path.read_bytes()
    for path, payload in outputs.items():
        require(not path.exists() or path.read_bytes() == payload,
                "cannot replace frozen revision; use a new output directory")
    for path, payload in outputs.items():
        if not path.exists():
            path.write_bytes(payload)
    print("QUALIFIED_SUBSET_FROZEN", sum(len(r["case_ids"]) for r in receipt["maps"].values()))


if __name__ == "__main__":
    main()
