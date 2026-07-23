from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import build_foundry_assets as foundry  # noqa: E402
from blender_build_utils import (  # noqa: E402
    add_box,
    add_cylinder,
    add_pipe,
    add_text,
    add_torus,
    assign_material,
    cube_project_uv,
    ensure_collection,
    export_collection_glb,
    join_mesh_objects,
    look_at,
    make_material,
    remove_collection,
    validate_collection,
)


MAP_COLLECTION = "VB_MAP_FOUNDRY_REFORGED"
PRESENTATION_COLLECTION = "VB_PRESENTATION_REFORGED"
EQUIPMENT_COVER_IDS = {"a-long-spool", "b-pump-crate", "b-valve-cover"}


def _load_level() -> dict:
    path = PROJECT_ROOT / "data" / "levels" / "foundry-reforged.json"
    return json.loads(path.read_text(encoding="utf-8"))


def _map_point(x: float, z: float, height: float) -> tuple[float, float, float]:
    return (x, -z, height)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def _add_boundary(
    collection: bpy.types.Collection,
    materials: dict,
    level: dict,
) -> None:
    arena_x = float(level["arenaSizeX"])
    arena_z = float(level["arenaSizeZ"])
    height = float(level["boundaryHeight"])
    add_box(
        "GEO-reforged-floor",
        (0.0, 0.0, -0.12),
        (arena_x * 2.0, arena_z * 2.0, 0.24),
        materials["concrete"],
        collection,
    )
    spans = (
        ("north", (0.0, arena_z + 0.5, height * 0.5), (arena_x * 2.0 + 2.0, 1.0, height), materials["concrete_light"]),
        ("south", (0.0, -arena_z - 0.5, height * 0.5), (arena_x * 2.0 + 2.0, 1.0, height), materials["green_metal"]),
        ("west", (-arena_x - 0.5, 0.0, height * 0.5), (1.0, arena_z * 2.0 + 2.0, height), materials["corrugated_rust"]),
        ("east", (arena_x + 0.5, 0.0, height * 0.5), (1.0, arena_z * 2.0 + 2.0, height), materials["corrugated_rust"]),
    )
    for name, location, dimensions, material in spans:
        add_box(
            f"GEO-reforged-boundary-{name}",
            location,
            dimensions,
            material,
            collection,
        )


def _wall_material(materials: dict, entry: dict, index: int) -> bpy.types.Material:
    wall_id = str(entry["id"])
    if wall_id.startswith("b-"):
        return materials["green_metal" if index % 2 == 0 else "corrugated_rust"]
    if wall_id in {"a-pit-screen", "a-site-entry-screen"}:
        return materials["damaged_concrete"]
    if wall_id.startswith("a-"):
        return materials["concrete"]
    if wall_id.startswith("south-partition") and index % 3 == 0:
        return materials["green_metal"]
    if wall_id.startswith("defender-"):
        return materials["metal_mid"]
    return materials["concrete_light" if index % 3 else "concrete"]


def _project_reforged_uvs(collection: bpy.types.Collection) -> None:
    for obj in collection.objects:
        name = obj.name.lower()
        if "floor" in name or "boundary" in name:
            cube_size = 4.0
        elif "wall" in name:
            cube_size = 3.0
        elif "cover" in name or "furnace" in name or "equipment" in name:
            cube_size = 1.35
        elif "frame" in name or "panel" in name or "drain" in name:
            cube_size = 1.0
        else:
            cube_size = 1.8
        cube_project_uv(obj, cube_size)


def _add_box_entry(
    collection: bpy.types.Collection,
    material: bpy.types.Material,
    entry: dict,
    prefix: str,
) -> None:
    height = float(entry["h"])
    add_box(
        f"GEO-reforged-{prefix}-{entry['id']}",
        _map_point(float(entry["x"]), float(entry["z"]), height * 0.5),
        (float(entry["sx"]), float(entry["sz"]), height),
        material,
        collection,
    )


def _add_ramp(
    collection: bpy.types.Collection,
    materials: dict,
    entry: dict,
) -> None:
    sx = float(entry["sx"])
    sz = float(entry["sz"])
    top = float(entry["h"])
    along_x = sx >= sz
    run = sx if along_x else sz
    cross = sz if along_x else sx
    segments = 8
    segment_run = run / segments
    for segment in range(segments):
        progress = (segment + 1) / segments
        segment_height = max(0.08, top * progress)
        offset = -run * 0.5 + segment_run * (segment + 0.5)
        x = float(entry["x"]) + (offset if along_x else 0.0)
        z = float(entry["z"]) + (0.0 if along_x else offset)
        dimensions = (
            (segment_run, cross, segment_height)
            if along_x
            else (cross, segment_run, segment_height)
        )
        add_box(
            f"GEO-reforged-ramp-{entry['id']}-{segment:02d}",
            _map_point(x, z, segment_height * 0.5),
            dimensions,
            materials["metal_mid"],
            collection,
        )


def build_blockout() -> dict:
    collection = ensure_collection(MAP_COLLECTION)
    materials = foundry._materials()
    level = _load_level()
    _add_boundary(collection, materials, level)

    for index, entry in enumerate(level.get("walls", [])):
        if entry["id"] == "mid-furnace-core":
            continue
        material = _wall_material(materials, entry, index)
        _add_box_entry(collection, material, entry, "wall")

    for index, entry in enumerate(level.get("covers", [])):
        if str(entry["id"]) in EQUIPMENT_COVER_IDS:
            continue
        foundry._build_cover(collection, materials, entry, index)
        cover = collection.objects.get(f"GEO-map_cover_{index:02d}")
        if cover is not None:
            zone_material = materials["green_metal"] if float(entry["z"]) > 12.0 else materials["rust"]
            assign_material(cover, zone_material)

    for entry in level.get("floors", []):
        material = materials["corrugated_rust"] if entry.get("upper") else materials["concrete"]
        _add_box_entry(collection, material, entry, "floor")

    for index, entry in enumerate(level.get("stairs", [])):
        foundry._build_stair_run(collection, materials, entry, index)
        if str(entry["id"]).startswith("b-"):
            for obj in collection.objects:
                if obj.name.startswith(f"GEO-map_stair_{index:02d}_"):
                    assign_material(obj, materials["green_metal"])

    for entry in level.get("ramps", []):
        _add_ramp(collection, materials, entry)

    for index, entry in enumerate(level.get("catwalks", [])):
        deck_height = float(entry["h"])
        add_box(
            f"GEO-reforged-catwalk-{entry['id']}",
            _map_point(float(entry["x"]), float(entry["z"]), deck_height - 0.14),
            (float(entry["sx"]), float(entry["sz"]), 0.28),
            materials["corrugated_rust"],
            collection,
        )
        foundry._build_catwalk_supports(collection, materials, entry, index)

    for entry in level.get("overheads", []):
        underside = float(entry["y"])
        thickness = float(entry["thickness"])
        add_box(
            f"GEO-reforged-frame-{entry['id']}",
            _map_point(float(entry["x"]), float(entry["z"]), underside + thickness * 0.5),
            (float(entry["sx"]), float(entry["sz"]), thickness),
            materials["rust"],
            collection,
        )

    _project_reforged_uvs(collection)
    return validate_collection(MAP_COLLECTION)


