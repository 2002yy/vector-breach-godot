"""Build schema-2 point receipts from frozen physics and body/control evidence."""

import argparse
import hashlib
import json
from pathlib import Path

from map_jump_qualification import assess

MAPS = ("dust2", "mirage", "inferno")


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frozen_directory", type=Path)
    parser.add_argument("qualification_directory", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    archive = args.frozen_directory.parent.resolve()
    review = {"schema": 2, "reference_profile": "current@b0378218", "points": []}
    for name in MAPS:
        path = args.frozen_directory / f"{name}-manifest.json"
        manifest = load(path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        channels, jumps, refs = {}, {}, []
        for rate in (60, 120):
            for folder, suffix in ((args.qualification_directory, f"qualify-{rate}"),
                                   (args.frozen_directory, str(rate))):
                evidence = folder / f"{name}-{suffix}.json"
                data = load(evidence)
                refs.append({"file": str(evidence.resolve().relative_to(archive)).replace("\\", "/"),
                             "sha256": hashlib.sha256(evidence.read_bytes()).hexdigest()})
                if "points" in data:
                    channels[rate] = data["points"]
                else:
                    jumps[rate] = data["results"]
        for point in manifest["cases"]:
            per_point = {rate: next(p for p in rows if p["case"] == point["id"])
                         for rate, rows in channels.items()}
            status, reason = assess(point, per_point, jumps)
            review["points"].append({"map": name, "case": point["id"],
                "level": manifest["level"], "manifest_sha256": digest, "status": status,
                "reason": reason, "evidence": refs})
    args.out.write_text(json.dumps(review, indent=2) + "\n", encoding="utf-8")
    print("POINT_QUALIFICATION_WRITTEN 15 points, no aggregate complete flag")


if __name__ == "__main__":
    main()
