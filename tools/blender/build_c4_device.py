from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from blender_build_utils import (  # noqa: E402
    add_box,
    add_cylinder,
    ensure_collection,
    export_collection_glb,
    make_material,
    remove_collection,
    validate_collection,
)


C4_COLLECTION = "VB_C4_DEVICE"


def _chamfered_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    chamfer: float = 0.006,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    obj = add_box(name, location, dimensions, material, collection, rotation=rotation)
    modifier = obj.modifiers.new("VB_C4_Chamfer", "BEVEL")
    modifier.width = min(chamfer, min(dimensions) * 0.18)
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    return obj


def _materials() -> dict[str, bpy.types.Material]:
    return {
        "chassis": make_material(
            "MAT_c4_chassis",
            (0.045, 0.055, 0.058, 1.0),
            metallic=0.42,
            roughness=0.48,
        ),
        "charge": make_material(
            "MAT_c4_charge",
            (0.16, 0.18, 0.12, 1.0),
            metallic=0.02,
            roughness=0.82,
        ),
        "rubber": make_material(
            "MAT_c4_rubber",
            (0.018, 0.022, 0.022, 1.0),
            metallic=0.0,
            roughness=0.9,
        ),
        "metal": make_material(
            "MAT_c4_metal",
            (0.22, 0.25, 0.26, 1.0),
            metallic=0.86,
            roughness=0.3,
        ),
        "accent": make_material(
            "MAT_c4_accent",
            (0.78, 0.22, 0.035, 1.0),
            metallic=0.2,
            roughness=0.36,
        ),
        "display": make_material(
            "MAT_c4_display",
            (0.018, 0.09, 0.095, 1.0),
            metallic=0.08,
            roughness=0.18,
            emission=(0.03, 0.42, 0.46, 1.0),
            emission_strength=0.6,
        ),
        "lens": make_material(
            "MAT_c4_status_lens",
            (0.55, 0.58, 0.56, 1.0),
            metallic=0.15,
            roughness=0.16,
        ),
    }


def build_device(materials: dict[str, bpy.types.Material]) -> dict:
    remove_collection(C4_COLLECTION)
    collection = ensure_collection(C4_COLLECTION)

    # Gameplay-compatible footprint: X ~= 0.42 m, Y ~= 0.28 m. The visual
    # assembly is authored above Z=0 so the Godot root can remain the ground /
    # interaction / explosion origin instead of embedding half the model below it.
    _chamfered_box(
        "GEO-c4-base-chassis",
        (0.0, 0.0, 0.027),
        (0.40, 0.26, 0.054),
        materials["chassis"],
        collection,
        chamfer=0.012,
    )

    for side, x in (("L", -0.145), ("R", 0.145)):
        _chamfered_box(
            f"GEO-c4-charge-{side}",
            (x, 0.0, 0.078),
            (0.082, 0.215, 0.070),
            materials["charge"],
            collection,
            chamfer=0.010,
        )
        for y in (-0.075, 0.075):
            _chamfered_box(
                f"GEO-c4-charge-strap-{side}-{'A' if y < 0 else 'B'}",
                (x, y, 0.116),
                (0.096, 0.023, 0.013),
                materials["rubber"],
                collection,
                chamfer=0.003,
            )

    _chamfered_box(
        "GEO-c4-control-deck",
        (0.0, 0.0, 0.094),
        (0.188, 0.145, 0.080),
        materials["chassis"],
        collection,
        chamfer=0.010,
    )
    _chamfered_box(
        "GEO-c4-display-bezel",
        (0.0, -0.042, 0.139),
        (0.126, 0.046, 0.014),
        materials["metal"],
        collection,
        chamfer=0.004,
    )
    _chamfered_box(
        "GEO-c4-display",
        (0.0, -0.043, 0.147),
        (0.108, 0.033, 0.006),
        materials["display"],
        collection,
        chamfer=0.002,
    )

    key_x = (-0.046, 0.0, 0.046)
    key_y = (0.000, 0.019, 0.038, 0.057)
    for row, y in enumerate(key_y):
        for column, x in enumerate(key_x):
            _chamfered_box(
                f"GEO-c4-key-{row + 1:02d}-{column + 1:02d}",
                (x, y, 0.141),
                (0.026, 0.014, 0.012),
                materials["rubber"] if (row + column) % 2 == 0 else materials["metal"],
                collection,
                chamfer=0.002,
            )

    # A raised physical lens gives the armed-status cue a geometric landmark;
    # Godot's existing StatusLight supplies the state-dependent pulse. The cue is
    # therefore not dependent on color alone.
    add_cylinder(
        "GEO-c4-status-lens",
        (0.073, -0.040, 0.154),
        0.014,
        0.014,
        materials["lens"],
        collection,
        vertices=16,
    )

    # Top carry handle: two uprights and one crossbar. It changes silhouette even
    # when the status light is not visible, improving dropped/planted readability.
    for x in (-0.105, 0.105):
        add_cylinder(
            f"GEO-c4-handle-post-{'L' if x < 0 else 'R'}",
            (x, 0.086, 0.151),
            0.009,
            0.070,
            materials["metal"],
            collection,
            vertices=12,
        )
    add_cylinder(
        "GEO-c4-handle-bar",
        (0.0, 0.086, 0.186),
        0.010,
        0.210,
        materials["metal"],
        collection,
        vertices=12,
        rotation=(0.0, math.radians(90.0), 0.0),
    )

    for x in (-0.178, 0.178):
        for y in (-0.108, 0.108):
            add_cylinder(
                f"GEO-c4-fastener-{'L' if x < 0 else 'R'}-{'F' if y < 0 else 'B'}",
                (x, y, 0.058),
                0.010,
                0.012,
                materials["metal"],
                collection,
                vertices=10,
            )

    # Four shallow feet preserve the bottom-center origin and make ground contact
    # readable in gameplay screenshots without altering collision authority.
    for x in (-0.155, 0.155):
        for y in (-0.095, 0.095):
            _chamfered_box(
                f"GEO-c4-foot-{'L' if x < 0 else 'R'}-{'F' if y < 0 else 'B'}",
                (x, y, 0.006),
                (0.045, 0.040, 0.012),
                materials["rubber"],
                collection,
                chamfer=0.003,
            )

    validation = validate_collection(C4_COLLECTION)
    validation["design_contract"] = {
        "gameplay_footprint_m": [0.42, 0.28],
        "origin": "bottom_center",
        "external_textures": 0,
        "skins": 0,
        "animations": 0,
    }
    return validation


def build_all() -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    remove_collection(C4_COLLECTION)
    materials = _materials()
    validation = build_device(materials)

    runtime_output = PROJECT_ROOT / "assets" / "models" / "objectives" / "c4_device.glb"
    export_count = export_collection_glb(C4_COLLECTION, runtime_output)

    source_blend = (
        PROJECT_ROOT
        / "assets-source"
        / "blender"
        / "objectives"
        / "c4_device_source.blend"
    )
    source_blend.parent.mkdir(parents=True, exist_ok=True)
    previous_save_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(source_blend))
    finally:
        bpy.context.preferences.filepaths.save_version = previous_save_versions

    return {
        "asset_id": "VB-OBJECTIVE-C4",
        "collection": C4_COLLECTION,
        "exported_objects": export_count,
        "runtime_output": str(runtime_output),
        "source_blend": str(source_blend),
        "validation": validation,
    }


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
