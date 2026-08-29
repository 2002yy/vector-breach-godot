from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_EXTENSIONS = {".blend", ".blend1", ".kra", ".psd"}
GENERATED_RUNTIME_EXTENSIONS = {".glb", ".gltf", ".import", ".ctex", ".stex"}
LFS_POINTER_PREFIX = b"version https://git-lfs.github.com/spec/v1\n"
GENERATED_TRACKED_ALLOWLIST = {
    "assets-generated/.gdignore",
    "assets-generated/README.md",
}


def tracked_files() -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return {
        item.decode("utf-8").replace("\\", "/")
        for item in result.stdout.split(b"\0")
        if item
    }


def lfs_tracked_files(paths: set[str]) -> set[str]:
    lfs_paths: set[str] = set()
    ordered = sorted(paths)
    for start in range(0, len(ordered), 100):
        chunk = ordered[start : start + 100]
        result = subprocess.run(
            ["git", "check-attr", "filter", "--", *chunk],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        for line in result.stdout.splitlines():
            path, _, value = line.rpartition(": filter: ")
            if value.strip() == "lfs":
                lfs_paths.add(path.replace("\\", "/"))
    return lfs_paths


def git_blob(path: str) -> bytes:
    return subprocess.run(
        ["git", "cat-file", "-p", f"HEAD:{path}"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    ).stdout


def main() -> int:
    tracked = tracked_files()
    violations: list[str] = []

    for required in ("assets-source/.gdignore", "assets-generated/.gdignore"):
        if required not in tracked:
            violations.append(f"missing Godot import barrier: {required}")

    for path in sorted(tracked):
        suffix = Path(path).suffix.lower()

        if suffix in SOURCE_EXTENSIONS and not path.startswith("assets-source/"):
            violations.append(
                "editable source master is outside canonical assets-source/: " + path
            )

        if path.startswith("assets-source/") and suffix in GENERATED_RUNTIME_EXTENSIONS:
            violations.append(
                "generated/runtime artifact is inside source layer: " + path
            )

        if path.startswith("assets-generated/") and path not in GENERATED_TRACKED_ALLOWLIST:
            violations.append(f"generated intermediate is tracked by Git: {path}")

        if path.startswith("tools/blender/source/"):
            violations.append(
                "legacy Blender source root must stay retired; use assets-source/: " + path
            )

    for path in sorted(lfs_tracked_files(tracked)):
        if not git_blob(path).startswith(LFS_POINTER_PREFIX):
            violations.append(
                "file matches Git LFS attributes but Git stores raw binary instead of an LFS pointer: "
                + path
            )

    if violations:
        print("ASSET_LAYER_POLICY=FAIL")
        for violation in violations:
            print(f"- {violation}")
        return 1

    source_master_count = sum(
        1
        for path in tracked
        if path.startswith("assets-source/") and Path(path).suffix.lower() in SOURCE_EXTENSIONS
    )
    print("ASSET_LAYER_POLICY=PASS")
    print(f"source_masters={source_master_count}")
    print("legacy_blender_masters=0")
    print("runtime_layer=assets/")
    print("source_layer=assets-source/")
    print("generated_layer=assets-generated/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
