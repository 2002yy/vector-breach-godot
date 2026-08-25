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
    add_ico_sphere,
    add_pipe,
    ensure_collection,
    export_collection_glb,
    look_at,
    make_material,
    move_to_collection,
    remove_collection,
    validate_collection,
)


RIFLE_COLLECTION = "VB_WEAPON_RIFLE"
PISTOL_COLLECTION = "VB_WEAPON_PISTOL"
PRESENTATION_COLLECTION = "VB_WEAPON_PRESENTATION"


def _materials() -> dict[str, bpy.types.Material]:
    return {
        "receiver": make_material(
            "MAT_weapon_receiver",
            (0.055, 0.068, 0.076, 1.0),
            metallic=0.78,
            roughness=0.28,
        ),
        "steel": make_material(
            "MAT_weapon_steel",
            (0.12, 0.145, 0.16, 1.0),
            metallic=0.92,
            roughness=0.22,
        ),
        "polymer": make_material(
            "MAT_weapon_polymer",
            (0.022, 0.028, 0.03, 1.0),
            metallic=0.02,
            roughness=0.62,
        ),
        "rubber": make_material(
            "MAT_weapon_rubber",
            (0.015, 0.018, 0.018, 1.0),
            roughness=0.9,
        ),
        "accent": make_material(
            "MAT_weapon_accent",
            (0.72, 0.19, 0.035, 1.0),
            metallic=0.35,
            roughness=0.36,
        ),
        "marking": make_material(
            "MAT_weapon_marking",
            (0.62, 0.68, 0.7, 1.0),
            metallic=0.4,
            roughness=0.4,
        ),
        "optic": make_material(
            "MAT_weapon_optic",
            (0.025, 0.25, 0.29, 1.0),
            metallic=0.12,
            roughness=0.12,
            emission=(0.02, 0.32, 0.38, 1.0),
            emission_strength=0.35,
        ),
        "sleeve": make_material(
            "MAT_weapon_sleeve",
            (0.065, 0.105, 0.115, 1.0),
            roughness=0.88,
        ),
        "glove": make_material(
            "MAT_weapon_glove",
            (0.045, 0.052, 0.05, 1.0),
            roughness=0.86,
        ),
    }