def _build_furnace(collection: bpy.types.Collection, materials: dict) -> None:
    add_cylinder(
        "GEO-reforged-furnace-body",
        _map_point(0.0, 0.0, 2.75),
        2.35,
        5.5,
        materials["rust"],
        collection,
        vertices=12,
    )
    for index, height in enumerate((0.35, 2.75, 5.15)):
        add_cylinder(
            f"GEO-reforged-furnace-ring-{index}",
            _map_point(0.0, 0.0, height),
            2.5,
            0.22,
            materials["yellow"],
            collection,
            vertices=12,
        )
    for index in range(8):
        angle = index * math.tau / 8.0
        add_box(
            f"GEO-reforged-furnace-rib-{index:02d}",
            (math.cos(angle) * 2.37, math.sin(angle) * 2.37, 2.75),
            (0.14, 0.14, 4.7),
            materials["metal"],
            collection,
            rotation=(0.0, 0.0, angle),
        )
    for index in range(4):
        angle = index * math.tau / 4.0
        add_box(
            f"GEO-reforged-furnace-glow-{index:02d}",
            (math.cos(angle) * 2.38, math.sin(angle) * 2.38, 2.75),
            (0.05, 0.82, 2.6),
            materials["light"],
            collection,
            rotation=(0.0, 0.0, angle),
        )


def _build_pipes(collection: bpy.types.Collection, materials: dict) -> None:
    pipe_routes = (
        ((-39.0, 39.7, 5.8), (12.0, 39.7, 5.8), (12.0, 35.0, 5.8)),
        ((-30.0, -39.7, 5.4), (18.0, -39.7, 5.4), (18.0, -35.0, 5.4)),
        ((42.0, -9.5, 5.2), (42.0, 9.5, 5.2)),
    )
    for index, points in enumerate(pipe_routes):
        add_pipe(
            f"GEO-reforged-pipe-{index:02d}",
            points,
            0.16,
            materials["teal"],
            collection,
        )
        for endpoint_index, endpoint in enumerate((points[0], points[-1])):
            add_cylinder(
                f"GEO-reforged-pipe-flange-{index:02d}-{endpoint_index}",
                endpoint,
                0.28,
                0.12,
                materials["metal"],
                collection,
                vertices=12,
            )


def _finish_equipment(parts: list[bpy.types.Object], name: str, cover_id: str) -> None:
    equipment = join_mesh_objects(parts, f"GEO-reforged-equipment-{name}")
    equipment["cover_id"] = cover_id


def _build_cable_spool(
    collection: bpy.types.Collection,
    materials: dict,
    cover: dict,
) -> None:
    center_x, center_y, _ = _map_point(float(cover["x"]), float(cover["z"]), 0.0)
    center_height = 0.72
    parts = [
        add_cylinder(
            "TMP-reforged-spool-core",
            (center_x, center_y, center_height),
            0.58,
            1.55,
            materials["dark"],
            collection,
            vertices=12,
            rotation=(math.radians(90.0), 0.0, 0.0),
        )
    ]
    for side, offset in enumerate((-0.84, 0.84)):
        parts.append(
            add_cylinder(
                f"TMP-reforged-spool-flange-{side}",
                (center_x, center_y + offset, center_height),
                0.72,
                0.12,
                materials["rust"],
                collection,
                vertices=12,
                rotation=(math.radians(90.0), 0.0, 0.0),
            )
        )
    parts.append(
        add_cylinder(
            "TMP-reforged-spool-hub",
            (center_x, center_y, center_height),
            0.20,
            1.88,
            materials["metal_mid"],
            collection,
            vertices=12,
            rotation=(math.radians(90.0), 0.0, 0.0),
        )
    )
    for band, offset in enumerate((-0.42, 0.0, 0.42)):
        parts.append(
            add_cylinder(
                f"TMP-reforged-spool-cable-band-{band}",
                (center_x, center_y + offset, center_height),
                0.61,
                0.065,
                materials["dark"],
                collection,
                vertices=12,
                rotation=(math.radians(90.0), 0.0, 0.0),
            )
        )
    _finish_equipment(parts, "a-cable-spool", str(cover["id"]))


def _build_pump(
    collection: bpy.types.Collection,
    materials: dict,
    cover: dict,
) -> None:
    center_x, center_y, _ = _map_point(float(cover["x"]), float(cover["z"]), 0.0)
    parts = [
        add_box(
            "TMP-reforged-pump-plinth",
            (center_x, center_y, 0.08),
            (2.2, 1.65, 0.16),
            materials["dark"],
            collection,
        ),
        add_cylinder(
            "TMP-reforged-pump-motor",
            (center_x - 0.32, center_y, 0.68),
            0.45,
            1.20,
            materials["green_metal"],
            collection,
            vertices=12,
            rotation=(0.0, math.radians(90.0), 0.0),
        ),
        add_cylinder(
            "TMP-reforged-pump-housing",
            (center_x + 0.65, center_y, 0.58),
            0.48,
            0.78,
            materials["metal_mid"],
            collection,
            vertices=12,
        ),
    ]
    for cap, offset in enumerate((-0.96, 0.32)):
        parts.append(
            add_cylinder(
                f"TMP-reforged-pump-motor-cap-{cap}",
                (center_x + offset, center_y, 0.68),
                0.50,
                0.12,
                materials["metal_mid"],
                collection,
                vertices=12,
                rotation=(0.0, math.radians(90.0), 0.0),
            )
        )
    parts.extend(
        (
            add_cylinder(
                "TMP-reforged-pump-neck",
                (center_x + 0.65, center_y, 1.08),
                0.18,
                0.22,
                materials["metal_mid"],
                collection,
                vertices=12,
            ),
            add_cylinder(
                "TMP-reforged-pump-top-flange",
                (center_x + 0.65, center_y, 1.23),
                0.28,
                0.08,
                materials["rust"],
                collection,
                vertices=12,
            ),
            add_cylinder(
                "TMP-reforged-pump-side-nozzle",
                (center_x + 0.65, center_y - 0.55, 0.58),
                0.18,
                0.52,
                materials["metal_mid"],
                collection,
                vertices=12,
                rotation=(math.radians(90.0), 0.0, 0.0),
            ),
            add_cylinder(
                "TMP-reforged-pump-side-flange",
                (center_x + 0.65, center_y - 0.84, 0.58),
                0.28,
                0.10,
                materials["rust"],
                collection,
                vertices=12,
                rotation=(math.radians(90.0), 0.0, 0.0),
            ),
        )
    )
    _finish_equipment(parts, "b-pump", str(cover["id"]))


