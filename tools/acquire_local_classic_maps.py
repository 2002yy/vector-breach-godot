"""Acquire pinned research sources, verifying bytes before conversion.

Run with --output outside Git. No Steam credentials or full game install needed.
Valve-derived data must remain private; these are not original texture packs.
"""

import argparse
import hashlib
import json
import urllib.request
import zipfile
from pathlib import Path

REVISION = "776f381d4a6e1b606190cbc9ab7430e68a03572f"
VISUALS = {
    "inferno": "1403e13847cfea5266927fc3f2b684727c99f85a5e0c066281b203b1cd54bab6",
    "mirage": "2d64bcf23d987dc616f2c958734a14a3c327ffd3309885327c349852ccf81447",
}
PHYSICS_SHA = "e1730a90200a2bacffe6d0d1984d31dc038c52faae91366564403a59b9e9e7f5"
METADATA = {
    "inferno": "9977291123ec3ec4a934bd4b4f2e05fa3e00094b35963fdcdd52d4152bc859a6",
    "mirage": "3bc24d27931f3faa60d568f399f130dd9e44fa813883037bbad89ae37f636ed4",
}
MANIFEST_SHA = "2cf43dda2cda420ea2faa305d9e186833e0bb59a286ac7af61fdecff5ccb1ee2"


def obtain(url, path, expected=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read()
        if expected and hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Source hash mismatch: {path.name}")
        path.write_bytes(data)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if expected and digest != expected:
        raise ValueError(f"Cached source hash mismatch: {path.name}")
    return {
        "url": url,
        "file": str(path),
        "sha256": digest,
        "bytes": path.stat().st_size,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    records = []
    for name, digest in VISUALS.items():
        base = f"https://raw.githubusercontent.com/sliuhaob/mirage-utility-lab/{REVISION}/assets/"
        for suffix in ["native.glb", "native.json"]:
            filename = f"{name}-{suffix}"
            records.append(
                obtain(
                    base + filename,
                    args.output / name / filename,
                    digest if suffix == "native.glb" else METADATA[name],
                )
            )
    physics = args.output / "awpy-2000933"
    url = "https://github.com/pnxenopoulos/awpy-data/releases/download/2000933/"
    records.append(
        obtain(url + "manifest.json", physics / "manifest.json", MANIFEST_SHA)
    )
    records.append(obtain(url + "geometry.zip", physics / "geometry.zip", PHYSICS_SHA))
    with zipfile.ZipFile(physics / "geometry.zip") as archive:
        for name in VISUALS:
            filename = f"de_{name}.mesh"
            data = archive.read(filename)
            destination = physics / filename
            if destination.exists() and destination.read_bytes() != data:
                raise ValueError(f"Existing extracted source differs: {filename}")
            destination.write_bytes(data)
    (args.output / "acquisition.json").write_text(
        json.dumps({"records": records, "original_textures": False}, indent=2),
        encoding="utf-8",
    )
    print(f"CLASSIC_SOURCES_OK: {len(records)} verified sources; no original textures")


if __name__ == "__main__":
    main()