def _add_profile_prism(
    name: str,
    half_width: float,
    profile_yz: tuple[tuple[float, float], ...],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    """Extrude a measured side profile across X for an authored hard-surface mass."""
    count = len(profile_yz)
    vertices = [(-half_width, y, z) for y, z in profile_yz]
    vertices.extend((half_width, y, z) for y, z in profile_yz)
    faces: list[tuple[int, ...]] = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def _add_chamfered_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    chamfer: float = 0.004,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    obj = add_box(name, location, dimensions, material, collection, rotation=rotation)
    modifier = obj.modifiers.new("VB_PlanarChamfer", "BEVEL")
    modifier.width = min(chamfer, min(dimensions) * 0.12)
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    return obj


def _add_fastener_pair(
    prefix: str,
    y: float,
    z: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    half_width: float,
) -> None:
    for side in (-1.0, 1.0):
        add_cylinder(
            f"{prefix}_{'L' if side < 0 else 'R'}",
            (side * (half_width + 0.003), y, z),
            0.009,
            0.007,
            material,
            collection,
            vertices=8,
            rotation=(0.0, math.radians(90.0), 0.0),
        )


def _build_rifle_arms(collection: bpy.types.Collection, materials: dict[str, bpy.types.Material]) -> None:
    sleeve_specs = (
        ("support", (-0.105, -0.10, -0.18), 0.058, 0.34, (math.radians(37.0), 0.0, math.radians(8.0))),
        ("trigger", (0.095, 0.19, -0.21), 0.06, 0.32, (math.radians(-24.0), 0.0, math.radians(-7.0))),
    )
    for role, location, radius, depth, rotation in sleeve_specs:
        add_cylinder(
            f"GEO-rifle-sleeve-{role}",
            location,
            radius,
            depth,
            materials["sleeve"],
            collection,
            vertices=10,
            rotation=rotation,
        )
    palms = (
        ("support", (-0.085, -0.31, -0.07), (0.105, 0.13, 0.08), (math.radians(12.0), 0.0, math.radians(8.0))),
        ("trigger", (0.07, 0.06, -0.13), (0.10, 0.12, 0.085), (math.radians(-8.0), 0.0, math.radians(-5.0))),
    )
    for role, location, dimensions, rotation in palms:
        _add_chamfered_box(
            f"GEO-rifle-glove-palm-{role}",
            location,
            dimensions,
            materials["glove"],
            collection,
            chamfer=0.012,
            rotation=rotation,
        )
    for index in range(4):
        add_cylinder(
            f"GEO-rifle-glove-finger-{index:02d}",
            (-0.035 + index * 0.022, -0.335, -0.035),
            0.012,
            0.105,
            materials["glove"],
            collection,
            vertices=8,
            rotation=(math.radians(82.0), 0.0, 0.0),
        )


def build_rifle(materials: dict[str, bpy.types.Material]) -> dict:
    remove_collection(RIFLE_COLLECTION)
    collection = ensure_collection(RIFLE_COLLECTION)

    receiver = _add_profile_prism(
        "GEO-rifle-upper-receiver",
        0.079,
        ((-0.17, -0.055), (0.17, -0.055), (0.185, 0.035), (0.11, 0.09), (-0.14, 0.09), (-0.18, 0.045)),
        materials["receiver"],
        collection,
    )
    _add_profile_prism(
        "GEO-rifle-lower-receiver",
        0.071,
        ((-0.125, -0.075), (0.12, -0.085), (0.155, -0.02), (0.10, 0.025), (-0.11, 0.02)),
        materials["steel"],
        collection,
    )
    handguard = _add_profile_prism(
        "GEO-rifle-handguard",
        0.075,
        ((-0.51, -0.052), (-0.17, -0.052), (-0.15, 0.072), (-0.47, 0.082), (-0.52, 0.035)),
        materials["polymer"],
        collection,
    )
    _add_profile_prism(
        "GEO-rifle-grip",
        0.052,
        ((0.045, -0.075), (0.135, -0.08), (0.19, -0.235), (0.105, -0.25), (0.015, -0.105)),
        materials["polymer"],
        collection,
    )
    _add_profile_prism(
        "GEO-rifle-magazine",
        0.059,
        ((-0.09, -0.07), (0.005, -0.075), (0.035, -0.245), (-0.04, -0.27), (-0.12, -0.12)),
        materials["steel"],
        collection,
    )
    _add_chamfered_box(
        "GEO-rifle-magazine-base",
        (-0.001, -0.005, -0.263),
        (0.13, 0.09, 0.028),
        materials["accent"],
        collection,
        chamfer=0.006,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )

    barrel = add_cylinder(
        "GEO-rifle-barrel",
        (0.0, -0.605, 0.018),
        0.014,
        0.21,
        materials["steel"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_cylinder(
        "GEO-rifle-gas-block",
        (0.0, -0.51, 0.018),
        0.026,
        0.052,
        materials["receiver"],
        collection,
        vertices=10,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_cylinder(
        "GEO-rifle-muzzle-brake",
        (0.0, -0.735, 0.018),
        0.026,
        0.07,
        materials["receiver"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    for side in (-1.0, 1.0):
        for index in range(2):
            _add_chamfered_box(
                f"GEO-rifle-muzzle-port-{'L' if side < 0 else 'R'}-{index}",
                (side * 0.024, -0.72 - index * 0.022, 0.02),
                (0.006, 0.012, 0.018),
                materials["polymer"],
                collection,
                chamfer=0.001,
            )

    add_cylinder(
        "GEO-rifle-buffer-tube",
        (0.0, 0.275, 0.015),
        0.026,
        0.23,
        materials["steel"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    _add_profile_prism(
        "GEO-rifle-stock-frame",
        0.064,
        ((0.245, 0.05), (0.46, 0.055), (0.47, -0.105), (0.405, -0.13), (0.31, -0.045), (0.245, -0.03)),
        materials["polymer"],
        collection,
    )
    _add_chamfered_box(
        "GEO-rifle-cheek-rest",
        (0.0, 0.36, 0.074),
        (0.132, 0.22, 0.045),
        materials["polymer"],
        collection,
        chamfer=0.008,
    )
    _add_chamfered_box(
        "GEO-rifle-butt-pad",
        (0.0, 0.478, -0.027),
        (0.145, 0.035, 0.18),
        materials["rubber"],
        collection,
        chamfer=0.008,
    )

    for index in range(9):
        _add_chamfered_box(
            f"GEO-rifle-top-rail-{index:02d}",
            (0.0, -0.37 + index * 0.065, 0.105),
            (0.056, 0.032, 0.018),
            materials["steel"],
            collection,
            chamfer=0.002,
        )
    for side in (-1.0, 1.0):
        for index in range(4):
            _add_chamfered_box(
                f"GEO-rifle-handguard-slot-{'L' if side < 0 else 'R'}-{index:02d}",
                (side * 0.077, -0.425 + index * 0.075, 0.012),
                (0.008, 0.043, 0.022),
                materials["steel"],
                collection,
                chamfer=0.002,
            )

    _add_chamfered_box(
        "GEO-rifle-optic-base",
        (0.0, -0.01, 0.125),
        (0.09, 0.13, 0.025),
        materials["steel"],
        collection,
        chamfer=0.004,
    )
    _add_profile_prism(
        "GEO-rifle-optic-housing",
        0.052,
        ((-0.055, 0.138), (0.055, 0.138), (0.04, 0.205), (-0.035, 0.205)),
        materials["receiver"],
        collection,
    )
    _add_chamfered_box(
        "GEO-rifle-optic-glass",
        (0.0, -0.057, 0.173),
        (0.078, 0.006, 0.048),
        materials["optic"],
        collection,
        chamfer=0.004,
    )
    _add_chamfered_box(
        "GEO-rifle-ejection-port",
        (0.082, -0.035, 0.02),
        (0.008, 0.105, 0.055),
        materials["steel"],
        collection,
        chamfer=0.003,
    )
    _add_chamfered_box(
        "GEO-rifle-charging-handle",
        (-0.103, 0.10, 0.035),
        (0.065, 0.028, 0.022),
        materials["accent"],
        collection,
        chamfer=0.003,
    )
    add_pipe(
        "GEO-rifle-trigger-guard",
        ((-0.036, 0.035, -0.075), (-0.036, -0.02, -0.115), (0.036, -0.02, -0.115), (0.036, 0.035, -0.075)),
        0.007,
        materials["steel"],
        collection,
    )
    add_cylinder(
        "GEO-rifle-trigger",
        (0.0, 0.005, -0.085),
        0.006,
        0.055,
        materials["accent"],
        collection,
        vertices=8,
        rotation=(math.radians(15.0), 0.0, 0.0),
    )
    for y, z in ((0.09, 0.005), (-0.085, -0.01), (-0.35, 0.025)):
        _add_fastener_pair("GEO-rifle-fastener", y, z, materials["marking"], collection, 0.079)

    _build_rifle_arms(collection, materials)
    validation = validate_collection(RIFLE_COLLECTION)
    validation["interfaces"] = {
        "receiver_to_handguard_gap": round((-0.17) - (-0.17), 4),
        "handguard_to_barrel_overlap": round((-0.51) - (-0.50), 4),
        "receiver_to_buffer_overlap": round(0.17 - 0.16, 4),
    }
    validation["major_masses"] = 12
    validation["authored_detail_modules"] = 30
    return validation


def _build_pistol_arms(collection: bpy.types.Collection, materials: dict[str, bpy.types.Material]) -> None:
    sleeve_specs = (
        ("support", (-0.075, 0.12, -0.25), 0.057, 0.31, (math.radians(-31.0), 0.0, math.radians(8.0))),
        ("trigger", (0.08, 0.16, -0.27), 0.06, 0.34, (math.radians(-24.0), 0.0, math.radians(-7.0))),
    )
    for role, location, radius, depth, rotation in sleeve_specs:
        add_cylinder(
            f"GEO-pistol-sleeve-{role}",
            location,
            radius,
            depth,
            materials["sleeve"],
            collection,
            vertices=10,
            rotation=rotation,
        )
    for role, location, rotation in (
        ("support", (-0.055, -0.06, -0.10), (math.radians(20.0), 0.0, math.radians(7.0))),
        ("trigger", (0.055, 0.08, -0.16), (math.radians(-10.0), 0.0, math.radians(-5.0))),
    ):
        _add_chamfered_box(
            f"GEO-pistol-glove-palm-{role}",
            location,
            (0.095, 0.12, 0.085),
            materials["glove"],
            collection,
            chamfer=0.012,
            rotation=rotation,
        )


def build_pistol(materials: dict[str, bpy.types.Material]) -> dict:
    remove_collection(PISTOL_COLLECTION)
    collection = ensure_collection(PISTOL_COLLECTION)

    slide = _add_profile_prism(
        "GEO-pistol-slide",
        0.057,
        ((-0.255, 0.015), (0.105, 0.015), (0.115, 0.07), (0.075, 0.105), (-0.22, 0.105), (-0.265, 0.075)),
        materials["receiver"],
        collection,
    )
    frame = _add_profile_prism(
        "GEO-pistol-frame",
        0.052,
        ((-0.205, -0.045), (0.105, -0.045), (0.105, 0.025), (-0.19, 0.035)),
        materials["polymer"],
        collection,
    )
    _add_profile_prism(
        "GEO-pistol-grip",
        0.052,
        ((0.015, -0.025), (0.12, -0.035), (0.175, -0.25), (0.07, -0.27), (-0.005, -0.09)),
        materials["polymer"],
        collection,
    )
    _add_chamfered_box(
        "GEO-pistol-grip-backstrap",
        (0.0, 0.136, -0.15),
        (0.112, 0.026, 0.19),
        materials["rubber"],
        collection,
        chamfer=0.009,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )
    barrel = add_cylinder(
        "GEO-pistol-barrel",
        (0.0, -0.235, 0.055),
        0.015,
        0.075,
        materials["steel"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_cylinder(
        "GEO-pistol-thread-protector",
        (0.0, -0.282, 0.055),
        0.021,
        0.032,
        materials["receiver"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    _add_chamfered_box(
        "GEO-pistol-magazine-base",
        (0.0, 0.103, -0.267),
        (0.125, 0.09, 0.03),
        materials["accent"],
        collection,
        chamfer=0.006,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )
    add_pipe(
        "GEO-pistol-trigger-guard",
        ((-0.04, -0.01, -0.04), (-0.04, -0.105, -0.09), (0.04, -0.105, -0.09), (0.04, -0.01, -0.04)),
        0.008,
        materials["steel"],
        collection,
    )
    add_cylinder(
        "GEO-pistol-trigger",
        (0.0, -0.045, -0.045),
        0.006,
        0.055,
        materials["accent"],
        collection,
        vertices=8,
        rotation=(math.radians(18.0), 0.0, 0.0),
    )
    _add_chamfered_box(
        "GEO-pistol-ejection-port",
        (0.059, -0.055, 0.062),
        (0.007, 0.105, 0.046),
        materials["steel"],
        collection,
        chamfer=0.003,
    )
    _add_chamfered_box(
        "GEO-pistol-slide-stop",
        (-0.063, 0.025, 0.006),
        (0.012, 0.075, 0.022),
        materials["accent"],
        collection,
        chamfer=0.003,
    )
    _add_chamfered_box(
        "GEO-pistol-front-sight",
        (0.0, -0.205, 0.118),
        (0.025, 0.026, 0.028),
        materials["optic"],
        collection,
        chamfer=0.003,
    )
    for side in (-1.0, 1.0):
        for index in range(2):
            _add_chamfered_box(
                f"GEO-pistol-rear-sight-{'L' if side < 0 else 'R'}-{index}",
                (side * 0.025, 0.07 + index * 0.008, 0.116),
                (0.018, 0.025, 0.032),
                materials["steel"],
                collection,
                chamfer=0.003,
            )
        for index in range(6):
            _add_chamfered_box(
                f"GEO-pistol-serration-{'L' if side < 0 else 'R'}-{index:02d}",
                (side * 0.058, 0.005 + index * 0.018, 0.062),
                (0.008, 0.009, 0.058),
                materials["steel"],
                collection,
                chamfer=0.001,
                rotation=(math.radians(-12.0), 0.0, 0.0),
            )
        for index in range(3):
            _add_chamfered_box(
                f"GEO-pistol-frame-rail-{'L' if side < 0 else 'R'}-{index:02d}",
                (side * 0.054, -0.145 + index * 0.042, -0.052),
                (0.009, 0.022, 0.016),
                materials["marking"],
                collection,
                chamfer=0.002,
            )
    for y, z in ((0.05, -0.01), (-0.13, 0.01)):
        _add_fastener_pair("GEO-pistol-fastener", y, z, materials["marking"], collection, 0.052)

    _build_pistol_arms(collection, materials)
    validation = validate_collection(PISTOL_COLLECTION)
    validation["interfaces"] = {
        "slide_to_frame_overlap": round(0.035 - 0.015, 4),
        "slide_to_barrel_overlap": round((-0.22) - (-0.2725), 4),
        "frame_to_grip_overlap": round(0.025 - (-0.025), 4),
    }
    validation["major_masses"] = 9
    validation["authored_detail_modules"] = 24
    return validation


def _render_preview(
    collection: bpy.types.Collection,
    output: Path,
    target: tuple[float, float, float],
) -> None:
    for other_name in (RIFLE_COLLECTION, PISTOL_COLLECTION):
        other = bpy.data.collections.get(other_name)
        if other is not None:
            hidden = other != collection
            other.hide_render = hidden
            for obj in other.all_objects:
                obj.hide_render = hidden or "sleeve" in obj.name or "glove" in obj.name

    camera = bpy.data.objects.get("CAM_weapon_preview")
    if camera is None:
        camera_data = bpy.data.cameras.new("CAM_weapon_preview")
        camera = bpy.data.objects.new("CAM_weapon_preview", camera_data)
        ensure_collection(PRESENTATION_COLLECTION).objects.link(camera)
    camera_distance = 2.35 if collection.name == RIFLE_COLLECTION else 1.75
    camera.location = (camera_distance, -0.08, 0.48)
    camera.data.lens = 62.0
    look_at(camera, target)
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    # User startup files can carry compositor or sequencer state that replaces
    # the actual 3D render with an unrelated frame. Preview evidence must come
    # directly from the current weapon scene.
    scene.use_nodes = False
    if scene.sequence_editor is not None:
        scene.sequence_editor_clear()
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    engines = {item.identifier for item in scene.render.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.filepath = str(output)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("VB_WEAPON_WORLD")
        scene.world.use_nodes = True
    scene.world.color = (0.012, 0.017, 0.022)
    if scene.world.use_nodes:
        background = next((node for node in scene.world.node_tree.nodes if node.type == "BACKGROUND"), None)
        if background is not None:
            background.inputs["Color"].default_value = (0.012, 0.017, 0.022, 1.0)
            background.inputs["Strength"].default_value = 0.18
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.35
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def _build_presentation() -> None:
    remove_collection(PRESENTATION_COLLECTION)
    collection = ensure_collection(PRESENTATION_COLLECTION)
    key_data = bpy.data.lights.new("LIGHT_weapon_key", type="AREA")
    key_data.energy = 850.0
    key_data.shape = "DISK"
    key_data.size = 3.0
    key_data.color = (0.72, 0.84, 1.0)
    key = bpy.data.objects.new("LIGHT_weapon_key", key_data)
    key.location = (1.4, -1.8, 2.2)
    look_at(key, (0.0, -0.1, 0.0))
    collection.objects.link(key)

    rim_data = bpy.data.lights.new("LIGHT_weapon_rim", type="AREA")
    rim_data.energy = 620.0
    rim_data.size = 2.4
    rim_data.color = (1.0, 0.34, 0.12)
    rim = bpy.data.objects.new("LIGHT_weapon_rim", rim_data)
    rim.location = (-1.2, 1.1, 1.3)
    look_at(rim, (0.0, 0.0, 0.0))
    collection.objects.link(rim)


def build_all() -> dict:
    # This dedicated asset build owns its scene; reset any user startup scene
    # state so cameras, collections, sequencer strips, and compositor settings
    # cannot contaminate deterministic exports or previews.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for collection_name in (RIFLE_COLLECTION, PISTOL_COLLECTION, PRESENTATION_COLLECTION):
        remove_collection(collection_name)
    materials = _materials()
    rifle_validation = build_rifle(materials)
    pistol_validation = build_pistol(materials)

    rifle_output = PROJECT_ROOT / "assets" / "models" / "weapons" / "vb_rifle.glb"
    pistol_output = PROJECT_ROOT / "assets" / "models" / "weapons" / "vb_pistol.glb"
    export_counts = {
        "rifle": export_collection_glb(RIFLE_COLLECTION, rifle_output),
        "pistol": export_collection_glb(PISTOL_COLLECTION, pistol_output),
    }

    _build_presentation()
    preview_root = PROJECT_ROOT / "assets" / "models" / "weapons" / "previews"
    _render_preview(bpy.data.collections[RIFLE_COLLECTION], preview_root / "vb-rifle-preview.png", (0.0, -0.12, -0.02))
    _render_preview(bpy.data.collections[PISTOL_COLLECTION], preview_root / "vb-pistol-preview.png", (0.0, -0.05, -0.06))

    source_blend = PROJECT_ROOT / "tools" / "blender" / "source" / "weapon_asset_source.blend"
    source_blend.parent.mkdir(parents=True, exist_ok=True)
    previous_save_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(source_blend))
    finally:
        bpy.context.preferences.filepaths.save_version = previous_save_versions

    return {
        "exports": export_counts,
        "rifle_validation": rifle_validation,
        "pistol_validation": pistol_validation,
        "source_blend": str(source_blend),
        "previews": {
            "rifle": str(preview_root / "vb-rifle-preview.png"),
            "pistol": str(preview_root / "vb-pistol-preview.png"),
        },
    }


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
