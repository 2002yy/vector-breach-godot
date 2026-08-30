from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import build_foundry_assets as foundry  # noqa: E402


def _temporary_collection(name: str) -> bpy.types.Collection | None:
    if bpy.data.collections.get(name) is not None:
        return None
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def _remove_collection(collection: bpy.types.Collection | None) -> None:
    if collection is None:
        return
    bpy.data.collections.remove(collection)


def _resave_canonical_master() -> None:
    source_blend = (
        PROJECT_ROOT
        / "assets-source"
        / "blender"
        / "maps"
        / "foundry_asset_source.blend"
    )
    previous_save_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(source_blend))
    finally:
        bpy.context.preferences.filepaths.save_version = previous_save_versions


def build() -> dict:
    foundry.reset_owned_scene()
    result = {
        "blockout": foundry.build_map_blockout(),
        "details": foundry.build_map_details(),
    }

    # The legacy preview path predates the standalone weapon producer and
    # assumes these collections exist only so it can hide them. Supply empty
    # compatibility collections for the render call, then remove them and
    # resave the map-only canonical master. No weapon geometry is built or
    # published here.
    temporary = [
        _temporary_collection(foundry.RIFLE_COLLECTION),
        _temporary_collection(foundry.PISTOL_COLLECTION),
    ]
    try:
        result["final"] = foundry.export_map_and_save()
    finally:
        for collection in temporary:
            _remove_collection(collection)
        _resave_canonical_master()

    print("FOUNDRY_PORTABLE_PUBLISH=PASS")
    return result


if __name__ == "__main__":
    print(json.dumps(build(), indent=2))