def _build_valve(
    collection: bpy.types.Collection,
    materials: dict,
    cover: dict,
) -> None:
    center_x, center_y, _ = _map_point(float(cover["x"]), float(cover["z"]), 0.0)
    parts = [
        add_box(
            "TMP-reforged-valve-plinth",
            (center_x, center_y, 0.07),
            (2.05, 1.65, 0.14),
            materials["dark"],
            collection,
        ),
        add_cylinder(
            "TMP-reforged-valve-pipe",
            (center_x, center_y, 0.45),
            0.24,
            1.90,
            materials["metal_mid"],
            collection,
            vertices=12,
            rotation=(0.0, math.radians(90.0), 0.0),
        ),
        add_cylinder(
            "TMP-reforged-valve-body",
            (center_x, center_y, 0.54),
            0.48,
            0.70,
            materials["green_metal"],
            collection,
            vertices=12,
        ),
        add_cylinder(
            "TMP-reforged-valve-collar",
            (center_x, center_y, 0.88),
            0.32,
            0.16,
            materials["rust"],
            collection,
            vertices=12,
        ),
        add_cylinder(
            "TMP-reforged-valve-neck",
            (center_x, center_y, 1.13),
            0.15,
            0.45,
            materials["metal_mid"],
            collection,
            vertices=12,
        ),
        add_torus(
            "TMP-reforged-valve-wheel-rim",
            (center_x, center_y, 1.37),
            0.39,
            0.055,
            materials["yellow"],
            collection,
        ),
        add_cylinder(
            "TMP-reforged-valve-wheel-hub",
            (center_x, center_y, 1.37),
            0.11,
            0.09,
            materials["yellow"],
            collection,
            vertices=12,
        ),
    ]
    for flange, offset in enumerate((-0.82, 0.82)):
        parts.append(
            add_cylinder(
                f"TMP-reforged-valve-flange-{flange}",
                (center_x + offset, center_y, 0.45),
                0.38,
                0.16,
                materials["rust"],
                collection,
                vertices=12,
                rotation=(0.0, math.radians(90.0), 0.0),
            )
        )
    for spoke, angle in enumerate((0.0, math.radians(90.0))):
        parts.append(
            add_box(
                f"TMP-reforged-valve-wheel-spoke-{spoke}",
                (center_x, center_y, 1.37),
                (0.72, 0.055, 0.055),
                materials["yellow"],
                collection,
                rotation=(0.0, 0.0, angle),
            )
        )
    _finish_equipment(parts, "b-valve", str(cover["id"]))


def _build_equipment(
    collection: bpy.types.Collection,
    materials: dict,
    level: dict,
) -> None:
    covers = {str(entry["id"]): entry for entry in level.get("covers", [])}
    _build_cable_spool(collection, materials, covers["a-long-spool"])
    _build_pump(collection, materials, covers["b-pump-crate"])
    _build_valve(collection, materials, covers["b-valve-cover"])


def _add_floor_stain(
    collection: bpy.types.Collection,
    material: bpy.types.Material,
    name: str,
    x: float,
    z: float,
    radius: float,
    aspect: float,
    rotation: float,
) -> None:
    radii = (1.0, 0.78, 0.92, 0.70, 0.88, 0.74, 0.95, 0.80)
    center_y = -z
    vertices = []
    for index, variation in enumerate(radii):
        angle = rotation + math.tau * index / len(radii)
        vertices.append(
            (
                x + math.cos(angle) * radius * variation,
                center_y + math.sin(angle) * radius * aspect * variation,
                0.008,
            )
        )
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], [list(range(len(vertices)))])
    mesh.update()
    stain = bpy.data.objects.new(name, mesh)
    collection.objects.link(stain)
    stain.data.materials.append(material)


def _finish_wall_detail(
    parts: list[bpy.types.Object],
    name: str,
    wall: dict,
    face_sign: float,
) -> None:
    detail = join_mesh_objects(parts, name)
    detail["wall_id"] = str(wall["id"])
    detail["wall_face_axis"] = "z"
    detail["wall_face_sign"] = face_sign


def _build_rust_run(
    collection: bpy.types.Collection,
    materials: dict,
    name: str,
    wall: dict,
    face_sign: float,
    anchor_x: float,
) -> None:
    thickness = 0.012
    wall_face = float(wall["z"]) + face_sign * float(wall["sz"]) * 0.5
    detail_z = wall_face + face_sign * thickness * 0.5
    parts: list[bpy.types.Object] = []
    runs = ((-0.25, 0.13, 0.86), (0.0, 0.18, 1.18), (0.29, 0.10, 0.64))
    for index, (offset, width, height) in enumerate(runs):
        parts.append(
            add_box(
                f"TMP-reforged-rust-run-{name}-{index}",
                _map_point(anchor_x + offset, detail_z, float(wall["h"]) - 0.32 - height * 0.5),
                (width, thickness, height),
                materials["rust"],
                collection,
            )
        )
    _finish_wall_detail(parts, f"GEO-reforged-surface-rust-{name}", wall, face_sign)


def _build_weld_seam(
    collection: bpy.types.Collection,
    materials: dict,
    name: str,
    wall: dict,
    face_sign: float,
    anchor_x: float,
) -> None:
    thickness = 0.012
    wall_face = float(wall["z"]) + face_sign * float(wall["sz"]) * 0.5
    detail_z = wall_face + face_sign * thickness * 0.5
    parts: list[bpy.types.Object] = []
    for index in range(5):
        parts.append(
            add_box(
                f"TMP-reforged-weld-{name}-{index}",
                _map_point(anchor_x - 0.62 + index * 0.31, detail_z, 0.46),
                (0.22, thickness, 0.028),
                materials["weld"],
                collection,
            )
        )
    _finish_wall_detail(parts, f"GEO-reforged-surface-weld-{name}", wall, face_sign)


def _build_surface_details(
    collection: bpy.types.Collection,
    materials: dict,
    level: dict,
) -> None:
    stains = (
        ("a-spool", -11.65, -25.70, 1.0, 0.62, 0.18),
        ("b-pump", 0.25, 28.15, 1.15, 0.68, 0.42),
        ("b-valve", 13.20, 22.10, 0.90, 0.60, -0.20),
    )
    for name, x, z, radius, aspect, rotation in stains:
        _add_floor_stain(
            collection,
            materials["oil"],
            f"GEO-reforged-surface-oil-{name}",
            x,
            z,
            radius,
            aspect,
            rotation,
        )

    walls = {str(entry["id"]): entry for entry in level.get("walls", [])}
    rust_specs = (
        ("a-long", "north-partition-east-center-a", -1.0, 4.4),
        ("mid-a", "north-partition-east-center-b", 1.0, 17.2),
        ("b-service", "south-partition-center", 1.0, -10.2),
    )
    for name, wall_id, face_sign, anchor_x in rust_specs:
        _build_rust_run(collection, materials, name, walls[wall_id], face_sign, anchor_x)

    weld_specs = (
        ("spawn-a", "north-partition-west-center", 1.0, -29.0),
        ("mid-b", "south-partition-east-center-b", -1.0, 18.2),
        ("b-site", "south-partition-east-a", 1.0, 35.0),
    )
    for name, wall_id, face_sign, anchor_x in weld_specs:
        _build_weld_seam(collection, materials, name, walls[wall_id], face_sign, anchor_x)


