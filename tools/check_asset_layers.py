from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_EXTENSIONS = {".blend", ".blend1", ".kra", ".psd"}
GENERATED_TRACKED_ALLOWLIST = {
    "assets-generated/.gdignore",
    "assets-generated/README.md",
}
LEGACY_BLENDER_SOURCE_ALLOWLIST = {
    "tools/blender/source/.gdignore",
    "tools/blender/source/core_vault_asset_source.blend",
    "tools/blender/source/foundry_asset_source.blend",
    "tools/blender/source/foundry_reforged_source.blend",
    "tools/blender/source/gatehouse_asset_source.blend",
    "tools/blender/source/tactical_actor_lowpoly_source.blend",
    "tools/blender/source/weapon_asset_source.blend",
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


def main() -> int:
    tracked = tracked_files()
    violations: list[str] = []

    for required in ("assets-source/.gdignore", "assets-generated/.gdignore"):
        if required not in tracked:
            violations.append(f"missing Godot import barrier: {required}")

    for path in sorted(tracked):
        suffix = Path(path).suffix.lower()
        if path.startswith("assets/") and suffix in SOURCE_EXTENSIONS:
            violations.append(f"editable source file is inside runtime assets: {path}")

        if path.startswith("assets-generated/") and path not in GENERATED_TRACKED_ALLOWLIST:
            violations.append(f"generated intermediate is tracked by Git: {path}")

        if path.startswith("tools/blender/source/") and path not in LEGACY_BLENDER_SOURCE_ALLOWLIST:
            violations.append(
                "new file added to legacy Blender source root; use assets-source/: " + path
            )

    if violations:
        print("ASSET_LAYER_POLICY=FAIL")
        for violation in violations:
            print(f"- {violation}")
        return 1

    legacy_count = len(LEGACY_BLENDER_SOURCE_ALLOWLIST & tracked) - 1
    print("ASSET_LAYER_POLICY=PASS")
    print(f"legacy_blender_masters={max(legacy_count, 0)}")
    print("runtime_layer=assets/")
    print("source_layer=assets-source/")
    print("generated_layer=assets-generated/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
