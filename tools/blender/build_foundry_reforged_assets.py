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

import build_foundry_assets as foundry  # noqa: E402
from blender_build_utils import (  # noqa: E402
    add_box,
    add_cylinder,
    add_pipe,
    add_text,
    ensure_collection,
    export_collection_glb,
    look_at,
    remove_collection,
    validate_collection,
)


MAP_COLLECTION = "VB_MAP_FOUNDRY_REFORGED"
PRESENTATION_COLLECTION = "VB_PRESENTATION_REFORGED"


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
        ("north", (0.0, arena_z + 0.5, height * 0.5), (arena_x * 2.0 + 2.0, 1.0, height)),
        ("south", (0.0, -arena_z - 0.5, height * 0.5), (arena_x * 2.0 + 2.0, 1.0, height)),
        ("west", (-arena_x - 0.5, 0.0, height * 0.5), (1.0, arena_z * 2.0 + 2.0, height)),
        ("east", (arena_x + 0.5, 0.0, height * 0.5), (1.0, arena_z * 2.0 + 2.0, height)),
    )
    for name, location, dimensions in spans:
        add_box(
            f"GEO-reforged-boundary-{name}",
            location,
            dimensions,
            materials["concrete_light"],
            collection,
        )


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
        material = materials["concrete" if index % 3 == 0 else "concrete_light"]
        _add_box_entry(collection, material, entry, "wall")

    for index, entry in enumerate(level.get("covers", [])):
        foundry._build_cover(collection, materials, entry, index)

    for entry in level.get("floors", []):
        material = materials["metal_mid"] if entry.get("upper") else materials["concrete"]
        _add_box_entry(collection, material, entry, "floor")

    for index, entry in enumerate(level.get("stairs", [])):
        foundry._build_stair_run(collection, materials, entry, index)

    for entry in level.get("ramps", []):
        _add_ramp(collection, materials, entry)

    for index, entry in enumerate(level.get("catwalks", [])):
        deck_height = float(entry["h"])
        add_box(
            f"GEO-reforged-catwalk-{entry['id']}",
            _map_point(float(entry["x"]), float(entry["z"]), deck_height - 0.14),
            (float(entry["sx"]), float(entry["sz"]), 0.28),
            materials["metal_mid"],
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

    foundry._project_collection_uvs(collection, 2.5)
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


def _build_equipment(collection: bpy.types.Collection, materials: dict) -> None:
    add_cylinder(
        "GEO-reforged-a-spool",
        _map_point(-12.0, -25.5, 0.72),
        0.66,
        1.8,
        materials["rust"],
        collection,
        vertices=12,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_cylinder(
        "GEO-reforged-b-pump",
        _map_point(0.0, 28.0, 0.65),
        0.95,
        1.3,
        materials["metal_mid"],
        collection,
        vertices=12,
    )
    add_cylinder(
        "GEO-reforged-b-valve",
        _map_point(13.0, 22.0, 0.75),
        0.9,
        1.5,
        materials["rust"],
        collection,
        vertices=12,
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
    level = _load_level()
    for index, entry in enumerate(level.get("walls", [])):
        if entry["id"] != "mid-furnace-core":
            foundry._add_hazard_band(collection, materials, entry, index)
    _build_furnace(collection, materials)
    _build_pipes(collection, materials)
    _build_equipment(collection, materials)
    _build_route_markings(collection, materials)
    _build_catwalk_rails(collection, materials, level)
    foundry._project_collection_uvs(collection, 2.5)
    return validate_collection(MAP_COLLECTION)


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