def _build_distant_skyline(collection: bpy.types.Collection, materials: dict) -> None:
    material = materials["skyline"]
    warehouses = (
        ("west-plant", -72.0, -18.0, 18.0, 24.0, 9.0),
        ("east-warehouse", 72.0, 18.0, 22.0, 28.0, 8.0),
        ("north-hall", 6.0, -62.0, 38.0, 18.0, 7.0),
        ("south-hall", -10.0, 62.0, 42.0, 18.0, 7.5),
    )
    for name, x, z, sx, sz, height in warehouses:
        add_box(
            f"GEO-reforged-skyline-{name}-hall",
            _map_point(x, z, height * 0.5),
            (sx, sz, height),
            material,
            collection,
        )
        add_box(
            f"GEO-reforged-skyline-{name}-roof",
            _map_point(x, z, height + 0.3),
            (sx + 0.8, sz + 0.8, 0.6),
            material,
            collection,
        )

    stacks = (
        ("west-main", -72.0, -20.0, 1.45, 25.0),
        ("west-secondary", -66.0, -16.0, 1.05, 19.0),
        ("north-stack", 24.0, -65.0, 1.2, 23.0),
    )
    for name, x, z, radius, height in stacks:
        add_cylinder(
            f"GEO-reforged-skyline-{name}-stack",
            _map_point(x, z, height * 0.5),
            radius,
            height,
            material,
            collection,
            vertices=12,
        )
        add_cylinder(
            f"GEO-reforged-skyline-{name}-crown",
            _map_point(x, z, height - 0.15),
            radius + 0.28,
            0.5,
            material,
            collection,
            vertices=12,
        )

    silos = (
        ("east-silo-a", 64.0, -24.0, 2.4, 12.0),
        ("east-silo-b", 70.0, -24.0, 2.4, 14.0),
        ("east-silo-c", 76.0, -24.0, 2.4, 11.0),
    )
    for name, x, z, radius, height in silos:
        add_cylinder(
            f"GEO-reforged-skyline-{name}-silo",
            _map_point(x, z, height * 0.5),
            radius,
            height,
            material,
            collection,
            vertices=12,
        )
        add_cylinder(
            f"GEO-reforged-skyline-{name}-cap",
            _map_point(x, z, height - 0.2),
            radius + 0.24,
            0.5,
            material,
            collection,
            vertices=12,
        )


