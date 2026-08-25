from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = PROJECT_ROOT / ".tools" / "weapon-audit"
WEAPON_COLLECTIONS = {
    "rifle": "VB_WEAPON_RIFLE",
    "pistol": "VB_WEAPON_PISTOL",
}
VIEWS = {
    "left": Vector((1.0, 0.0, 0.0)),
    "right": Vector((-1.0, 0.0, 0.0)),
    "front": Vector((0.0, -1.0, 0.0)),
    "back": Vector((0.0, 1.0, 0.0)),
    "top": Vector((0.0, 0.0, 1.0)),
    "bottom": Vector((0.0, 0.0, -1.0)),
}


def _bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    minimum = Vector((float("inf"),) * 3)
    maximum = Vector((float("-inf"),) * 3)
    for obj in objects:
        if obj.type not in {"MESH", "CURVE"}:
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                minimum[axis] = min(minimum[axis], world[axis])
                maximum[axis] = max(maximum[axis], world[axis])
    return minimum, maximum


def _set_weapon_visible(target: bpy.types.Collection) -> list[bpy.types.Object]:
    visible: list[bpy.types.Object] = []
    for collection_name in WEAPON_COLLECTIONS.values():
        collection = bpy.data.collections[collection_name]
        collection.hide_render = collection != target
        for obj in collection.all_objects:
            if obj is None:
                continue
            hide_arms = "sleeve" in obj.name or "glove" in obj.name
            obj.hide_render = collection != target or hide_arms
            if collection == target and not hide_arms:
                visible.append(obj)
    presentation = bpy.data.collections.get("VB_WEAPON_PRESENTATION")
    if presentation is not None:
        presentation.hide_render = True
        for obj in presentation.all_objects:
            if obj is None:
                continue
            obj.hide_render = True
    return visible


def audit() -> dict:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    scene.render.resolution_x = 480
    scene.render.resolution_y = 480
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True

    audit_collection = bpy.data.collections.get("VB_WEAPON_AUDIT")
    if audit_collection is None:
        audit_collection = bpy.data.collections.new("VB_WEAPON_AUDIT")
        scene.collection.children.link(audit_collection)
    camera_data = bpy.data.cameras.get("CAM_weapon_audit") or bpy.data.cameras.new("CAM_weapon_audit")
    camera = bpy.data.objects.get("CAM_weapon_audit") or bpy.data.objects.new("CAM_weapon_audit", camera_data)
    if camera.name not in audit_collection.objects:
        audit_collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.hide_render = False
    scene.camera = camera

    outputs: dict[str, dict[str, str]] = {}
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    for weapon_name, collection_name in WEAPON_COLLECTIONS.items():
        collection = bpy.data.collections[collection_name]
        objects = _set_weapon_visible(collection)
        minimum, maximum = _bounds(objects)
        center = (minimum + maximum) * 0.5
        size = maximum - minimum
        maximum_extent = max(size)
        camera.data.ortho_scale = maximum_extent * 1.22
        outputs[weapon_name] = {}
        for view_name, direction in VIEWS.items():
            camera.location = center + direction * maximum_extent * 2.2
            camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
            output = OUTPUT_ROOT / f"{weapon_name}-{view_name}.png"
            scene.render.filepath = str(output)
            bpy.ops.render.render(write_still=True)
            outputs[weapon_name][view_name] = str(output)

    print("WEAPON_SIX_SIDE_AUDIT=" + json.dumps(outputs, ensure_ascii=False))
    return outputs


if __name__ == "__main__":
    audit()
