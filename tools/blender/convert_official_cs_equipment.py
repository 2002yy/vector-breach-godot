"""Prepare optional native equipment in measured wrist and world frames."""

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import convert_official_cs_assets as assets

ITEMS = {
    "rifle-ct": "weapon_rif_m4a1_silencer",
    "rifle-t": "weapon_rif_ak47",
    "pistol": "weapon_pist_glock18",
    "knife-ct": "weapon_knife_default_ct",
    "knife-t": "weapon_knife_default_t",
    "c4": "weapon_c4",
}


def mount_frame(arm, meshes, key, correction):
    """Resolve native attachment axes into the game's upright wrist axes.

    Source gun muzzles point along Blender -Y; knife blades remain upright.
    C4 is held by its right edge with its native top panel tilted toward the eye.
    All rotations occur at the native attachment before the C4 edge translation.
    """
    anchor = arm.data.bones["ag1_hand_r"]
    native = anchor.matrix_local @ correction
    semantic = assets.shared.C.copy()
    semantic.translation = anchor.head_local
    target = semantic.inverted()
    if key == "c4":
        target = Matrix.Rotation(math.radians(50), 4, "X") @ target
        right_edge = max((target @ v.co).x for obj in meshes for v in obj.data.vertices)
        target = Matrix.Translation(Vector((-right_edge, 0, 0))) @ target
    else:
        target = Matrix.Rotation(math.pi, 4, "Y") @ target
    return target @ native


def wrist_correction(source):
    arm, _ = assets.imported(source / "ctm_fbi_varianta.gltf")
    bones = arm.data.bones
    hand = bones["hand_R"]
    z = -(bones["finger_middle_0_R"].head_local - hand.head_local).normalized()
    x = (
        bones["finger_index_0_R"].head_local - bones["finger_pinky_0_R"].head_local
    ).normalized()
    y = z.cross(x).normalized()
    x = y.cross(z).normalized()
    frame = Matrix((x, y, z)).transposed().to_4x4()
    frame.translation = hand.head_local
    return hand.matrix_local.inverted() @ frame


def export(path, objects, animations, yup):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_animations=animations,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_def_bones=False,
        export_force_sampling=True,
        export_apply=False,
        export_image_format="AUTO",
        export_yup=yup,
    )


def convert(source, output, key, name, correction):
    arm, meshes = assets.imported(source / (name + ".gltf"))
    # A source model can contain mutually exclusive legacy and HD bodies.
    hd = any(o.name.endswith(".body_hd") for o in meshes)
    meshes = [o for o in meshes if not (hd and o.name.endswith(".body_legacy"))]
    for action in bpy.data.actions:
        action.use_fake_user = True
    if key == "c4":
        # World model is a separate export: native metres, base on ground.
        points = [v.co for o in meshes for v in o.data.vertices]
        offset = Matrix.Translation(
            (
                -(min(v.x for v in points) + max(v.x for v in points)) / 2,
                -(min(v.y for v in points) + max(v.y for v in points)) / 2,
                -min(v.z for v in points),
            )
        )
        copies = []
        for obj in meshes:
            copy = obj.copy()
            copy.data = obj.data.copy()
            copy.modifiers.clear()
            copy.parent = None
            copy.data.transform(offset)
            bpy.context.collection.objects.link(copy)
            copies.append(copy)
        export(output / "c4-world.glb", copies, False, True)
        for obj in copies:
            bpy.data.objects.remove(obj, do_unlink=True)
    anchor = arm.data.bones.get("ag1_hand_r")
    if anchor is None:
        raise ValueError("Missing native right-hand attachment: " + name)
    transform = (anchor.matrix_local @ correction).inverted()
    mount = mount_frame(arm, meshes, key, correction)
    origin_error = (transform @ anchor.matrix_local @ correction).translation.length
    if origin_error > 0.00001:
        raise ValueError("Native wrist attachment failed to normalize")
    for obj in meshes:
        obj.data.transform(transform)
        obj.name = obj.name.rsplit(".", 1)[-1]
    arm.data.transform(transform)
    arm.animation_data_create()
    # Expose imported native actions to Blender's action exporter without
    # baking an inventory/dropped pose into the model's bind state.
    for action in bpy.data.actions:
        if action.slots:
            arm.animation_data.action = action
            arm.animation_data.action_slot = action.slots[0]
    arm.animation_data.action = None
    target = output / (key + ".glb")
    export(target, [arm] + meshes, True, False)
    return {
        "file": target.name,
        "sha256": assets.digest(target),
        "source": str(source / (name + ".gltf")),
        "source_sha256": assets.digest(source / (name + ".gltf")),
        "native_anchor": "ag1_hand_r",
        "wrist_origin_error_m": origin_error,
        "mount_transform": [list(mount.col[i])[:3] for i in range(4)],
        "selected_groups": [o.name for o in meshes],
        "clips": [a.name for a in bpy.data.actions],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    if args.output.resolve().parts[-4:] != (
        "assets",
        "local_reference",
        "cs_official",
        "equipment",
    ):
        raise ValueError(
            "Output must end in assets/local_reference/cs_official/equipment"
        )
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        raise FileExistsError(
            "Equipment output must be empty; preserve previous exports"
        )
    correction = wrist_correction(args.source)
    manifest = {"version": 1, "items": {}}
    for key, name in ITEMS.items():
        manifest["items"][key] = convert(
            args.source, args.output, key, name, correction
        )
        print("OFFICIAL_EQUIPMENT_EXPORTED", key, flush=True)
    world = args.output / "c4-world.glb"
    manifest["items"]["c4-world"] = {"file": world.name, "sha256": assets.digest(world)}
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
