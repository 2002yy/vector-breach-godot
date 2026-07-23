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
    add_text,
    cube_project_uv,
    ensure_collection,
    export_collection_glb,
    look_at,
    make_material,
    make_pbr_texture_material,
    remove_collection,
    validate_collection,
)


MAP_COLLECTION = "VB_MAP_GATEHOUSE"
PRESENTATION_COLLECTION = "VB_PRESENTATION_GATEHOUSE"


def _map_point(x: float, z: float, height: float) -> tuple[float, float, float]:
    return (x, -z, height)


def _load_level() -> dict:
    return json.loads((PROJECT_ROOT / "data" / "levels" / "gatehouse.json").read_text(encoding="utf-8"))


def _materials() -> dict[str, bpy.types.Material]:
    texture_root = PROJECT_ROOT / "assets" / "textures" / "foundry"
    return {
        "concrete": make_pbr_texture_material(
            "MAT_gatehouse_concrete",
            texture_root / "concrete_floor_worn_001_diffuse.jpg",
            texture_root / "concrete_floor_worn_001_rough.jpg",
            texture_root / "concrete_floor_worn_001_nor_gl.jpg",
            base_color_factor=(0.74, 0.75, 0.72, 1.0),
            normal_strength=0.54,
        ),
        "concrete_light": make_pbr_texture_material(
            "MAT_gatehouse_concrete_light",
            texture_root / "rebar_reinforced_concrete_diffuse.jpg",
            texture_root / "rebar_reinforced_concrete_rough.jpg",
            texture_root / "rebar_reinforced_concrete_nor_gl.jpg",
            base_color_factor=(0.82, 0.80, 0.72, 1.0),
            normal_strength=0.48,
        ),
        "metal": make_pbr_texture_material(
            "MAT_gatehouse_blue_metal",
            texture_root / "blue_metal_plate_diffuse.jpg",
            texture_root / "blue_metal_plate_rough.jpg",
            texture_root / "blue_metal_plate_nor_gl.jpg",
            base_color_factor=(0.58, 0.67, 0.72, 1.0),
            metallic=0.58,
            normal_strength=0.58,
        ),
        "green": make_pbr_texture_material(
            "MAT_gatehouse_green_metal",
            texture_root / "green_metal_rust_diffuse.jpg",
            texture_root / "green_metal_rust_rough.jpg",
            texture_root / "green_metal_rust_nor_gl.jpg",
            base_color_factor=(0.52, 0.68, 0.55, 1.0),
            metallic=0.32,
            normal_strength=0.68,
        ),
        "corrugated": make_pbr_texture_material(
            "MAT_gatehouse_corrugated",
            texture_root / "corrugated_rusty_metal_diffuse.jpg",
            texture_root / "corrugated_rusty_metal_rough.jpg",
            texture_root / "corrugated_rusty_metal_nor_gl.jpg",
            base_color_factor=(0.52, 0.39, 0.26, 1.0),
            metallic=0.28,
            normal_strength=0.72,
        ),
        "rust": make_pbr_texture_material(
            "MAT_gatehouse_rust",
            texture_root / "rusty_metal_02_diffuse.jpg",
            texture_root / "rusty_metal_02_rough.jpg",
            texture_root / "rusty_metal_02_nor_gl.jpg",
            base_color_factor=(0.62, 0.42, 0.25, 1.0),
            metallic=0.24,
            normal_strength=0.66,
        ),
        "dark": make_material("MAT_gatehouse_dark", (0.035, 0.045, 0.047, 1.0), metallic=0.25, roughness=0.78),
        "joint": make_material("MAT_gatehouse_joint", (0.045, 0.05, 0.05, 1.0), roughness=0.94),
        "wear": make_material("MAT_gatehouse_wear", (0.24, 0.23, 0.19, 1.0), roughness=0.96),
        "orange": make_material("MAT_gatehouse_orange", (0.78, 0.30, 0.035, 1.0), roughness=0.64),
        "yellow": make_material("MAT_gatehouse_yellow", (0.82, 0.58, 0.08, 1.0), roughness=0.68),
        "glass": make_material("MAT_gatehouse_glass", (0.025, 0.12, 0.14, 1.0), metallic=0.18, roughness=0.2),
        "light_warm": make_material(
            "MAT_gatehouse_light_warm",
            (1.0, 0.52, 0.12, 1.0),
            roughness=0.3,
            emission=(1.0, 0.24, 0.04, 1.0),
            emission_strength=4.0,
        ),
        "light_cool": make_material(
            "MAT_gatehouse_light_cool",
            (0.18, 0.72, 0.82, 1.0),
            roughness=0.3,
            emission=(0.03, 0.42, 0.72, 1.0),
            emission_strength=3.5,
        ),
    }