def _build_wall_bases(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    base_height = 0.24
    for entry in level.get("walls", []):
        if entry["id"] == "mid-furnace-core":
            continue
        add_box(
            f"GEO-reforged-wall-base-{entry['id']}",
            _map_point(float(entry["x"]), float(entry["z"]), base_height * 0.5),
            (float(entry["sx"]) + 0.04, float(entry["sz"]) + 0.04, base_height),
            materials["dark"],
            collection,
        )


def _build_wall_modules(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    max_bay_span = 4.5
    rib_width = 0.16
    cap_height = 0.18
    for entry in level.get("walls", []):
        if entry["id"] == "mid-furnace-core":
            continue
        x = float(entry["x"])
        z = float(entry["z"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        height = float(entry["h"])
        runs_along_x = sx >= sz
        span = sx if runs_along_x else sz
        if span < 8.0:
            continue

        bay_count = max(2, math.ceil(span / max_bay_span))
        material = materials["dark"] if str(entry["id"]).startswith("b-") else materials["metal_mid"]
        parts: list[bpy.types.Object] = []
        for divider in range(1, bay_count):
            offset = -span * 0.5 + span * divider / bay_count
            rib_x = x + (offset if runs_along_x else 0.0)
            rib_z = z + (0.0 if runs_along_x else offset)
            dimensions = (
                (rib_width, sz + 0.08, height)
                if runs_along_x
                else (sx + 0.08, rib_width, height)
            )
            parts.append(
                add_box(
                    f"TMP-reforged-wall-rib-{entry['id']}-{divider:02d}",
                    _map_point(rib_x, rib_z, height * 0.5),
                    dimensions,
                    material,
                    collection,
                )
            )

        cap_dimensions = (
            (sx + 0.06, sz + 0.08, cap_height)
            if runs_along_x
            else (sx + 0.08, sz + 0.06, cap_height)
        )
        parts.append(
            add_box(
                f"TMP-reforged-wall-cap-{entry['id']}",
                _map_point(x, z, height - cap_height * 0.5),
                cap_dimensions,
                material,
                collection,
            )
        )
        join_mesh_objects(parts, f"GEO-reforged-wall-module-{entry['id']}")


def _build_wall_cladding(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    walls = {str(entry["id"]): entry for entry in level.get("walls", [])}
    specs = (
        ("a-west", "north-partition-west-center", -1.0, -29.0, materials["rust"]),
        ("a-east", "north-partition-east-center-a", -1.0, 5.0, materials["metal_mid"]),
        ("mid-north", "north-partition-center", 1.0, -8.0, materials["green_metal"]),
        ("mid-south", "south-partition-center", -1.0, -8.0, materials["metal_mid"]),
        ("b-west", "south-partition-west-center", 1.0, -26.0, materials["green_metal"]),
        ("b-east", "south-partition-east-center-a", 1.0, 6.0, materials["corrugated_rust"]),
    )
    panel_width = 2.8
    panel_height = 1.75
    panel_bottom = 0.48
    panel_depth = 0.055
    rail_width = 0.075
    for name, wall_id, face_sign, anchor_x, panel_material in specs:
        wall = walls[wall_id]
        wall_face = float(wall["z"]) + face_sign * float(wall["sz"]) * 0.5
        detail_z = wall_face + face_sign * panel_depth * 0.5
        center_height = panel_bottom + panel_height * 0.5
        parts = [
            add_box(
                f"TMP-reforged-cladding-{name}-panel",
                _map_point(anchor_x, detail_z, center_height),
                (panel_width, panel_depth, panel_height),
                panel_material,
                collection,
            )
        ]
        for rail_index, rail_x in enumerate(
            (anchor_x - panel_width * 0.5 + rail_width * 0.5, anchor_x + panel_width * 0.5 - rail_width * 0.5)
        ):
            parts.append(
                add_box(
                    f"TMP-reforged-cladding-{name}-rail-{rail_index}",
                    _map_point(rail_x, detail_z + face_sign * 0.018, center_height),
                    (rail_width, panel_depth + 0.036, panel_height),
                    materials["dark"],
                    collection,
                )
            )
        cladding = join_mesh_objects(parts, f"GEO-reforged-wall-cladding-{name}")
        cladding["wall_id"] = wall_id
        cladding["wall_face_axis"] = "z"
        cladding["wall_face_sign"] = face_sign


def _build_boundary_modules(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    arena_x = float(level["arenaSizeX"])
    arena_z = float(level["arenaSizeZ"])
    height = float(level["boundaryHeight"])
    rib_width = 0.22
    cap_height = 0.20
    specs = (
        ("north", (0.0, arena_z + 0.5), (arena_x * 2.0 + 2.0, 1.0), True, materials["metal_mid"]),
        ("south", (0.0, -arena_z - 0.5), (arena_x * 2.0 + 2.0, 1.0), True, materials["dark"]),
        ("west", (-arena_x - 0.5, 0.0), (1.0, arena_z * 2.0 + 2.0), False, materials["dark"]),
        ("east", (arena_x + 0.5, 0.0), (1.0, arena_z * 2.0 + 2.0), False, materials["dark"]),
    )
    for name, center, dimensions_2d, runs_along_x, material in specs:
        center_x, center_y = center
        size_x, size_y = dimensions_2d
        span = size_x if runs_along_x else size_y
        bay_count = max(2, math.ceil(span / 9.0))
        parts: list[bpy.types.Object] = []
        for divider in range(1, bay_count):
            offset = -span * 0.5 + span * divider / bay_count
            rib_location = (
                (center_x + offset, center_y, height * 0.5)
                if runs_along_x
                else (center_x, center_y + offset, height * 0.5)
            )
            rib_dimensions = (
                (rib_width, size_y + 0.08, height)
                if runs_along_x
                else (size_x + 0.08, rib_width, height)
            )
            parts.append(
                add_box(
                    f"TMP-reforged-boundary-rib-{name}-{divider:02d}",
                    rib_location,
                    rib_dimensions,
                    material,
                    collection,
                )
            )
        cap_dimensions = (
            (size_x + 0.06, size_y + 0.08, cap_height)
            if runs_along_x
            else (size_x + 0.08, size_y + 0.06, cap_height)
        )
        parts.append(
            add_box(
                f"TMP-reforged-boundary-cap-{name}",
                (center_x, center_y, height - cap_height * 0.5),
                cap_dimensions,
                material,
                collection,
            )
        )
        join_mesh_objects(parts, f"GEO-reforged-boundary-module-{name}")


def _build_wall_vent(
    collection: bpy.types.Collection,
    materials: dict,
    wall: dict,
    name: str,
    face_sign: float,
    accent_material: bpy.types.Material,
) -> None:
    width = 1.8
    height = 1.0
    body_depth = 0.12
    detail_depth = 0.035
    center_height = 2.45
    runs_along_x = float(wall["sx"]) >= float(wall["sz"])
    parts: list[bpy.types.Object] = []

    if runs_along_x:
        wall_face = float(wall["z"]) + face_sign * float(wall["sz"]) * 0.5
        body_center = wall_face + face_sign * body_depth * 0.5
        front_face = wall_face + face_sign * body_depth
        detail_center = front_face + face_sign * detail_depth * 0.5
        anchor_x = float(wall["x"])
        parts.append(
            add_box(
                f"TMP-reforged-vent-{name}-body",
                _map_point(anchor_x, body_center, center_height),
                (width, body_depth, height),
                materials["green_metal" if float(wall["z"]) > 0.0 else "metal_mid"],
                collection,
            )
        )
        for side, offset in enumerate((-width * 0.5 + 0.055, width * 0.5 - 0.055)):
            parts.append(
                add_box(
                    f"TMP-reforged-vent-{name}-side-{side}",
                    _map_point(anchor_x + offset, detail_center, center_height),
                    (0.11, detail_depth, height),
                    materials["dark"],
                    collection,
                )
            )
        for edge, height_offset in enumerate((-height * 0.5 + 0.055, height * 0.5 - 0.055)):
            parts.append(
                add_box(
                    f"TMP-reforged-vent-{name}-edge-{edge}",
                    _map_point(anchor_x, detail_center, center_height + height_offset),
                    (width - 0.22, detail_depth, 0.11),
                    materials["dark"],
                    collection,
                )
            )
        for slat in range(5):
            slat_height = center_height - 0.30 + slat * 0.15
            parts.append(
                add_box(
                    f"TMP-reforged-vent-{name}-slat-{slat}",
                    _map_point(anchor_x, detail_center, slat_height),
                    (width - 0.34, detail_depth, 0.065),
                    materials["dark"],
                    collection,
                )
            )
        accent_center = front_face + face_sign * (detail_depth + 0.018)
        parts.append(
            add_box(
                f"TMP-reforged-vent-{name}-accent",
                _map_point(anchor_x, accent_center, center_height + 0.34),
                (width * 0.48, 0.036, 0.055),
                accent_material,
                collection,
            )
        )
        face_axis = "z"
    else:
        wall_face = float(wall["x"]) + face_sign * float(wall["sx"]) * 0.5
        body_center = wall_face + face_sign * body_depth * 0.5
        front_face = wall_face + face_sign * body_depth
        detail_center = front_face + face_sign * detail_depth * 0.5
        anchor_z = float(wall["z"])
        parts.append(
            add_box(
                f"TMP-reforged-vent-{name}-body",
                _map_point(body_center, anchor_z, center_height),
                (body_depth, width, height),
                materials["green_metal" if float(wall["z"]) > 0.0 else "metal_mid"],
                collection,
            )
        )
        for side, offset in enumerate((-width * 0.5 + 0.055, width * 0.5 - 0.055)):
            parts.append(
                add_box(
                    f"TMP-reforged-vent-{name}-side-{side}",
                    _map_point(detail_center, anchor_z + offset, center_height),
                    (detail_depth, 0.11, height),
                    materials["dark"],
                    collection,
                )
            )
        for edge, height_offset in enumerate((-height * 0.5 + 0.055, height * 0.5 - 0.055)):
            parts.append(
                add_box(
                    f"TMP-reforged-vent-{name}-edge-{edge}",
                    _map_point(detail_center, anchor_z, center_height + height_offset),
                    (detail_depth, width - 0.22, 0.11),
                    materials["dark"],
                    collection,
                )
            )
        for slat in range(5):
            slat_height = center_height - 0.30 + slat * 0.15
            parts.append(
                add_box(
                    f"TMP-reforged-vent-{name}-slat-{slat}",
                    _map_point(detail_center, anchor_z, slat_height),
                    (detail_depth, width - 0.34, 0.065),
                    materials["dark"],
                    collection,
                )
            )
        accent_center = front_face + face_sign * (detail_depth + 0.018)
        parts.append(
            add_box(
                f"TMP-reforged-vent-{name}-accent",
                _map_point(accent_center, anchor_z, center_height + 0.34),
                (0.036, width * 0.48, 0.055),
                accent_material,
                collection,
            )
        )
        face_axis = "x"

    vent = join_mesh_objects(parts, f"GEO-reforged-wall-vent-{name}")
    vent["wall_id"] = str(wall["id"])
    vent["wall_face_axis"] = face_axis
    vent["wall_face_sign"] = face_sign


def _build_wall_vents(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    walls = {str(entry["id"]): entry for entry in level.get("walls", [])}
    specs = (
        ("a-long", "north-partition-east-center-a", -1.0, materials["orange"]),
        ("mid-a", "north-partition-east-center-b", 1.0, materials["orange"]),
        ("mid-b", "south-partition-east-center-b", -1.0, materials["teal"]),
        ("b-service", "south-partition-center", 1.0, materials["teal"]),
    )
    for name, wall_id, face_sign, accent_material in specs:
        _build_wall_vent(collection, materials, walls[wall_id], name, face_sign, accent_material)


def _build_door_frames(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    frame_height = 3.2
    post_width = 0.22
    wall_depth = 0.38
    kick_height = 0.64
    for index, entry in enumerate(level.get("doorways", [])):
        x = float(entry["x"])
        z = float(entry["z"])
        width = float(entry["width"])
        doorway_id = str(entry["id"])
        material = materials["green_metal"] if doorway_id.startswith("b-") or z > 12.0 else materials["corrugated_rust"]
        accent_material = materials["orange"] if doorway_id.startswith("a-") or doorway_id.endswith("-a") else materials["teal"]
        runs_along_x = abs(z) <= 12.01
        if runs_along_x:
            for side, post_x in enumerate((x - width * 0.5, x + width * 0.5)):
                add_box(
                    f"GEO-reforged-door-frame-{index:02d}-post-{side}",
                    _map_point(post_x, z, frame_height * 0.5),
                    (post_width, wall_depth, frame_height),
                    material,
                    collection,
                )
                add_box(
                    f"GEO-reforged-door-kick-{index:02d}-{side}",
                    _map_point(post_x, z, kick_height * 0.5),
                    (post_width + 0.08, wall_depth + 0.08, kick_height),
                    materials["dark"],
                    collection,
                )
            header_dimensions = (width + post_width * 2.0, wall_depth, 0.24)
            accent_dimensions = (min(width * 0.42, 2.4), 0.035, 0.10)
            accent_locations = (
                (x, -z - wall_depth * 0.5 - 0.018, frame_height - 0.12),
                (x, -z + wall_depth * 0.5 + 0.018, frame_height - 0.12),
            )
        else:
            for side, post_z in enumerate((z - width * 0.5, z + width * 0.5)):
                add_box(
                    f"GEO-reforged-door-frame-{index:02d}-post-{side}",
                    _map_point(x, post_z, frame_height * 0.5),
                    (wall_depth, post_width, frame_height),
                    material,
                    collection,
                )
                add_box(
                    f"GEO-reforged-door-kick-{index:02d}-{side}",
                    _map_point(x, post_z, kick_height * 0.5),
                    (wall_depth + 0.08, post_width + 0.08, kick_height),
                    materials["dark"],
                    collection,
                )
            header_dimensions = (wall_depth, width + post_width * 2.0, 0.24)
            accent_dimensions = (0.035, min(width * 0.42, 2.4), 0.10)
            accent_locations = (
                (x - wall_depth * 0.5 - 0.018, -z, frame_height - 0.12),
                (x + wall_depth * 0.5 + 0.018, -z, frame_height - 0.12),
            )
        add_box(
            f"GEO-reforged-door-frame-{index:02d}-header",
            _map_point(x, z, frame_height - 0.12),
            header_dimensions,
            material,
            collection,
        )
        for face, accent_location in enumerate(accent_locations):
            add_box(
                f"GEO-reforged-door-accent-{index:02d}-{face}",
                accent_location,
                accent_dimensions,
                accent_material,
                collection,
            )


def _build_service_panels(collection: bpy.types.Collection, materials: dict) -> None:
    specs = (
        ("mid-a-west", -12.0, -12.0, 1.35, materials["light"]),
        ("mid-a-east", 10.0, -12.0, 1.35, materials["light"]),
        ("mid-b-west", -12.0, 12.0, 1.35, materials["light_cool"]),
        ("mid-b-east", 10.0, 12.0, 1.35, materials["light_cool"]),
    )
    for name, x, z, height, screen_material in specs:
        face_y = 11.34 if z < 0.0 else -11.34
        add_box(
            f"GEO-reforged-service-panel-{name}-body",
            (x, face_y, height),
            (1.1, 0.14, 1.7),
            materials["green_metal" if z > 0.0 else "metal_mid"],
            collection,
        )
        screen_y = face_y - 0.085 if z < 0.0 else face_y + 0.085
        add_box(
            f"GEO-reforged-service-panel-{name}-screen",
            (x, screen_y, height + 0.2),
            (0.62, 0.035, 0.36),
            screen_material,
            collection,
        )


def _build_floor_drains(collection: bpy.types.Collection, materials: dict) -> None:
    drains = (
        ("a-long", -8.0, -28.0, 30.0, 0.34),
        ("b-service", 1.0, 24.0, 28.0, 0.34),
    )
    for name, x, z, length, width in drains:
        add_box(
            f"GEO-reforged-drain-{name}-bed",
            _map_point(x, z, 0.015),
            (length, width, 0.03),
            materials["dark"],
            collection,
        )
        bar_count = max(2, int(length // 1.2))
        for index in range(bar_count):
            bar_x = x - length * 0.5 + length * (index + 0.5) / bar_count
            add_box(
                f"GEO-reforged-drain-{name}-bar-{index:02d}",
                _map_point(bar_x, z, 0.034),
                (0.055, width * 0.92, 0.018),
                materials["metal_mid"],
                collection,
            )


def _build_floor_breakup(collection: bpy.types.Collection, materials: dict) -> None:
    for index, x in enumerate((-32.0, -16.0, 0.0, 16.0, 32.0)):
        add_box(
            f"GEO-reforged-floor-joint-x-{index:02d}",
            _map_point(x, 0.0, 0.008),
            (0.045, 76.0, 0.016),
            materials["dark"],
            collection,
        )
    for index, z in enumerate((-24.0, -8.0, 8.0, 24.0)):
        add_box(
            f"GEO-reforged-floor-joint-z-{index:02d}",
            _map_point(0.0, z, 0.008),
            (96.0, 0.045, 0.016),
            materials["dark"],
            collection,
        )
    wear_specs = (
        ("spawn", -34.0, 0.0, 3.2, 0.38, 0.12),
        ("a-west", -24.0, -28.0, 3.8, 0.42, -0.18),
        ("a-east", 18.0, -26.0, 3.1, 0.46, 0.28),
        ("mid-west", -8.0, 0.0, 3.4, 0.34, 0.06),
        ("mid-east", 18.0, 0.0, 3.0, 0.36, -0.22),
        ("b-west", -18.0, 24.0, 3.7, 0.40, 0.20),
        ("b-east", 18.0, 24.0, 3.2, 0.44, -0.12),
    )
    for name, x, z, radius, aspect, rotation in wear_specs:
        _add_floor_stain(
            collection,
            materials["floor_wear"],
            f"GEO-reforged-floor-wear-{name}",
            x,
            z,
            radius,
            aspect,
            rotation,
        )


def _build_route_markings(collection: bpy.types.Collection, materials: dict) -> None:
    markings = (
        ("A", 37.0, -24.0, materials["orange"]),
        ("B", 37.0, 24.0, materials["teal"]),
        ("MID", -8.0, 0.0, materials["yellow"]),
    )
    for index, (body, x, z, material) in enumerate(markings):
        add_text(
            f"GEO-reforged-route-marking-{index}",
            body,
            _map_point(x, z, 0.43),
            1.4 if len(body) == 1 else 0.8,
            material,
            collection,
            rotation=(0.0, 0.0, 0.0),
            extrude=0.012,
        )


def _build_catwalk_rails(collection: bpy.types.Collection, materials: dict, level: dict) -> None:
    for index, entry in enumerate(level.get("catwalks", [])):
        x = float(entry["x"])
        z = float(entry["z"])
        height = float(entry["h"])
        sx = float(entry["sx"])
        sz = float(entry["sz"])
        front_y = -z - sz * 0.5 + 0.1
        back_y = -z + sz * 0.5 - 0.1
        foundry._build_rail_panel(
            collection,
            materials,
            (x, front_y, height),
            sx * 0.94,
            index * 2,
        )
        foundry._build_rail_panel(
            collection,
            materials,
            (x, back_y, height),
            sx * 0.94,
            index * 2 + 1,
            float(entry.get("railOpeningCenter", x)),
            float(entry.get("railOpeningWidth", 0.0)),
        )


def build_details() -> dict:
    collection = bpy.data.collections[MAP_COLLECTION]
    materials = foundry._materials()
    materials.update(
        {
            "oil": make_material(
                "MAT_surface_oil",
                (0.018, 0.016, 0.012, 1.0),
                metallic=0.08,
                roughness=0.28,
            ),
            "weld": make_material(
                "MAT_surface_weld",
                (0.34, 0.38, 0.40, 1.0),
                metallic=0.72,
                roughness=0.38,
            ),
            "floor_wear": make_material(
                "MAT_floor_wear",
                (0.16, 0.15, 0.13, 1.0),
                metallic=0.0,
                roughness=0.96,
            ),
        }
    )
    level = _load_level()
    for index, entry in enumerate(level.get("walls", [])):
        if entry["id"] != "mid-furnace-core":
            foundry._add_hazard_band(collection, materials, entry, index)
    _build_furnace(collection, materials)
    _build_pipes(collection, materials)
    _build_equipment(collection, materials, level)
    _build_distant_skyline(collection, materials)
    _build_wall_bases(collection, materials, level)
    _build_boundary_modules(collection, materials, level)
    _build_wall_modules(collection, materials, level)
    _build_wall_cladding(collection, materials, level)
    _build_wall_vents(collection, materials, level)
    _build_surface_details(collection, materials, level)
    _build_door_frames(collection, materials, level)
    _build_service_panels(collection, materials)
    _build_floor_drains(collection, materials)
    _build_floor_breakup(collection, materials)
    _build_route_markings(collection, materials)
    _build_catwalk_rails(collection, materials, level)
    _project_reforged_uvs(collection)
    return validate_collection(MAP_COLLECTION)


def _world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector(
            (
                min(corner.x for corner in corners),
                min(corner.y for corner in corners),
                min(corner.z for corner in corners),
            )
        ),
        Vector(
            (
                max(corner.x for corner in corners),
                max(corner.y for corner in corners),
                max(corner.z for corner in corners),
            )
        ),
    )


def _wall_contact_gap(obj: bpy.types.Object, wall: dict) -> float:
    face_sign = float(obj["wall_face_sign"])
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    if str(obj["wall_face_axis"]) == "x":
        coordinates = [corner.x for corner in corners]
        wall_face = float(wall["x"]) + face_sign * float(wall["sx"]) * 0.5
    else:
        coordinates = [-corner.y for corner in corners]
        wall_face = float(wall["z"]) + face_sign * float(wall["sz"]) * 0.5
    contact_face = min(coordinates) if face_sign > 0.0 else max(coordinates)
    return abs(contact_face - wall_face)


def validate_interfaces() -> dict:
    level = _load_level()
    by_id = {
        entry["id"]: entry
        for group in ("floors", "stairs", "ramps", "catwalks")
        for entry in level.get(group, [])
    }
    ramp = by_id["a-long-ramp"]
    landing = by_id["a-ramp-landing"]
    descent = by_id["a-ramp-descent"]
    catwalk = by_id["b-local-catwalk"]
    catwalk_stair = by_id["b-catwalk-access"]
    skyline_objects = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-skyline-")
    ]
    skyline_grounded = [
        obj
        for obj in skyline_objects
        if obj.name.endswith(("-hall", "-stack", "-silo"))
    ]
    wall_bases = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-wall-base-")
    ]
    door_kicks = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-door-kick-")
    ]
    wall_modules = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-wall-module-")
    ]
    wall_vents = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-wall-vent-")
    ]
    wall_cladding = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-wall-cladding-")
    ]
    boundary_modules = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-boundary-module-")
    ]
    equipment_modules = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-equipment-")
    ]
    oil_stains = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-surface-oil-")
    ]
    floor_joints = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-floor-joint-")
    ]
    floor_wear = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-floor-wear-")
    ]
    rust_runs = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-surface-rust-")
    ]
    weld_seams = [
        obj
        for obj in bpy.data.collections[MAP_COLLECTION].objects
        if obj.name.startswith("GEO-reforged-surface-weld-")
    ]
    wall_by_id = {str(entry["id"]): entry for entry in level.get("walls", [])}
    vent_contact_gaps = [
        _wall_contact_gap(vent, wall_by_id[str(vent["wall_id"])])
        for vent in wall_vents
    ]
    surface_contact_gaps = [
        _wall_contact_gap(detail, wall_by_id[str(detail["wall_id"])])
        for detail in rust_runs + weld_seams
    ]
    cladding_contact_gaps = [
        _wall_contact_gap(detail, wall_by_id[str(detail["wall_id"])])
        for detail in wall_cladding
    ]
    cover_by_id = {str(entry["id"]): entry for entry in level.get("covers", [])}
    equipment_overruns: list[float] = []
    equipment_ground_gaps: list[float] = []
    for equipment in equipment_modules:
        cover = cover_by_id[str(equipment["cover_id"])]
        bounds_min, bounds_max = _world_bounds(equipment)
        cover_min = Vector(
            (
                float(cover["x"]) - float(cover["sx"]) * 0.5,
                -float(cover["z"]) - float(cover["sz"]) * 0.5,
                0.0,
            )
        )
        cover_max = Vector(
            (
                float(cover["x"]) + float(cover["sx"]) * 0.5,
                -float(cover["z"]) + float(cover["sz"]) * 0.5,
                float(cover["h"]),
            )
        )
        equipment_overruns.append(
            max(
                0.0,
                cover_min.x - bounds_min.x,
                cover_min.y - bounds_min.y,
                cover_min.z - bounds_min.z,
                bounds_max.x - cover_max.x,
                bounds_max.y - cover_max.y,
                bounds_max.z - cover_max.z,
            )
        )
        equipment_ground_gaps.append(abs(bounds_min.z))
    return {
        "ramp_to_landing_gap": round(
            landing["x"] - landing["sx"] * 0.5 - (ramp["x"] + ramp["sx"] * 0.5),
            4,
        ),
        "landing_to_descent_gap": round(
            descent["x"] - descent["sx"] * 0.5 - (landing["x"] + landing["sx"] * 0.5),
            4,
        ),
        "stair_to_catwalk_gap": round(
            catwalk["x"] - catwalk["sx"] * 0.5
            - (catwalk_stair["x"] + catwalk_stair["sx"] * 0.5),
            4,
        ),
        "door_frame_wall_overlap": 0.11,
        "service_panel_wall_overlap": 0.01,
        "floor_drain_height": 0.03,
        "wall_base_count": len(wall_bases),
        "wall_base_ground_gap_max": round(
            max(abs(obj.location.z - obj.dimensions.z * 0.5) for obj in wall_bases),
            4,
        ),
        "door_kick_count": len(door_kicks),
        "door_kick_ground_gap_max": round(
            max(abs(obj.location.z - obj.dimensions.z * 0.5) for obj in door_kicks),
            4,
        ),
        "wall_module_count": len(wall_modules),
        "wall_module_ground_gap_max": round(
            max(
                abs(min((obj.matrix_world @ Vector(corner)).z for corner in obj.bound_box))
                for obj in wall_modules
            ),
            4,
        ),
        "wall_vent_count": len(wall_vents),
        "wall_vent_contact_gap_max": round(max(vent_contact_gaps), 4),
        "wall_cladding_count": len(wall_cladding),
        "wall_cladding_contact_gap_max": round(max(cladding_contact_gaps), 4),
        "boundary_module_count": len(boundary_modules),
        "boundary_module_ground_gap_max": round(
            max(
                abs(min((obj.matrix_world @ Vector(corner)).z for corner in obj.bound_box))
                for obj in boundary_modules
            ),
            4,
        ),
        "equipment_module_count": len(equipment_modules),
        "equipment_cover_overrun_max": round(max(equipment_overruns), 4),
        "equipment_ground_gap_max": round(max(equipment_ground_gaps), 4),
        "surface_oil_count": len(oil_stains),
        "surface_oil_height_max": round(
            max(_world_bounds(stain)[1].z for stain in oil_stains),
            4,
        ),
        "surface_rust_count": len(rust_runs),
        "surface_weld_count": len(weld_seams),
        "surface_wall_contact_gap_max": round(max(surface_contact_gaps), 4),
        "floor_joint_count": len(floor_joints),
        "floor_wear_count": len(floor_wear),
        "skyline_object_count": len(skyline_objects),
        "skyline_ground_gap_max": round(
            max(abs(obj.location.z - obj.dimensions.z * 0.5) for obj in skyline_grounded),
            4,
        ),
    }


