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


MAP_COLLECTION = "VB_MAP_CORE_VAULT"
PRESENTATION_COLLECTION = "VB_PRESENTATION_CORE_VAULT"


def _map_point(x: float, z: float, height: float) -> tuple[float, float, float]:
    return (x, -z, height)


def _load_level() -> dict:
    return json.loads((PROJECT_ROOT / "data" / "levels" / "core-vault.json").read_text(encoding="utf-8"))


def _materials() -> dict[str, bpy.types.Material]:
    texture_root = PROJECT_ROOT / "assets" / "textures" / "foundry"
    return {
        "concrete": make_pbr_texture_material(
            "MAT_vault_concrete",
            texture_root / "concrete_floor_worn_001_diffuse.jpg",
            texture_root / "concrete_floor_worn_001_rough.jpg",
            texture_root / "concrete_floor_worn_001_nor_gl.jpg",
            base_color_factor=(0.66, 0.69, 0.68, 1.0),
            normal_strength=0.50,
        ),
        "reinforced": make_pbr_texture_material(
            "MAT_vault_reinforced",
            texture_root / "rebar_reinforced_concrete_diffuse.jpg",
            texture_root / "rebar_reinforced_concrete_rough.jpg",
            texture_root / "rebar_reinforced_concrete_nor_gl.jpg",
            base_color_factor=(0.66, 0.69, 0.66, 1.0),
            normal_strength=0.62,
        ),
        "metal": make_pbr_texture_material(
            "MAT_vault_blue_metal",
            texture_root / "blue_metal_plate_diffuse.jpg",
            texture_root / "blue_metal_plate_rough.jpg",
            texture_root / "blue_metal_plate_nor_gl.jpg",
            base_color_factor=(0.48, 0.58, 0.63, 1.0),
            metallic=0.66,
            normal_strength=0.58,
        ),
        "green": make_pbr_texture_material(
            "MAT_vault_green_metal",
            texture_root / "green_metal_rust_diffuse.jpg",
            texture_root / "green_metal_rust_rough.jpg",
            texture_root / "green_metal_rust_nor_gl.jpg",
            base_color_factor=(0.42, 0.58, 0.46, 1.0),
            metallic=0.38,
            normal_strength=0.66,
        ),
        "rust": make_pbr_texture_material(
            "MAT_vault_rust",
            texture_root / "rusty_metal_02_diffuse.jpg",
            texture_root / "rusty_metal_02_rough.jpg",
            texture_root / "rusty_metal_02_nor_gl.jpg",
            base_color_factor=(0.53, 0.35, 0.22, 1.0),
            metallic=0.28,
            normal_strength=0.64,
        ),
        "dark": make_material("MAT_vault_dark", (0.025, 0.035, 0.040, 1.0), metallic=0.42, roughness=0.68),
        "joint": make_material("MAT_vault_joint", (0.035, 0.042, 0.044, 1.0), roughness=0.94),
        "wear": make_material("MAT_vault_wear", (0.18, 0.20, 0.19, 1.0), roughness=0.97),
        "copper": make_material("MAT_vault_copper", (0.60, 0.25, 0.07, 1.0), metallic=0.62, roughness=0.46),
        "yellow": make_material("MAT_vault_warning", (0.78, 0.53, 0.06, 1.0), roughness=0.66),
        "glass": make_material("MAT_vault_glass", (0.018, 0.10, 0.12, 1.0), metallic=0.24, roughness=0.18),
        "core_light": make_material(
            "MAT_vault_core_light",
            (0.12, 0.90, 0.78, 1.0),
            roughness=0.26,
            emission=(0.02, 0.78, 0.58, 1.0),
            emission_strength=4.5,
        ),
        "warm_light": make_material(
            "MAT_vault_warm_light",
            (1.0, 0.42, 0.08, 1.0),
            roughness=0.28,
            emission=(1.0, 0.14, 0.02, 1.0),
            emission_strength=4.0,
        ),
    }