def reset_owned_scene() -> None:
    remove_collection(MAP_COLLECTION)
    remove_collection(PRESENTATION_COLLECTION)


def _build_floor_and_boundaries(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    arena_size = float(level.get("arenaSize", 56.0))
    arena_size_x = float(level.get("arenaSizeX", arena_size))
    arena_size_z = float(level.get("arenaSizeZ", arena_size))
    boundary_height = float(level.get("boundaryHeight", 6.0))
    add_box(
        "GEO-gatehouse-floor",
        (0.0, 0.0, -0.10),
        (arena_size_x * 2.0, arena_size_z * 2.0, 0.20),
        materials["concrete"],
        collection,
    )
    span_x = arena_size_x * 2.0 + 2.0
    span_z = arena_size_z * 2.0 + 2.0
    boundaries = (
        ("north", _map_point(0.0, -arena_size_z - 0.5, boundary_height * 0.5), (span_x, 1.0, boundary_height)),
        ("south", _map_point(0.0, arena_size_z + 0.5, boundary_height * 0.5), (span_x, 1.0, boundary_height)),
        ("west", _map_point(-arena_size_x - 0.5, 0.0, boundary_height * 0.5), (1.0, span_z, boundary_height)),
        ("east", _map_point(arena_size_x + 0.5, 0.0, boundary_height * 0.5), (1.0, span_z, boundary_height)),
    )
    for name, location, dimensions in boundaries:
        add_box(f"GEO-gatehouse-boundary-{name}", location, dimensions, materials["concrete_light"], collection)
        add_box(
            f"GEO-gatehouse-boundary-base-{name}",
            (location[0], location[1], 0.14),
            (dimensions[0] + 0.06, dimensions[1] + 0.06, 0.28),
            materials["dark"],
            collection,
        )

    for x in (-42.0, -28.0, -14.0, 0.0, 14.0, 28.0, 42.0):
        add_box(
            f"GEO-gatehouse-floor-joint-x-{int(x):+03d}",
            _map_point(x, 0.0, 0.009),
            (0.055, 110.0, 0.018),
            materials["joint"],
            collection,
        )
    for z in (-42.0, -28.0, -14.0, 0.0, 14.0, 28.0, 42.0):
        add_box(
            f"GEO-gatehouse-floor-joint-z-{int(z):+03d}",
            _map_point(0.0, z, 0.009),
            (110.0, 0.055, 0.018),
            materials["joint"],
            collection,
        )

    wear_specs = (
        ("south-entry", 0.0, 43.0, 13.0, 20.0),
        ("west-lane", -12.0, 20.0, 8.0, 25.0),
        ("east-lane", 12.0, 20.0, 8.0, 25.0),
        ("checkpoint", 0.0, -8.0, 16.0, 25.0),
        ("gate", 0.0, -29.0, 22.0, 10.0),
        ("north-exit", 0.0, -47.0, 13.0, 15.0),
    )
    for name, x, z, sx, sz in wear_specs:
        add_box(
            f"GEO-gatehouse-floor-wear-{name}",
            _map_point(x, z, 0.016),
            (sx, sz, 0.014),
            materials["wear"],
            collection,
        )


def _build_semantic_geometry(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    for index, entry in enumerate(level.get("walls", [])):
        height = float(entry["h"])
        wall_id = str(entry["id"])
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        add_box(
            f"GEO-gatehouse-wall-{wall_id}",
            _map_point(x, z, height * 0.5),
            (sx, sz, height),
            materials["concrete_light"],
            collection,
        )
        add_box(
            f"GEO-gatehouse-wall-base-{wall_id}",
            _map_point(x, z, 0.14),
            (sx + 0.05, sz + 0.05, 0.28),
            materials["dark"],
            collection,
        )
        span = max(sx, sz)
        along_x = sx >= sz
        bay_count = max(2, math.ceil(span / 3.5))
        for divider in range(1, bay_count):
            offset = -span * 0.5 + span * divider / bay_count
            rib_x = x + (offset if along_x else 0.0)
            rib_z = z + (0.0 if along_x else offset)
            add_box(
                f"GEO-gatehouse-wall-rib-{wall_id}-{divider:02d}",
                _map_point(rib_x, rib_z, height * 0.5),
                (0.14, sz + 0.08, height) if along_x else (sx + 0.08, 0.14, height),
                materials["metal"],
                collection,
            )
        add_box(
            f"GEO-gatehouse-wall-cap-{wall_id}",
            _map_point(x, z, height - 0.09),
            (sx + 0.07, sz + 0.07, 0.18),
            materials["metal"],
            collection,
        )

    for index, entry in enumerate(level.get("covers", [])):
        height = float(entry["h"])
        cover_id = str(entry["id"])
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        add_box(
            f"GEO-gatehouse-cover-{cover_id}",
            _map_point(x, z, height * 0.5),
            (sx, sz, height),
            materials["green" if index % 2 else "corrugated"],
            collection,
        )
        span = max(sx, sz)
        along_x = sx >= sz
        rib_count = max(2, math.ceil(span / 1.5))
        for rib in range(1, rib_count):
            offset = -span * 0.5 + span * rib / rib_count
            rib_x = x + (offset if along_x else 0.0)
            rib_z = z + (0.0 if along_x else offset)
            add_box(
                f"GEO-gatehouse-cover-rib-{cover_id}-{rib:02d}",
                _map_point(rib_x, rib_z, height * 0.52),
                (0.07, sz + 0.035, height * 0.88) if along_x else (sx + 0.035, 0.07, height * 0.88),
                materials["yellow"],
                collection,
            )

    for entry in level.get("floors", []):
        height = float(entry["h"])
        floor_id = str(entry["id"])
        add_box(
            f"GEO-gatehouse-raised-floor-{floor_id}",
            _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
            (float(entry["sx"]), float(entry["sz"]), height),
            materials["metal"],
            collection,
        )

    for entry in level.get("stairs", []):
        height = float(entry["h"])
        stair_id = str(entry["id"])
        add_box(
            f"GEO-gatehouse-stair-{stair_id}",
            _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
            (float(entry["sx"]), float(entry["sz"]), height),
            materials["rust"],
            collection,
        )


def _add_wall_panel(
    collection: bpy.types.Collection,
    materials: dict,
    level: dict,
    wall_id: str,
    face_sign: float,
    anchor: float,
    width: float,
    height: float,
    index: int,
) -> None:
    wall = next(entry for entry in level["walls"] if str(entry["id"]) == wall_id)
    x = float(wall["x"])
    z = float(wall["z"])
    sx = float(wall["sx"])
    sz = float(wall["sz"])
    thickness = 0.08
    along_x = sx >= sz
    if along_x:
        face_z = z + face_sign * sz * 0.5
        location = _map_point(anchor, face_z + face_sign * thickness * 0.5, 0.30 + height * 0.5)
        dimensions = (width, thickness, height)
    else:
        face_x = x + face_sign * sx * 0.5
        location = _map_point(face_x + face_sign * thickness * 0.5, anchor, 0.30 + height * 0.5)
        dimensions = (thickness, width, height)
    panel = add_box(
        f"GEO-gatehouse-wall-cladding-{index:02d}-{wall_id}",
        location,
        dimensions,
        materials["green" if index % 2 else "corrugated"],
        collection,
    )
    panel["wall_id"] = wall_id
    panel["contact_gap"] = 0.0


def _build_checkpoint_details(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    panel_specs = (
        ("gate-west", 1.0, -23.5, 2.8, 2.3),
        ("gate-west", -1.0, -20.5, 2.4, 2.0),
        ("gate-east", 1.0, 20.5, 2.4, 2.0),
        ("gate-east", -1.0, 23.5, 2.8, 2.3),
        ("north-west-security", 1.0, 23.0, 4.0, 2.0),
        ("north-east-security", -1.0, 25.0, 4.0, 2.0),
    )
    for index, spec in enumerate(panel_specs):
        _add_wall_panel(collection, materials, level, *spec, index)

    booth_specs = (
        ("south-east", 10.6, -6.4, 1.7, 6.2, 1.8, 1.0),
        ("mid-west", -7.2, 4.2, 1.5, 6.4, 1.6, -1.0),
    )
    for index, (name, x, z, sx, sz, height, face_sign) in enumerate(booth_specs):
        face_x = x + face_sign * sx * 0.5
        add_box(
            f"GEO-gatehouse-booth-panel-{name}-lower",
            _map_point(face_x + face_sign * 0.035, z - 1.25, 0.72),
            (0.07, 1.5, 0.72),
            materials["dark"],
            collection,
        )
        add_box(
            f"GEO-gatehouse-booth-panel-{name}-screen",
            _map_point(face_x + face_sign * 0.071, z - 1.25, 1.22),
            (0.025, 1.05, 0.42),
            materials["glass"],
            collection,
        )

    deck = next(entry for entry in level["floors"] if str(entry["id"]) == "west-inspection-deck")
    deck_top = float(deck["h"])
    deck_x = float(deck["x"])
    deck_z = float(deck["z"])
    deck_sx = float(deck["sx"])
    deck_sz = float(deck["sz"])
    border_specs = (
        ("north", deck_x, deck_z - deck_sz * 0.5 + 0.09, deck_sx - 0.2, 0.18),
        ("south", deck_x, deck_z + deck_sz * 0.5 - 0.09, deck_sx - 0.2, 0.18),
        ("west", deck_x - deck_sx * 0.5 + 0.09, deck_z, 0.18, deck_sz - 0.2),
    )
    for name, x, z, sx, sz in border_specs:
        add_box(
            f"GEO-gatehouse-deck-border-{name}",
            _map_point(x, z, deck_top + 0.045),
            (sx, sz, 0.09),
            materials["yellow"],
            collection,
        )

    for index, point in enumerate(level.get("lights", {}).get("points", [])):
        x = float(point[0])
        height = float(point[1])
        z = float(point[2])
        add_box(
            f"GEO-gatehouse-light-fixture-{index:02d}",
            _map_point(x, z, height + 0.08),
            (1.5, 0.40, 0.13),
            materials["metal"],
            collection,
        )
        add_box(
            f"GEO-gatehouse-light-emitter-{index:02d}",
            _map_point(x, z, height),
            (1.12, 0.28, 0.05),
            materials["light_warm" if index < 2 else "light_cool"],
            collection,
        )

    route_marks = (
        ("ENTRY", 0.0, 38.0, materials["orange"]),
        ("CHECK", 0.0, -12.0, materials["yellow"]),
        ("GATE", 0.0, -34.0, materials["orange"]),
    )
    for index, (body, x, z, material) in enumerate(route_marks):
        add_text(
            f"GEO-gatehouse-route-mark-{index:02d}",
            body,
            _map_point(x, z, 0.028),
            1.35,
            material,
            collection,
            extrude=0.012,
        )


def _project_collection_uvs(collection: bpy.types.Collection) -> None:
    for obj in collection.objects:
        cube_project_uv(obj, 2.8)


def _validate_gatehouse(collection: bpy.types.Collection) -> dict:
    names = [obj.name for obj in collection.objects]
    wall_count = sum(name.startswith("GEO-gatehouse-wall-") and "-base-" not in name and "-rib-" not in name and "-cap-" not in name and "-cladding-" not in name for name in names)
    cover_count = sum(name.startswith("GEO-gatehouse-cover-") and "-rib-" not in name for name in names)
    raised_floor_count = sum(name.startswith("GEO-gatehouse-raised-floor-") for name in names)
    stair_count = sum(name.startswith("GEO-gatehouse-stair-") for name in names)
    floor_joint_count = sum(name.startswith("GEO-gatehouse-floor-joint-") for name in names)
    floor_wear_count = sum(name.startswith("GEO-gatehouse-floor-wear-") for name in names)
    cladding = [obj for obj in collection.objects if obj.name.startswith("GEO-gatehouse-wall-cladding-")]
    cladding_gap = max((float(obj.get("contact_gap", 999.0)) for obj in cladding), default=999.0)
    booth_panel_count = sum(name.startswith("GEO-gatehouse-booth-panel-") for name in names)
    assert wall_count == 4, f"Expected 4 semantic walls, got {wall_count}"
    assert cover_count == 5, f"Expected 5 semantic covers, got {cover_count}"
    assert raised_floor_count == 1, f"Expected 1 raised floor, got {raised_floor_count}"
    assert stair_count == 3, f"Expected 3 stair blocks, got {stair_count}"
    assert floor_joint_count == 14, f"Expected 14 floor joints, got {floor_joint_count}"
    assert floor_wear_count == 6, f"Expected 6 floor wear zones, got {floor_wear_count}"
    assert len(cladding) == 6, f"Expected 6 cladding modules, got {len(cladding)}"
    assert booth_panel_count == 4, f"Expected 4 booth panels, got {booth_panel_count}"
    assert cladding_gap <= 0.0001, f"Cladding contact gap is {cladding_gap:.4f} m"
    return {
        "semantic_wall_count": wall_count,
        "semantic_cover_count": cover_count,
        "raised_floor_count": raised_floor_count,
        "stair_count": stair_count,
        "floor_joint_count": floor_joint_count,
        "floor_wear_count": floor_wear_count,
        "wall_cladding_count": len(cladding),
        "wall_cladding_contact_gap_max": round(cladding_gap, 4),
        "booth_panel_count": booth_panel_count,
    }


def build_map() -> dict:
    reset_owned_scene()
    collection = ensure_collection(MAP_COLLECTION)
    materials = _materials()
    level = _load_level()
    _build_floor_and_boundaries(collection, materials, level)
    _build_semantic_geometry(collection, materials, level)
    _build_checkpoint_details(collection, materials, level)
    _project_collection_uvs(collection)
    validation = validate_collection(MAP_COLLECTION)
    validation.update(_validate_gatehouse(collection))
    return validation


def _create_presentation(level: dict) -> None:
    remove_collection(PRESENTATION_COLLECTION)
    collection = ensure_collection(PRESENTATION_COLLECTION)
    camera_data = bpy.data.cameras.new("CAM_gatehouse_preview")
    camera = bpy.data.objects.new("CAM_gatehouse_preview", camera_data)
    camera.location = (72.0, -88.0, 64.0)
    camera_data.lens = 52.0
    look_at(camera, (0.0, 0.0, 1.6))
    collection.objects.link(camera)
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("LIGHT_gatehouse_sun", type="SUN")
    sun_data.energy = 1.6
    sun_data.color = (1.0, 0.82, 0.66)
    sun = bpy.data.objects.new("LIGHT_gatehouse_sun", sun_data)
    sun.rotation_euler = (math.radians(32.0), math.radians(-16.0), math.radians(-38.0))
    collection.objects.link(sun)

    area_data = bpy.data.lights.new("LIGHT_gatehouse_fill", type="AREA")
    area_data.energy = 1350.0
    area_data.shape = "DISK"
    area_data.size = 46.0
    area_data.color = (0.42, 0.62, 0.76)
    area = bpy.data.objects.new("LIGHT_gatehouse_fill", area_data)
    area.location = (-38.0, 24.0, 54.0)
    look_at(area, (0.0, 0.0, 0.0))
    collection.objects.link(area)

    for index, point in enumerate(level.get("lights", {}).get("points", [])):
        light_data = bpy.data.lights.new(f"LIGHT_gatehouse_map_{index:02d}", type="POINT")
        light_data.energy = 460.0
        light_data.shadow_soft_size = 2.0
        light = bpy.data.objects.new(f"LIGHT_gatehouse_map_{index:02d}", light_data)
        light.location = _map_point(float(point[0]), float(point[2]), float(point[1]))
        collection.objects.link(light)


def export_and_save() -> dict:
    level = _load_level()
    output = PROJECT_ROOT / "assets" / "models" / "gatehouse" / "gatehouse.glb"
    preview = PROJECT_ROOT / "assets" / "maps" / "gatehouse-preview.png"
    source_blend = PROJECT_ROOT / "tools" / "blender" / "source" / "gatehouse_asset_source.blend"
    export_count = export_collection_glb(MAP_COLLECTION, output)
    _create_presentation(level)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview)
    scene.world.color = (0.022, 0.028, 0.03)
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.34
    scene.render.film_transparent = False
    bpy.context.view_layer.update()
    bpy.ops.render.render()
    scene.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)

    source_blend.parent.mkdir(parents=True, exist_ok=True)
    previous_save_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(source_blend))
    finally:
        bpy.context.preferences.filepaths.save_version = previous_save_versions

    collection = bpy.data.collections[MAP_COLLECTION]
    return {
        "exports": {"map": export_count},
        "map_validation": {
            **validate_collection(MAP_COLLECTION),
            **_validate_gatehouse(collection),
        },
        "blend": str(source_blend),
        "preview": str(preview),
    }


def build_all() -> dict:
    result = {"map": build_map()}
    result["final"] = export_and_save()
    return result


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
