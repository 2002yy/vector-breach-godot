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
    add_text,
    cube_project_uv,
    ensure_collection,
    export_collection_glb,
    look_at,
    make_material,
    make_pbr_texture_material,
    remove_collection,
    remove_objects_with_prefix,
    set_collection_hidden,
    validate_collection,
)


MAP_COLLECTION = "VB_MAP_FOUNDRY_DEPOT"
RIFLE_COLLECTION = "VB_WEAPON_RIFLE"
PISTOL_COLLECTION = "VB_WEAPON_PISTOL"
PRESENTATION_COLLECTION = "VB_PRESENTATION"


def _map_point(x: float, z: float, height: float) -> tuple[float, float, float]:
    return (x, -z, height)


def _materials() -> dict[str, bpy.types.Material]:
    texture_root = PROJECT_ROOT / "assets" / "textures" / "foundry"
    concrete = make_pbr_texture_material(
        "MAT_concrete",
        texture_root / "concrete_floor_worn_001_diffuse.jpg",
        texture_root / "concrete_floor_worn_001_rough.jpg",
        texture_root / "concrete_floor_worn_001_nor_gl.jpg",
        normal_strength=0.52,
    )
    concrete_light = make_pbr_texture_material(
        "MAT_concrete_light",
        texture_root / "concrete_floor_worn_001_diffuse.jpg",
        texture_root / "concrete_floor_worn_001_rough.jpg",
        texture_root / "concrete_floor_worn_001_nor_gl.jpg",
        normal_strength=0.42,
    )
    metal = make_pbr_texture_material(
        "MAT_gunmetal",
        texture_root / "blue_metal_plate_diffuse.jpg",
        texture_root / "blue_metal_plate_rough.jpg",
        texture_root / "blue_metal_plate_nor_gl.jpg",
        metallic=0.72,
        normal_strength=0.62,
    )
    metal_mid = make_pbr_texture_material(
        "MAT_metal_mid",
        texture_root / "blue_metal_plate_diffuse.jpg",
        texture_root / "blue_metal_plate_rough.jpg",
        texture_root / "blue_metal_plate_nor_gl.jpg",
        metallic=0.58,
        normal_strength=0.48,
    )
    rust = make_pbr_texture_material(
        "MAT_rust_red",
        texture_root / "rusty_metal_02_diffuse.jpg",
        texture_root / "rusty_metal_02_rough.jpg",
        texture_root / "rusty_metal_02_nor_gl.jpg",
        metallic=0.28,
        normal_strength=0.7,
    )
    return {
        "concrete": concrete,
        "concrete_light": concrete_light,
        "metal": metal,
        "metal_mid": metal_mid,
        "rust": rust,
        "orange": make_material("MAT_hazard_orange", (0.95, 0.42, 0.08, 1.0), roughness=0.5),
        "yellow": make_material("MAT_hazard_yellow", (0.92, 0.67, 0.12, 1.0), roughness=0.55),
        "teal": make_material("MAT_route_teal", (0.04, 0.42, 0.44, 1.0), metallic=0.15, roughness=0.5),
        "dark": make_material("MAT_polymer_dark", (0.025, 0.03, 0.032, 1.0), roughness=0.62),
        "glass": make_material("MAT_screen_glass", (0.02, 0.08, 0.085, 1.0), metallic=0.2, roughness=0.2),
        "light": make_material(
            "MAT_emissive_warm",
            (1.0, 0.48, 0.12, 1.0),
            roughness=0.35,
            emission=(1.0, 0.18, 0.03, 1.0),
            emission_strength=4.0,
        ),
        "glove": make_material("MAT_glove", (0.085, 0.095, 0.085, 1.0), roughness=0.9),
        "skin": make_material("MAT_sleeve", (0.11, 0.16, 0.17, 1.0), roughness=0.88),
    }


def _load_depot() -> dict:
    path = PROJECT_ROOT / "data" / "levels" / "depot.json"
    return json.loads(path.read_text(encoding="utf-8"))


