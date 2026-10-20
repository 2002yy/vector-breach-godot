"""Retain original collision bytes used by frozen-layout hashes in exported builds."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

LEVELS = (
    "dustline-depths-original-local",
    "mirage-classic-local",
    "inferno-classic-local",
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def resource_path(root: Path, resource: str) -> Path:
    if not resource.startswith("res://"):
        raise ValueError(f"Expected res:// path: {resource}")
    result = (root / resource[6:]).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError(f"Resource escapes root: {resource}")
    return result


def stage(project: Path, build: Path, require_all: bool = False) -> dict:
    project, build = project.resolve(), build.resolve()
    if project == build or project.is_relative_to(build):
        raise ValueError("Build directory must not contain the source project")
    planned = {}
    skipped = []
    for level_id in LEVELS:
        level_resource = f"res://data/levels/{level_id}.json"
        level_file = resource_path(project, level_resource)
        if not level_file.exists():
            if require_all:
                raise ValueError(f"Required local level missing: {level_id}")
            skipped.append(level_id)
            continue
        data = json.loads(level_file.read_text(encoding="utf-8-sig"))
        manifest_file = resource_path(
            project, data.get("match_manifest", "res://data/levels/match-local/dustline.json")
        )
        manifest = json.loads(manifest_file.read_text(encoding="utf-8-sig"))
        collision = data.get("runtime_collision_scene", data.get("visual_scene", ""))
        if manifest.get("schema") != 1 or manifest.get("collision_path") != collision:
            raise ValueError(f"Frozen collision declaration mismatch: {level_id}")
        if digest(level_file) != manifest.get("level_sha256", {}).get(level_resource):
            raise ValueError(f"Frozen level hash mismatch: {level_id}")
        source = resource_path(project, collision)
        expected = manifest.get("collision_sha256", "")
        if not expected or digest(source) != expected:
            raise ValueError(f"Frozen collision hash mismatch: {level_id}")
        destination = resource_path(build, collision)
        if destination.exists() and digest(destination) != expected:
            raise ValueError(f"Refusing to replace conflicting build file: {destination}")
        planned[collision] = (source, destination, expected)
    # Validate the entire inventory before writing any bytes.
    records = []
    for resource, (source, destination, expected) in planned.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            shutil.copyfile(source, destination)
        if digest(destination) != expected:
            raise ValueError(f"Copied collision hash mismatch: {destination}")
        records.append({"resource": resource, "sha256": expected, "bytes": source.stat().st_size})
    result = {"schema": 1, "files": records, "skipped_uninstalled_levels": skipped}
    build.mkdir(parents=True, exist_ok=True)
    (build / "frozen-match-sources.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--require-all", action="store_true")
    args = parser.parse_args()
    result = stage(args.project, args.build, args.require_all)
    print(f"FROZEN_MATCH_SOURCES_OK files={len(result['files'])}")


if __name__ == "__main__":
    main()