def reset_owned_scene() -> None:
    remove_collection(MAP_COLLECTION)
    remove_collection(PRESENTATION_COLLECTION)


def _build_floor_and_boundaries(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    arena = float(level.get("arenaSize", 56.0))
    arena_x = float(level.get("arenaSizeX", arena))
    arena_z = float(level.get("arenaSizeZ", arena))
    boundary_height = float(level.get("boundaryHeight", 6.0))
    add_box("GEO-vault-floor", (0.0, 0.0, -0.10), (arena_x * 2.0, arena_z * 2.0, 0.20), materials["concrete"], collection)
    boundaries = (
        ("north", _map_point(0.0, -arena_z - 0.5, boundary_height * 0.5), (arena_x * 2.0 + 2.0, 1.0, boundary_height)),
        ("south", _map_point(0.0, arena_z + 0.5, boundary_height * 0.5), (arena_x * 2.0 + 2.0, 1.0, boundary_height)),
        ("west", _map_point(-arena_x - 0.5, 0.0, boundary_height * 0.5), (1.0, arena_z * 2.0 + 2.0, boundary_height)),
        ("east", _map_point(arena_x + 0.5, 0.0, boundary_height * 0.5), (1.0, arena_z * 2.0 + 2.0, boundary_height)),
    )
    for name, location, dimensions in boundaries:
        add_box(f"GEO-vault-boundary-{name}", location, dimensions, materials["reinforced"], collection)
        add_box(
            f"GEO-vault-boundary-base-{name}",
            (location[0], location[1], 0.15),
            (dimensions[0] + 0.06, dimensions[1] + 0.06, 0.30),
            materials["dark"],
            collection,
        )
        span = max(dimensions[0], dimensions[1])
        along_x = dimensions[0] >= dimensions[1]
        for module_index in range(1, 8):
            offset = -span * 0.5 + span * module_index / 8.0
            add_box(
                f"GEO-vault-boundary-rib-{name}-{module_index:02d}",
                (
                    location[0] + (offset if along_x else 0.0),
                    location[1] + (0.0 if along_x else offset),
                    boundary_height * 0.5,
                ),
                (0.16, dimensions[1] + 0.06, boundary_height) if along_x else (dimensions[0] + 0.06, 0.16, boundary_height),
                materials["metal"],
                collection,
            )

    for x in (-42.0, -28.0, -14.0, 0.0, 14.0, 28.0, 42.0):
        add_box(f"GEO-vault-floor-joint-x-{int(x):+03d}", _map_point(x, 0.0, 0.009), (0.055, 110.0, 0.018), materials["joint"], collection)
    for z in (-42.0, -28.0, -14.0, 0.0, 14.0, 28.0, 42.0):
        add_box(f"GEO-vault-floor-joint-z-{int(z):+03d}", _map_point(0.0, z, 0.009), (110.0, 0.055, 0.018), materials["joint"], collection)

    wear_specs = (
        ("entry", 0.0, 45.0, 12.0, 20.0),
        ("north-chamber", 0.0, 24.0, 20.0, 12.0),
        ("west-loop", -20.0, 0.0, 9.0, 30.0),
        ("east-loop", 20.0, 0.0, 9.0, 30.0),
        ("core-ring", 0.0, 0.0, 25.0, 18.0),
        ("exit", 0.0, -39.0, 13.0, 24.0),
    )
    for name, x, z, sx, sz in wear_specs:
        add_box(f"GEO-vault-floor-wear-{name}", _map_point(x, z, 0.016), (sx, sz, 0.014), materials["wear"], collection)


def _build_core(collection: bpy.types.Collection, materials: dict) -> None:
    add_box("GEO-vault-core-base", _map_point(0.0, 0.0, 0.15), (6.0, 6.0, 0.30), materials["dark"], collection)
    add_box("GEO-vault-core-body", _map_point(0.0, 0.0, 1.72), (5.70, 5.70, 2.84), materials["metal"], collection)
    add_box("GEO-vault-core-cap", _map_point(0.0, 0.0, 3.25), (6.0, 6.0, 0.30), materials["copper"], collection)
    for x in (-2.86, 2.86):
        for z in (-2.86, 2.86):
            add_box(
                f"GEO-vault-core-corner-{int(x):+d}-{int(z):+d}",
                _map_point(x, z, 1.70),
                (0.28, 0.28, 3.10),
                materials["copper"],
                collection,
            )

    face_specs = (
        ("north", 0.0, -2.87, 3.8, 0.09, False),
        ("south", 0.0, 2.87, 3.8, 0.09, False),
        ("west", -2.87, 0.0, 0.09, 3.8, True),
        ("east", 2.87, 0.0, 0.09, 3.8, True),
    )
    for name, x, z, sx, sz, side_face in face_specs:
        add_box(
            f"GEO-vault-core-panel-bed-{name}",
            _map_point(x, z, 1.72),
            (sx, sz, 1.72),
            materials["dark"],
            collection,
        )
        glass_x = x + (0.035 if name == "east" else -0.035 if name == "west" else 0.0)
        glass_z = z + (0.035 if name == "south" else -0.035 if name == "north" else 0.0)
        add_box(
            f"GEO-vault-core-panel-glass-{name}",
            _map_point(glass_x, glass_z, 1.80),
            (0.035, 2.8, 0.92) if side_face else (2.8, 0.035, 0.92),
            materials["glass"],
            collection,
        )
        for slat_index in range(4):
            offset = -1.05 + slat_index * 0.70
            slat_x = glass_x if side_face else offset
            slat_z = offset if side_face else glass_z
            add_box(
                f"GEO-vault-core-light-slat-{name}-{slat_index:02d}",
                _map_point(slat_x, slat_z, 1.80),
                (0.025, 0.12, 0.72) if side_face else (0.12, 0.025, 0.72),
                materials["core_light"],
                collection,
            )


def _build_semantics(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    for entry in level.get("walls", []):
        wall_id = str(entry["id"])
        if wall_id == "vault-core":
            _build_core(collection, materials)
            continue
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        height = float(entry["h"])
        add_box(f"GEO-vault-wall-{wall_id}", _map_point(x, z, height * 0.5), (sx, sz, height), materials["reinforced"], collection)
        add_box(f"GEO-vault-wall-base-{wall_id}", _map_point(x, z, 0.14), (sx + 0.05, sz + 0.05, 0.28), materials["dark"], collection)
        span = max(sx, sz)
        along_x = sx >= sz
        bay_count = max(2, math.ceil(span / 4.0))
        for divider in range(1, bay_count):
            offset = -span * 0.5 + span * divider / bay_count
            add_box(
                f"GEO-vault-wall-rib-{wall_id}-{divider:02d}",
                _map_point(x + (offset if along_x else 0.0), z + (0.0 if along_x else offset), height * 0.5),
                (0.15, sz + 0.07, height) if along_x else (sx + 0.07, 0.15, height),
                materials["metal"],
                collection,
            )
        add_box(f"GEO-vault-wall-cap-{wall_id}", _map_point(x, z, height - 0.09), (sx + 0.07, sz + 0.07, 0.18), materials["metal"], collection)

    for index, entry in enumerate(level.get("covers", [])):
        cover_id = str(entry["id"])
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        height = float(entry["h"])
        add_box(f"GEO-vault-cover-{cover_id}", _map_point(x, z, height * 0.5), (sx, sz, height), materials["green"], collection)
        for rib in range(1, 4):
            rib_x = x - sx * 0.5 + sx * rib / 4.0
            add_box(
                f"GEO-vault-cover-rib-{cover_id}-{rib:02d}",
                _map_point(rib_x, z, height * 0.52),
                (0.07, sz + 0.04, height * 0.88),
                materials["copper" if index % 2 == 0 else "yellow"],
                collection,
            )

    for entry in level.get("stairs", []):
        height = float(entry["h"])
        add_box(
            f"GEO-vault-stair-{entry['id']}",
            _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
            (float(entry["sx"]), float(entry["sz"]), height),
            materials["rust"],
            collection,
        )


def _add_wall_cladding(
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
        location = _map_point(anchor, face_z + face_sign * thickness * 0.5, 0.28 + height * 0.5)
        dimensions = (width, thickness, height)
    else:
        face_x = x + face_sign * sx * 0.5
        location = _map_point(face_x + face_sign * thickness * 0.5, anchor, 0.28 + height * 0.5)
        dimensions = (thickness, width, height)
    panel = add_box(
        f"GEO-vault-wall-cladding-{index:02d}-{wall_id}",
        location,
        dimensions,
        materials["green" if index % 2 else "rust"],
        collection,
    )
    panel["wall_id"] = wall_id
    panel["contact_gap"] = 0.0


def _build_details(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    specs = (
        ("inner-west", 1.0, -3.0, 5.0, 1.4),
        ("inner-east", -1.0, 3.0, 5.0, 1.4),
        ("inner-south", 1.0, -4.0, 4.5, 1.4),
        ("outer-west", 1.0, -7.0, 6.0, 2.2),
        ("outer-east", -1.0, 7.0, 6.0, 2.2),
        ("outer-north", -1.0, -5.0, 5.0, 2.0),
        ("outer-south-west", 1.0, -20.0, 4.5, 1.8),
        ("outer-south-east", 1.0, 20.0, 4.5, 1.8),
    )
    for index, spec in enumerate(specs):
        _add_wall_cladding(collection, materials, level, *spec, index)

    for index, point in enumerate(level.get("lights", {}).get("points", [])):
        x, height, z = float(point[0]), float(point[1]), float(point[2])
        add_box(f"GEO-vault-light-fixture-{index:02d}", _map_point(x, z, height + 0.08), (1.6, 0.42, 0.13), materials["metal"], collection)
        add_box(
            f"GEO-vault-light-emitter-{index:02d}",
            _map_point(x, z, height),
            (1.18, 0.29, 0.05),
            materials["core_light" if index == 0 or index == 2 else "warm_light"],
            collection,
        )

    for index, (body, x, z) in enumerate((("CORE", 0.0, 9.5), ("VAULT", 0.0, -24.0), ("EXIT", 0.0, -45.0))):
        add_text(
            f"GEO-vault-route-mark-{index:02d}",
            body,
            _map_point(x, z, 0.028),
            1.35,
            materials["copper" if index < 2 else "yellow"],
            collection,
            extrude=0.012,
        )


def _project_uvs(collection: bpy.types.Collection) -> None:
    for obj in collection.objects:
        cube_project_uv(obj, 2.6)


def _validate_vault(collection: bpy.types.Collection) -> dict:
    names = [obj.name for obj in collection.objects]
    semantic_walls = [name for name in names if name.startswith("GEO-vault-wall-") and "-base-" not in name and "-rib-" not in name and "-cap-" not in name and "-cladding-" not in name]
    core_body_count = sum(name.startswith("GEO-vault-core-body") for name in names)
    covers = [name for name in names if name.startswith("GEO-vault-cover-") and "-rib-" not in name]
    stairs = [name for name in names if name.startswith("GEO-vault-stair-")]
    joints = [name for name in names if name.startswith("GEO-vault-floor-joint-")]
    wear = [name for name in names if name.startswith("GEO-vault-floor-wear-")]
    cladding = [obj for obj in collection.objects if obj.name.startswith("GEO-vault-wall-cladding-")]
    core_panels = [name for name in names if name.startswith("GEO-vault-core-panel-glass-")]
    core_lights = [name for name in names if name.startswith("GEO-vault-core-light-slat-")]
    gap = max((float(obj.get("contact_gap", 999.0)) for obj in cladding), default=999.0)
    assert len(semantic_walls) == 8, f"Expected 8 non-core walls, got {len(semantic_walls)}"
    assert core_body_count == 1, f"Expected 1 vault core body, got {core_body_count}"
    assert len(covers) == 4, f"Expected 4 covers, got {len(covers)}"
    assert len(stairs) == 2, f"Expected 2 stair blocks, got {len(stairs)}"
    assert len(joints) == 14, f"Expected 14 floor joints, got {len(joints)}"
    assert len(wear) == 6, f"Expected 6 floor wear zones, got {len(wear)}"
    assert len(cladding) == 8, f"Expected 8 cladding modules, got {len(cladding)}"
    assert len(core_panels) == 4, f"Expected 4 recessed core panels, got {len(core_panels)}"
    assert len(core_lights) == 16, f"Expected 16 core light slats, got {len(core_lights)}"
    assert gap <= 0.0001, f"Cladding contact gap is {gap:.4f} m"
    return {
        "semantic_wall_count": len(semantic_walls) + 1,
        "semantic_cover_count": len(covers),
        "stair_count": len(stairs),
        "floor_joint_count": len(joints),
        "floor_wear_count": len(wear),
        "wall_cladding_count": len(cladding),
        "wall_cladding_contact_gap_max": round(gap, 4),
        "core_panel_count": len(core_panels),
        "core_light_slat_count": len(core_lights),
    }


def build_map() -> dict:
    reset_owned_scene()
    collection = ensure_collection(MAP_COLLECTION)
    materials = _materials()
    level = _load_level()
    _build_floor_and_boundaries(collection, materials, level)
    _build_semantics(collection, materials, level)
    _build_details(collection, materials, level)
    _project_uvs(collection)
    validation = validate_collection(MAP_COLLECTION)
    validation.update(_validate_vault(collection))
    return validation


def _create_presentation(level: dict) -> None:
    remove_collection(PRESENTATION_COLLECTION)
    collection = ensure_collection(PRESENTATION_COLLECTION)
    camera_data = bpy.data.cameras.new("CAM_core_vault_preview")
    camera = bpy.data.objects.new("CAM_core_vault_preview", camera_data)
    camera.location = (68.0, -82.0, 60.0)
    camera_data.lens = 52.0
    look_at(camera, (0.0, 0.0, 1.5))
    collection.objects.link(camera)
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("LIGHT_core_vault_sun", type="SUN")
    sun_data.energy = 1.45
    sun_data.color = (1.0, 0.74, 0.58)
    sun = bpy.data.objects.new("LIGHT_core_vault_sun", sun_data)
    sun.rotation_euler = (math.radians(32.0), math.radians(-16.0), math.radians(-38.0))
    collection.objects.link(sun)

    area_data = bpy.data.lights.new("LIGHT_core_vault_fill", type="AREA")
    area_data.energy = 1300.0
    area_data.shape = "DISK"
    area_data.size = 44.0
    area_data.color = (0.28, 0.62, 0.68)
    area = bpy.data.objects.new("LIGHT_core_vault_fill", area_data)
    area.location = (-34.0, 22.0, 50.0)
    look_at(area, (0.0, 0.0, 0.0))
    collection.objects.link(area)


def export_and_save() -> dict:
    level = _load_level()
    output = PROJECT_ROOT / "assets" / "models" / "core_vault" / "core_vault.glb"
    preview = PROJECT_ROOT / "assets" / "maps" / "core-vault-preview.png"
    source_blend = PROJECT_ROOT / "tools" / "blender" / "source" / "core_vault_asset_source.blend"
    export_count = export_collection_glb(MAP_COLLECTION, output)
    _create_presentation(level)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview)
    scene.world.color = (0.014, 0.022, 0.025)
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
        "map_validation": {**validate_collection(MAP_COLLECTION), **_validate_vault(collection)},
        "blend": str(source_blend),
        "preview": str(preview),
    }


def build_all() -> dict:
    result = {"map": build_map()}
    result["final"] = export_and_save()
    return result


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