def reset_owned_scene() -> None:
    for name in (MAP_COLLECTION, RIFLE_COLLECTION, PISTOL_COLLECTION, PRESENTATION_COLLECTION):
        remove_collection(name)
    remove_objects_with_prefix("VB_INSPECT_")
    if not bpy.data.filepath and set(bpy.data.objects.keys()).issubset({"Cube", "Camera", "Light"}):
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)


def _add_hazard_band(
    collection: bpy.types.Collection,
    materials: dict,
    entry: dict,
    index: int,
) -> None:
    x = float(entry.get("x", 0.0))
    z = float(entry.get("z", 0.0))
    sx = float(entry.get("sx", 1.0))
    sz = float(entry.get("sz", 1.0))
    height = float(entry.get("h", 1.0))
    if sx >= sz:
        dimensions = (sx * 0.72, 0.045, 0.16)
        location = _map_point(x, z - sz * 0.505, min(height - 0.28, 1.0))
    else:
        dimensions = (0.045, sz * 0.72, 0.16)
        location = _map_point(x + sx * 0.505, z, min(height - 0.28, 1.0))
    add_box(
        f"GEO-detail_wall_band_{index:02d}",
        location,
        dimensions,
        materials["orange" if index % 2 == 0 else "teal"],
        collection,
    )