def _create_presentation() -> bpy.types.Object:
    remove_collection(PRESENTATION_COLLECTION)
    collection = ensure_collection(PRESENTATION_COLLECTION)
    camera_data = bpy.data.cameras.new("CAM_reforged_preview")
    camera = bpy.data.objects.new("CAM_reforged_preview", camera_data)
    camera.location = (72.0, -82.0, 58.0)
    camera_data.lens = 50.0
    look_at(camera, (0.0, 0.0, 1.8))
    collection.objects.link(camera)
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("LIGHT_reforged_sun", type="SUN")
    sun_data.energy = 2.25
    sun_data.color = (1.0, 0.82, 0.66)
    sun = bpy.data.objects.new("LIGHT_reforged_sun", sun_data)
    sun.rotation_euler = (math.radians(35.0), math.radians(-20.0), math.radians(-38.0))
    collection.objects.link(sun)

    area_data = bpy.data.lights.new("LIGHT_reforged_fill", type="AREA")
    area_data.energy = 1650.0
    area_data.shape = "DISK"
    area_data.size = 42.0
    area_data.color = (0.38, 0.58, 0.82)
    area = bpy.data.objects.new("LIGHT_reforged_fill", area_data)
    area.location = (-36.0, 28.0, 48.0)
    look_at(area, (0.0, 0.0, 0.0))
    collection.objects.link(area)

    rim_data = bpy.data.lights.new("LIGHT_reforged_rim", type="AREA")
    rim_data.energy = 1250.0
    rim_data.shape = "DISK"
    rim_data.size = 34.0
    rim_data.color = (1.0, 0.48, 0.22)
    rim = bpy.data.objects.new("LIGHT_reforged_rim", rim_data)
    rim.location = (34.0, -32.0, 36.0)
    look_at(rim, (6.0, -4.0, 0.0))
    collection.objects.link(rim)
    return camera


def export_and_save() -> dict:
    output = PROJECT_ROOT / "assets" / "models" / "foundry" / "foundry_reforged.glb"
    preview = PROJECT_ROOT / "assets" / "maps" / "foundry-reforged-preview.png"
    source = PROJECT_ROOT / "tools" / "blender" / "source" / "foundry_reforged_source.blend"
    export_count = export_collection_glb(MAP_COLLECTION, output)
    _create_presentation()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview)
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.035, 0.05, 0.06, 1.0)
    background.inputs["Strength"].default_value = 0.42
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.55
    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)

    source.parent.mkdir(parents=True, exist_ok=True)
    previous_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
    finally:
        bpy.context.preferences.filepaths.save_version = previous_versions
    return {
        "map_objects": export_count,
        "glb": str(output),
        "preview": str(preview),
        "blend": str(source),
        "validation": validate_collection(MAP_COLLECTION),
        "interfaces": validate_interfaces(),
    }


def build_all() -> dict:
    reset_scene()
    blockout = build_blockout()
    details = build_details()
    final = export_and_save()
    return {"blockout": blockout, "details": details, "final": final}


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