def _build_cover(collection: bpy.types.Collection, materials: dict, entry: dict, index: int) -> None:
    x = float(entry.get("x", 0.0))
    z = float(entry.get("z", 0.0))
    sx = float(entry.get("sx", 1.0))
    sz = float(entry.get("sz", 1.0))
    height = float(entry.get("h", 1.0))
    base_material = materials["rust"] if index % 2 == 0 else materials["metal_mid"]
    add_box(
        f"GEO-map_cover_{index:02d}",
        _map_point(x, z, height * 0.5),
        (sx, sz, height),
        base_material,
        collection,
    )
    rib_count = max(2, int(max(sx, sz) // 1.5))
    for rib in range(rib_count):
        t = (rib + 0.5) / rib_count - 0.5
        if sx >= sz:
            location = _map_point(x + t * sx, z - sz * 0.51, height * 0.55)
            dimensions = (0.07, 0.05, height * 0.86)
        else:
            location = _map_point(x + sx * 0.51, z + t * sz, height * 0.55)
            dimensions = (0.05, 0.07, height * 0.86)
        add_box(
            f"GEO-detail_cover_rib_{index:02d}_{rib:02d}",
            location,
            dimensions,
            materials["yellow"],
            collection,
        )


def _build_rail_panel(
    collection: bpy.types.Collection,
    materials: dict,
    center: tuple[float, float, float],
    length: float,
    index: int,
    opening_center: float | None = None,
    opening_width: float = 0.0,
) -> None:
    x, y, deck_z = center
    rail_height = 1.05
    post_width = 0.09
    start_x = x - length * 0.5
    end_x = x + length * 0.5
    spans = [(start_x, end_x)]
    if opening_center is not None and opening_width > 0.0:
        opening_start = max(start_x, opening_center - opening_width * 0.5)
        opening_end = min(end_x, opening_center + opening_width * 0.5)
        spans = [span for span in ((start_x, opening_start), (opening_end, end_x)) if span[1] - span[0] > 0.25]

    post_positions = sorted({round(value, 4) for span in spans for value in span})
    for post_index, post_x in enumerate(post_positions):
        add_box(
            f"GEO-detail_rail_post_{index:02d}_{post_index:02d}",
            (post_x, y, deck_z + rail_height * 0.5),
            (post_width, post_width, rail_height),
            materials["yellow"],
            collection,
        )
        add_box(
            f"GEO-detail_rail_foot_{index:02d}_{post_index:02d}",
            (post_x, y, deck_z + 0.025),
            (0.22, 0.22, 0.05),
            materials["metal_mid"],
            collection,
        )
    for span_index, (span_start, span_end) in enumerate(spans):
        span_length = span_end - span_start
        span_center = (span_start + span_end) * 0.5
        for rail_index, rail_z in enumerate((deck_z + 0.55, deck_z + rail_height)):
            add_box(
                f"GEO-detail_rail_bar_{index:02d}_{span_index:02d}_{rail_index}",
                (span_center, y, rail_z),
                (span_length, 0.075, 0.075),
                materials["yellow"],
                collection,
            )


def _build_stair_run(
    collection: bpy.types.Collection,
    materials: dict,
    entry: dict,
    index: int,
) -> None:
    x = float(entry["x"])
    z = float(entry["z"])
    sx = float(entry["sx"])
    sz = float(entry["sz"])
    top = float(entry["h"])
    direction = str(entry.get("direction", "x+"))
    along_x = direction.startswith("x")
    positive = direction.endswith("+")
    run = sx if along_x else sz
    cross = sz if along_x else sx
    steps = max(2, int(entry.get("steps", math.ceil(top / 0.2))))
    step_run = run / steps

    for step in range(steps):
        offset = -run * 0.5 + step_run * (step + 0.5)
        if not positive:
            offset = -offset
        step_height = top * (step + 1) / steps
        step_x = x + (offset if along_x else 0.0)
        step_z = z + (0.0 if along_x else offset)
        dimensions = (step_run, cross, step_height) if along_x else (cross, step_run, step_height)
        add_box(
            f"GEO-map_stair_{index:02d}_{step:02d}",
            _map_point(step_x, step_z, step_height * 0.5),
            dimensions,
            materials["concrete_light"],
            collection,
        )
        direction_sign = 1.0 if positive else -1.0
        nosing_x = step_x - direction_sign * step_run * 0.46 if along_x else step_x
        nosing_z = step_z if along_x else step_z - direction_sign * step_run * 0.46
        nosing_dimensions = (0.055, cross * 0.94, 0.025) if along_x else (cross * 0.94, 0.055, 0.025)
        add_box(
            f"GEO-map_stair_nosing_{index:02d}_{step:02d}",
            _map_point(nosing_x, nosing_z, step_height + 0.0125),
            nosing_dimensions,
            materials["yellow"],
            collection,
        )


def _build_catwalk_supports(
    collection: bpy.types.Collection,
    materials: dict,
    entry: dict,
    index: int,
) -> None:
    x = float(entry["x"])
    z = float(entry["z"])
    sx = float(entry["sx"])
    sz = float(entry["sz"])
    deck_height = float(entry["h"])
    inset = 0.38
    support_start = x - sx * 0.5 + inset
    support_end = x + sx * 0.5 - inset
    support_spans = max(1, math.ceil((support_end - support_start) / 8.0))
    support_xs = tuple(
        support_start + (support_end - support_start) * index / support_spans
        for index in range(support_spans + 1)
    )
    support_zs = (z - sz * 0.5 + inset, z + sz * 0.5 - inset)
    for side_index, support_x in enumerate(support_xs):
        for post_index, support_z in enumerate(support_zs):
            add_box(
                f"GEO-detail_catwalk_support_{index:02d}_{side_index}_{post_index}",
                _map_point(support_x, support_z, deck_height * 0.5),
                (0.22, 0.22, deck_height),
                materials["metal"],
                collection,
            )
        add_box(
            f"GEO-detail_catwalk_beam_{index:02d}_{side_index}",
            _map_point(support_x, z, deck_height - 0.26),
            (0.24, max(0.3, sz - inset * 1.2), 0.24),
            materials["rust"],
            collection,
        )


def _project_collection_uvs(collection: bpy.types.Collection, cube_size: float) -> None:
    for obj in collection.objects:
        cube_project_uv(obj, cube_size)


def build_map_blockout() -> dict:
    remove_collection(MAP_COLLECTION)
    collection = ensure_collection(MAP_COLLECTION)
    materials = _materials()
    level = _load_depot()
    arena_size = float(level.get("arenaSize", 56.0))
    arena_size_x = float(level.get("arenaSizeX", arena_size))
    arena_size_z = float(level.get("arenaSizeZ", arena_size))

    add_box(
        "GEO-map_floor",
        (0.0, 0.0, -0.12),
        (arena_size_x * 2.0, arena_size_z * 2.0, 0.24),
        materials["concrete"],
        collection,
    )

    boundary_height = float(level.get("boundaryHeight", 6.0))
    span_x = arena_size_x * 2.0 + 2.0
    span_z = arena_size_z * 2.0 + 2.0
    boundaries = (
        ("north", (0.0, arena_size_z + 0.5, boundary_height * 0.5), (span_x, 1.0, boundary_height)),
        ("south", (0.0, -arena_size_z - 0.5, boundary_height * 0.5), (span_x, 1.0, boundary_height)),
        ("west", (-arena_size_x - 0.5, 0.0, boundary_height * 0.5), (1.0, span_z, boundary_height)),
        ("east", (arena_size_x + 0.5, 0.0, boundary_height * 0.5), (1.0, span_z, boundary_height)),
    )
    for name, location, dimensions in boundaries:
        add_box(f"GEO-map_boundary_{name}", location, dimensions, materials["concrete_light"], collection)

    for index, entry in enumerate(level.get("walls", [])):
        height = float(entry.get("h", 1.0))
        add_box(
            f"GEO-map_wall_{index:02d}",
            _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
            (float(entry["sx"]), float(entry["sz"]), height),
            materials["concrete_light" if index % 3 else "concrete"],
            collection,
        )

    for index, entry in enumerate(level.get("covers", [])):
        _build_cover(collection, materials, entry, index)

    for index, entry in enumerate(level.get("floors", [])):
        height = float(entry.get("h", 1.0))
        add_box(
            f"GEO-map_upper_floor_{index:02d}",
            _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
            (float(entry["sx"]), float(entry["sz"]), height),
            materials["metal_mid"],
            collection,
        )

    for index, entry in enumerate(level.get("stairs", [])):
        if int(entry.get("steps", 1)) > 1:
            _build_stair_run(collection, materials, entry, index)
        else:
            height = float(entry.get("h", 1.0))
            add_box(
                f"GEO-map_stair_block_{index:02d}",
                _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
                (float(entry["sx"]), float(entry["sz"]), height),
                materials["metal_mid"],
                collection,
            )

    for index, entry in enumerate(level.get("ramps", [])):
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        top = float(entry["h"])
        along_x = sx >= sz
        run = sx if along_x else sz
        cross = sz if along_x else sx
        segments = 6
        segment_run = run / segments
        for segment in range(segments):
            progress = (segment + 1) / segments
            segment_height = max(0.08, top * progress)
            offset = -run * 0.5 + segment_run * (segment + 0.5)
            x = float(entry["x"]) + (offset if along_x else 0.0)
            z = float(entry["z"]) + (0.0 if along_x else offset)
            dimensions = (segment_run, cross, segment_height) if along_x else (cross, segment_run, segment_height)
            add_box(
                f"GEO-map_ramp_{index:02d}_{segment:02d}",
                _map_point(x, z, segment_height * 0.5),
                dimensions,
                materials["metal_mid"],
                collection,
            )

    for index, entry in enumerate(level.get("catwalks", [])):
        deck_height = float(entry["h"])
        deck_thickness = 0.28
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        add_box(
            f"GEO-map_catwalk_{index:02d}",
            _map_point(x, z, deck_height - deck_thickness * 0.5),
            (sx, sz, deck_thickness),
            materials["metal_mid"],
            collection,
        )

    for index, entry in enumerate(level.get("overheads", [])):
        underside = float(entry.get("y", 3.4))
        thickness = float(entry.get("thickness", 0.4))
        add_box(
            f"GEO-map_overhead_{index:02d}",
            _map_point(float(entry["x"]), float(entry["z"]), underside + thickness * 0.5),
            (float(entry["sx"]), float(entry["sz"]), thickness),
            materials["concrete_light"],
            collection,
        )

    _project_collection_uvs(collection, 2.5)
    return validate_collection(MAP_COLLECTION)


def build_map_details() -> dict:
    collection = ensure_collection(MAP_COLLECTION)
    materials = _materials()
    level = _load_depot()
    remove_objects_with_prefix("GEO-detail_")

    for index, entry in enumerate(level.get("walls", [])):
        _add_hazard_band(collection, materials, entry, index)

    for index, entry in enumerate(level.get("catwalks", [])):
        deck_height = float(entry["h"])
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        if sx >= sz:
            y_front = -z - sz * 0.5 + 0.1
            y_back = -z + sz * 0.5 - 0.1
            _build_rail_panel(collection, materials, (x, y_front, deck_height), sx * 0.94, index * 2)
            opening_center = float(entry.get("railOpeningCenter", x)) if str(entry.get("railOpening", "")) == "z-" else None
            opening_width = float(entry.get("railOpeningWidth", 0.0))
            _build_rail_panel(
                collection,
                materials,
                (x, y_back, deck_height),
                sx * 0.94,
                index * 2 + 1,
                opening_center,
                opening_width,
            )
        _build_catwalk_supports(collection, materials, entry, index)

    furnace_x, furnace_z = 4.0, 5.0
    add_cylinder(
        "GEO-detail_furnace_body",
        _map_point(furnace_x, furnace_z, 6.2),
        2.35,
        4.4,
        materials["rust"],
        collection,
        vertices=12,
    )
    add_cylinder(
        "GEO-detail_furnace_ring_lower",
        _map_point(furnace_x, furnace_z, 4.15),
        2.55,
        0.28,
        materials["yellow"],
        collection,
        vertices=12,
    )
    add_cylinder(
        "GEO-detail_furnace_ring_upper",
        _map_point(furnace_x, furnace_z, 8.15),
        2.55,
        0.28,
        materials["yellow"],
        collection,
        vertices=12,
    )
    for angle_index in range(8):
        angle = angle_index * math.tau / 8.0
        add_box(
            f"GEO-detail_furnace_rib_{angle_index:02d}",
            (
                furnace_x + math.cos(angle) * 2.38,
                -furnace_z + math.sin(angle) * 2.38,
                6.2,
            ),
            (0.16, 0.16, 3.6),
            materials["metal"],
            collection,
            rotation=(0.0, 0.0, angle),
        )

    pipe_routes = (
        ((-46.0, 39.0, 5.8), (-44.0, 39.0, 5.8), (-44.0, 27.0, 5.8)),
        ((46.0, -36.0, 6.1), (44.0, -36.0, 6.1), (44.0, -15.0, 6.1)),
        ((-34.0, 23.4, 6.4), (-11.0, 23.4, 6.4), (-11.0, 17.0, 6.4)),
    )
    for index, points in enumerate(pipe_routes):
        add_pipe(f"GEO-detail_pipe_{index:02d}", points, 0.18, materials["teal"], collection)
        for endpoint_index, endpoint in enumerate((points[0], points[-1])):
            add_cylinder(
                f"GEO-detail_pipe_flange_{index:02d}_{endpoint_index}",
                endpoint,
                0.31,
                0.12,
                materials["metal"],
                collection,
                vertices=12,
            )

    cabinet_specs = (
        (-33.2, 15.0, 0.0),
        (31.2, 12.0, math.pi),
        (-22.0, -23.2, math.pi * 0.5),
    )
    for index, (x, z, rotation) in enumerate(cabinet_specs):
        add_box(
            f"GEO-detail_cabinet_{index:02d}",
            _map_point(x, z, 1.05),
            (1.1, 0.48, 2.1),
            materials["metal_mid"],
            collection,
            rotation=(0.0, 0.0, rotation),
        )
        add_box(
            f"GEO-detail_cabinet_screen_{index:02d}",
            _map_point(x, z - 0.25, 1.35),
            (0.52, 0.03, 0.38),
            materials["glass"],
            collection,
            rotation=(0.0, 0.0, rotation),
        )

    route_marks = (
        ("MID", 0.0, 15.0, materials["orange"]),
        ("YARD", 38.0, 24.0, materials["teal"]),
        ("SERVICE", -12.0, -28.0, materials["yellow"]),
    )
    for index, (body, x, z, material) in enumerate(route_marks):
        add_text(
            f"GEO-detail_sign_{index:02d}",
            body,
            _map_point(x, z, 0.025),
            1.2,
            material,
            collection,
            rotation=(0.0, 0.0, 0.0),
            extrude=0.012,
        )

    lighting = level.get("lights", {})
    light_points = lighting.get("points", [])
    for index, point in enumerate(light_points):
        x = float(point[0])
        height = float(point[1])
        z = float(point[2])
        add_box(
            f"GEO-detail_light_fixture_{index:02d}",
            _map_point(x, z, height + 0.08),
            (1.4, 0.38, 0.12),
            materials["metal"],
            collection,
        )
        add_box(
            f"GEO-detail_light_emitter_{index:02d}",
            _map_point(x, z, height),
            (1.05, 0.28, 0.05),
            materials["light"],
            collection,
        )

    _project_collection_uvs(collection, 2.5)
    return validate_collection(MAP_COLLECTION)


def _build_arms(collection: bpy.types.Collection, materials: dict, pistol: bool = False) -> None:
    if pistol:
        arm_specs = (
            ((0.055, 0.13, -0.15), (0.055, 0.055, 0.18), (math.radians(-18.0), 0.0, math.radians(-8.0))),
            ((-0.05, 0.10, -0.13), (0.05, 0.05, 0.16), (math.radians(-24.0), 0.0, math.radians(8.0))),
        )
    else:
        arm_specs = (
            ((0.055, 0.155, -0.16), (0.06, 0.06, 0.25), (math.radians(-22.0), 0.0, math.radians(-7.0))),
            ((-0.07, -0.08, -0.09), (0.055, 0.055, 0.24), (math.radians(35.0), 0.0, math.radians(7.0))),
        )
    for index, (location, dimensions, rotation) in enumerate(arm_specs):
        add_cylinder(
            f"GEO-{'pistol' if pistol else 'rifle'}_forearm_{index}",
            location,
            dimensions[0],
            dimensions[2],
            materials["skin"],
            collection,
            vertices=8,
            rotation=rotation,
        )
        add_ico_sphere(
            f"GEO-{'pistol' if pistol else 'rifle'}_glove_{index}",
            (location[0], location[1] - 0.08, location[2] + 0.02),
            (0.055, 0.072, 0.05),
            materials["glove"],
            collection,
            subdivisions=1,
        )


def _soften_weapon_edges(collection: bpy.types.Collection) -> None:
    for obj in collection.objects:
        if obj.type != "MESH" or not obj.name.startswith("GEO-"):
            continue
        shortest_edge = min(float(value) for value in obj.dimensions)
        if shortest_edge <= 0.0:
            continue
        modifier = obj.modifiers.new("VB_SubtleBevel", "BEVEL")
        modifier.width = min(0.004, shortest_edge * 0.08)
        modifier.segments = 2
        modifier.limit_method = "ANGLE"


def build_rifle() -> dict:
    remove_collection(RIFLE_COLLECTION)
    collection = ensure_collection(RIFLE_COLLECTION)
    materials = _materials()
    add_box("GEO-rifle_receiver", (0.0, 0.0, 0.0), (0.085, 0.30, 0.10), materials["metal"], collection)
    add_box("GEO-rifle_upper", (0.0, -0.015, 0.068), (0.072, 0.26, 0.045), materials["metal_mid"], collection)
    add_box("GEO-rifle_handguard", (0.0, -0.255, 0.005), (0.078, 0.25, 0.085), materials["dark"], collection)
    add_cylinder(
        "GEO-rifle_barrel",
        (0.0, -0.51, 0.015),
        0.014,
        0.34,
        materials["metal"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_cylinder(
        "GEO-rifle_muzzle",
        (0.0, -0.69, 0.015),
        0.025,
        0.07,
        materials["metal_mid"],
        collection,
        vertices=10,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_box("GEO-rifle_stock", (0.0, 0.235, -0.01), (0.075, 0.23, 0.105), materials["dark"], collection)
    add_box("GEO-rifle_buttpad", (0.0, 0.36, -0.02), (0.084, 0.035, 0.13), materials["rust"], collection)
    add_box(
        "GEO-rifle_grip",
        (0.0, 0.085, -0.105),
        (0.065, 0.075, 0.17),
        materials["dark"],
        collection,
        rotation=(math.radians(-14.0), 0.0, 0.0),
    )
    add_box(
        "GEO-rifle_magazine",
        (0.0, -0.055, -0.14),
        (0.068, 0.115, 0.20),
        materials["rust"],
        collection,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )
    add_box("GEO-rifle_mag_base", (0.0, -0.036, -0.25), (0.075, 0.10, 0.025), materials["metal"], collection)
    for index in range(8):
        add_box(
            f"GEO-rifle_rail_{index:02d}",
            (0.0, -0.22 + index * 0.055, 0.102),
            (0.05, 0.025, 0.018),
            materials["metal_mid"],
            collection,
        )
    add_box("GEO-rifle_rear_sight", (0.0, 0.08, 0.135), (0.055, 0.045, 0.055), materials["metal"], collection)
    add_box("GEO-rifle_front_sight", (0.0, -0.35, 0.087), (0.04, 0.035, 0.075), materials["metal"], collection)
    add_box("GEO-rifle_accent", (0.043, -0.05, 0.01), (0.012, 0.13, 0.045), materials["orange"], collection)
    _build_arms(collection, materials, pistol=False)
    _soften_weapon_edges(collection)
    _project_collection_uvs(collection, 0.18)
    return validate_collection(RIFLE_COLLECTION)


def build_pistol() -> dict:
    remove_collection(PISTOL_COLLECTION)
    collection = ensure_collection(PISTOL_COLLECTION)
    materials = _materials()
    add_box("GEO-pistol_slide", (0.0, -0.055, 0.045), (0.055, 0.235, 0.065), materials["metal_mid"], collection)
    add_box("GEO-pistol_frame", (0.0, 0.015, -0.005), (0.05, 0.155, 0.06), materials["dark"], collection)
    add_cylinder(
        "GEO-pistol_barrel",
        (0.0, -0.18, 0.043),
        0.012,
        0.055,
        materials["metal"],
        collection,
        vertices=10,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_box(
        "GEO-pistol_grip",
        (0.0, 0.045, -0.115),
        (0.055, 0.085, 0.20),
        materials["dark"],
        collection,
        rotation=(math.radians(-12.0), 0.0, 0.0),
    )
    add_box("GEO-pistol_mag_base", (0.0, 0.068, -0.225), (0.065, 0.075, 0.025), materials["rust"], collection)
    add_pipe(
        "GEO-pistol_trigger_guard",
        ((-0.028, -0.025, -0.04), (-0.028, -0.07, -0.075), (0.028, -0.07, -0.075), (0.028, -0.025, -0.04)),
        0.008,
        materials["metal"],
        collection,
    )
    add_box("GEO-pistol_front_sight", (0.0, -0.155, 0.085), (0.022, 0.018, 0.022), materials["orange"], collection)
    add_box("GEO-pistol_rear_sight", (0.0, 0.04, 0.086), (0.04, 0.025, 0.024), materials["metal"], collection)
    add_box("GEO-pistol_accent", (0.029, -0.04, 0.043), (0.008, 0.12, 0.026), materials["teal"], collection)
    _build_arms(collection, materials, pistol=True)
    _soften_weapon_edges(collection)
    _project_collection_uvs(collection, 0.18)
    return validate_collection(PISTOL_COLLECTION)


def build_weapons() -> dict:
    return {"rifle": build_rifle(), "pistol": build_pistol()}


def _create_presentation() -> None:
    remove_collection(PRESENTATION_COLLECTION)
    collection = ensure_collection(PRESENTATION_COLLECTION)
    camera_data = bpy.data.cameras.new("CAM_foundry_preview")
    camera = bpy.data.objects.new("CAM_foundry_preview", camera_data)
    camera.location = (68.0, -78.0, 58.0)
    camera_data.lens = 48.0
    look_at(camera, (0.0, 0.0, 2.4))
    collection.objects.link(camera)
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("LIGHT_foundry_sun", type="SUN")
    sun_data.energy = 1.8
    sun_data.color = (1.0, 0.82, 0.66)
    sun = bpy.data.objects.new("LIGHT_foundry_sun", sun_data)
    sun.rotation_euler = (math.radians(32.0), math.radians(-18.0), math.radians(-38.0))
    collection.objects.link(sun)

    area_data = bpy.data.lights.new("LIGHT_foundry_fill", type="AREA")
    area_data.energy = 1200.0
    area_data.shape = "DISK"
    area_data.size = 45.0
    area_data.color = (0.38, 0.62, 0.82)
    area = bpy.data.objects.new("LIGHT_foundry_fill", area_data)
    area.location = (-36.0, 30.0, 52.0)
    look_at(area, (0.0, 0.0, 0.0))
    collection.objects.link(area)

    level = _load_depot()
    light_points = level.get("lights", {}).get("points", [])
    light_colors = level.get("lights", {}).get("colors", [])
    for index, point in enumerate(light_points):
        light_data = bpy.data.lights.new(f"LIGHT_map_{index:02d}", type="POINT")
        light_data.energy = 520.0
        light_data.shadow_soft_size = 2.0
        if index < len(light_colors):
            light_data.color = tuple(float(value) for value in light_colors[index][:3])
        light = bpy.data.objects.new(f"LIGHT_map_{index:02d}", light_data)
        light.location = _map_point(float(point[0]), float(point[2]), float(point[1]))
        collection.objects.link(light)


def _render_map_preview_and_save() -> tuple[Path, Path]:
    source_blend = PROJECT_ROOT / "tools" / "blender" / "source" / "foundry_asset_source.blend"
    preview = PROJECT_ROOT / "assets" / "maps" / "foundry-depot-preview.png"
    _create_presentation()
    set_collection_hidden(bpy.data.collections[RIFLE_COLLECTION], True)
    set_collection_hidden(bpy.data.collections[PISTOL_COLLECTION], True)
    set_collection_hidden(bpy.data.collections[MAP_COLLECTION], False)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview)
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.026, 0.03)
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.28
    scene.view_settings.gamma = 1.0
    scene.frame_set(scene.frame_current)
    bpy.context.view_layer.update()
    # Blender can render one stale frame after bulk export and visibility changes.
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
    return source_blend, preview


def export_map_and_save() -> dict:
    output_map = PROJECT_ROOT / "assets" / "models" / "foundry" / "foundry_depot.glb"
    map_count = export_collection_glb(MAP_COLLECTION, output_map)
    source_blend, preview = _render_map_preview_and_save()
    return {
        "exports": {"map": map_count},
        "map_validation": validate_collection(MAP_COLLECTION),
        "blend": str(source_blend),
        "preview": str(preview),
    }


def export_and_save() -> dict:
    output_map = PROJECT_ROOT / "assets" / "models" / "foundry" / "foundry_depot.glb"
    output_rifle = PROJECT_ROOT / "assets" / "models" / "weapons" / "vb_rifle.glb"
    output_pistol = PROJECT_ROOT / "assets" / "models" / "weapons" / "vb_pistol.glb"
    export_counts = {
        "map": export_collection_glb(MAP_COLLECTION, output_map),
        "rifle": export_collection_glb(RIFLE_COLLECTION, output_rifle),
        "pistol": export_collection_glb(PISTOL_COLLECTION, output_pistol),
    }
    source_blend, preview = _render_map_preview_and_save()
    return {
        "exports": export_counts,
        "map_validation": validate_collection(MAP_COLLECTION),
        "rifle_validation": validate_collection(RIFLE_COLLECTION),
        "pistol_validation": validate_collection(PISTOL_COLLECTION),
        "blend": str(source_blend),
        "preview": str(preview),
    }


def build_all() -> dict:
    reset_owned_scene()
    result = {
        "blockout": build_map_blockout(),
        "details": build_map_details(),
        "weapons": build_weapons(),
    }
    result["final"] = export_and_save()
    return result


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
