"""Deterministically build Vector Breach's rigged shared tactical actor.

The GLB owns presentation meshes, a named skeleton, sockets, and five clips.
Godot remains authoritative for capsule collision and five-zone hit resolution.
"""

import json
import math
import os

import bpy
from mathutils import Matrix


ASSET_NAME = "TacticalActor_LowPoly"
ARMATURE_NAME = "Armature"
OUTPUT_DIR = r"C:\Users\Zhang\Desktop\3Dgame\godot\assets\models\characters"
GLB_PATH = os.path.join(OUTPUT_DIR, "tactical_actor_lowpoly.glb")
BLEND_PATH = os.path.join(
    r"C:\Users\Zhang\Desktop\3Dgame\godot\tools\blender\source",
    "tactical_actor_lowpoly_source.blend",
)

BONES = {
    "root": ((0.0, 0.02, 0.0), (0.0, 0.16, 0.0), None),
    "hips": ((0.0, 0.76, 0.0), (0.0, 0.98, 0.0), "root"),
    "spine": ((0.0, 0.94, 0.0), (0.0, 1.27, 0.0), "hips"),
    "chest": ((0.0, 1.27, 0.0), (0.0, 1.52, 0.0), "spine"),
    "head": ((0.0, 1.50, 0.0), (0.0, 1.82, 0.0), "chest"),
    "upper_arm_l": ((-0.25, 1.44, 0.0), (-0.39, 1.16, 0.0), "chest"),
    "forearm_l": ((-0.39, 1.16, 0.0), (-0.35, 0.88, -0.02), "upper_arm_l"),
    "hand_l": ((-0.35, 0.88, -0.02), (-0.34, 0.76, -0.03), "forearm_l"),
    "upper_arm_r": ((0.25, 1.44, 0.0), (0.39, 1.16, 0.0), "chest"),
    "forearm_r": ((0.39, 1.16, 0.0), (0.35, 0.88, -0.02), "upper_arm_r"),
    "hand_r": ((0.35, 0.88, -0.02), (0.34, 0.76, -0.03), "forearm_r"),
    "thigh_l": ((-0.16, 0.80, 0.0), (-0.16, 0.44, 0.0), "hips"),
    "calf_l": ((-0.16, 0.44, 0.0), (-0.16, 0.08, 0.0), "thigh_l"),
    "thigh_r": ((0.16, 0.80, 0.0), (0.16, 0.44, 0.0), "hips"),
    "calf_r": ((0.16, 0.44, 0.0), (0.16, 0.08, 0.0), "thigh_r"),
}


def design_to_blender(value):
    """Convert Godot-style Y-up design coordinates to Blender Z-up."""
    x, y, z = value
    return (x, -z, y)


def design_scale(value):
    x, y, z = value
    return (x, z, y)


def make_material(name, color, metallic=0.0, roughness=0.75):
    value = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    bsdf = value.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return value


def clear_owned_asset():
    for obj in list(bpy.data.objects):
        if obj.get("vector_breach_asset") == ASSET_NAME or obj.name == ASSET_NAME:
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        if action.get("vector_breach_asset") == ASSET_NAME or action.name in {"idle", "run", "crouch", "hit", "death"}:
            bpy.data.actions.remove(action)


def make_empty(name, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj["vector_breach_asset"] = ASSET_NAME
    return obj


def build_armature(root):
    data = bpy.data.armatures.new(ARMATURE_NAME)
    armature = bpy.data.objects.new(ARMATURE_NAME, data)
    bpy.context.collection.objects.link(armature)
    armature.parent = root
    armature.show_in_front = True
    armature["vector_breach_asset"] = ASSET_NAME
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = {}
    for name, (head, tail, parent_name) in BONES.items():
        bone = data.edit_bones.new(name)
        bone.head = design_to_blender(head)
        bone.tail = design_to_blender(tail)
        edit_bones[name] = bone
        if parent_name:
            bone.parent = edit_bones[parent_name]
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def finish_mesh(obj, name, armature, material, bone_name):
    obj.name = name
    obj.data.name = name + "_Mesh"
    obj.data.materials.append(material)
    obj.parent = armature
    obj["vector_breach_asset"] = ASSET_NAME
    obj["skin_bone"] = bone_name
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature
    modifier.use_deform_preserve_volume = False
    return obj


def cube(name, location, scale, armature, material, bone_name):
    bpy.ops.mesh.primitive_cube_add(location=design_to_blender(location))
    obj = bpy.context.object
    obj.scale = design_scale(scale)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, armature, material, bone_name)


def cylinder(name, location, radius, depth, armature, material, bone_name, vertices=8):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=design_to_blender(location),
    )
    return finish_mesh(bpy.context.object, name, armature, material, bone_name)


def sphere(name, location, radius, armature, material, bone_name):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=8,
        ring_count=4,
        radius=radius,
        location=design_to_blender(location),
    )
    return finish_mesh(bpy.context.object, name, armature, material, bone_name)


def bone_socket(name, design_location, armature, bone_name):
    obj = make_empty(name)
    world_matrix = Matrix.Translation(design_to_blender(design_location))
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world_matrix
    obj["anchor_bone"] = bone_name
    return obj


def build_meshes(armature, materials):
    fabric, armor, skin, metal, accent = materials
    # Torso and replaceable equipment; all interfaces intentionally overlap by 1-3 cm.
    cube("Torso", (0.0, 1.25, 0.0), (0.27, 0.34, 0.16), armature, fabric, "spine")
    cube("ChestPlate", (0.0, 1.32, -0.17), (0.30, 0.25, 0.055), armature, armor, "chest")
    cube("Vest_Mk1", (0.0, 1.11, -0.18), (0.31, 0.22, 0.05), armature, armor, "spine")
    cube("VestPouch_L", (-0.17, 1.03, -0.245), (0.10, 0.10, 0.055), armature, accent, "spine")
    cube("VestPouch_R", (0.17, 1.03, -0.245), (0.10, 0.10, 0.055), armature, accent, "spine")
    cube("TeamChestMarker", (0.0, 1.37, -0.235), (0.13, 0.035, 0.018), armature, accent, "chest")
    cube("UtilityBelt", (0.0, 0.81, -0.02), (0.30, 0.05, 0.18), armature, armor, "hips")
    cube("Backpack", (0.0, 1.15, 0.20), (0.23, 0.27, 0.10), armature, armor, "spine")

    cylinder("Neck", (0.0, 1.61, 0.0), 0.105, 0.16, armature, skin, "head")
    sphere("Head", (0.0, 1.83, 0.0), 0.20, armature, skin, "head")
    helmet = sphere("Helmet_LowProfile", (0.0, 1.91, 0.01), 0.225, armature, armor, "head")
    helmet.scale.y = 1.08
    bpy.context.view_layer.objects.active = helmet
    helmet.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    helmet.select_set(False)
    cube("HelmetVisor", (0.0, 1.90, -0.19), (0.18, 0.055, 0.025), armature, metal, "head")

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        suffix = "l" if sign < 0 else "r"
        upper_x = 0.34 * sign
        fore_x = 0.38 * sign
        cube(side + "Shoulder", (0.30 * sign, 1.43, 0.0), (0.115, 0.14, 0.13), armature, fabric, "upper_arm_" + suffix)
        cylinder(side + "UpperArm", (upper_x, 1.28, 0.0), 0.085, 0.30, armature, fabric, "upper_arm_" + suffix)
        cylinder(side + "Forearm", (fore_x, 1.00, -0.01), 0.078, 0.28, armature, fabric, "forearm_" + suffix)
        cube("TeamPatch_" + side[0], (0.36 * sign, 1.35, -0.085), (0.06, 0.055, 0.018), armature, accent, "upper_arm_" + suffix)
        sphere(side + "Hand", (0.35 * sign, 0.83, -0.02), 0.095, armature, skin, "hand_" + suffix)

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        suffix = "l" if sign < 0 else "r"
        x = 0.16 * sign
        cylinder(side + "Thigh", (x, 0.62, 0.0), 0.105, 0.36, armature, fabric, "thigh_" + suffix)
        cylinder(side + "Calf", (x, 0.26, 0.0), 0.095, 0.36, armature, fabric, "calf_" + suffix)
        cube(side + "KneePad", (x, 0.44, -0.105), (0.115, 0.10, 0.035), armature, armor, "calf_" + suffix)
        cube(side + "Boot", (x, 0.06, -0.07), (0.13, 0.09, 0.20), armature, metal, "calf_" + suffix)

    # Socket is bone-parented and exactly co-located with the intended grip anchor.
    bone_socket("HeadSocket", (0.0, 1.65, 0.0), armature, "head")
    bone_socket("WeaponSocket", (0.26, 1.18, -0.28), armature, "hand_r")
    cube("Carbine_Visual", (0.26, 1.18, -0.54), (0.055, 0.06, 0.36), armature, metal, "hand_r")
    cube("CarbineStock", (0.26, 1.18, -0.12), (0.07, 0.07, 0.14), armature, armor, "hand_r")
    muzzle = cylinder("CarbineMuzzle", (0.26, 1.18, -0.92), 0.045, 0.14, armature, metal, "hand_r")
    muzzle.rotation_euler.x = math.pi * 0.5


def set_pose(armature, action, frame, rotations=None, locations=None):
    rotations = rotations or {}
    locations = locations or {}
    armature.animation_data.action = action
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        if bone.name in rotations:
            bone.rotation_euler = rotations[bone.name]
        if bone.name in locations:
            bone.location = design_to_blender(locations[bone.name])
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)


def make_action(armature, name, end_frame, poses):
    action = bpy.data.actions.new(name=name)
    action["vector_breach_asset"] = ASSET_NAME
    action.use_fake_user = True
    for frame, rotations, locations in poses:
        set_pose(armature, action, frame, rotations, locations)
    action.frame_start = 0
    action.frame_end = end_frame
    return action


def build_actions(armature):
    armature.animation_data_create()
    actions = []
    actions.append(make_action(armature, "idle", 36, [
        (0, {}, {}),
        (18, {"chest": (0.025, 0.0, 0.0), "head": (-0.018, 0.0, 0.0)}, {"hips": (0.0, 0.015, 0.0)}),
        (36, {}, {}),
    ]))
    actions.append(make_action(armature, "run", 16, [
        (0, {"upper_arm_l": (0.48, 0.0, -0.05), "upper_arm_r": (-0.42, 0.0, 0.05), "thigh_l": (-0.52, 0.0, 0.0), "thigh_r": (0.48, 0.0, 0.0), "calf_r": (-0.28, 0.0, 0.0)}, {}),
        (8, {"upper_arm_l": (-0.42, 0.0, -0.05), "upper_arm_r": (0.48, 0.0, 0.05), "thigh_l": (0.48, 0.0, 0.0), "thigh_r": (-0.52, 0.0, 0.0), "calf_l": (-0.28, 0.0, 0.0)}, {"hips": (0.0, 0.035, 0.0)}),
        (16, {"upper_arm_l": (0.48, 0.0, -0.05), "upper_arm_r": (-0.42, 0.0, 0.05), "thigh_l": (-0.52, 0.0, 0.0), "thigh_r": (0.48, 0.0, 0.0), "calf_r": (-0.28, 0.0, 0.0)}, {}),
    ]))
    crouch_rot = {"hips": (0.18, 0.0, 0.0), "spine": (-0.12, 0.0, 0.0), "thigh_l": (-0.72, 0.0, 0.0), "thigh_r": (-0.72, 0.0, 0.0), "calf_l": (1.16, 0.0, 0.0), "calf_r": (1.16, 0.0, 0.0)}
    actions.append(make_action(armature, "crouch", 24, [
        (0, crouch_rot, {"hips": (0.0, -0.28, 0.08)}),
        (12, dict(crouch_rot, chest=(0.025, 0.0, 0.0)), {"hips": (0.0, -0.265, 0.08)}),
        (24, crouch_rot, {"hips": (0.0, -0.28, 0.08)}),
    ]))
    actions.append(make_action(armature, "hit", 7, [
        (0, {}, {}),
        (3, {"spine": (-0.16, 0.0, 0.12), "chest": (-0.10, 0.0, 0.08), "head": (0.12, 0.0, -0.08)}, {}),
        (7, {}, {}),
    ]))
    actions.append(make_action(armature, "death", 24, [
        (0, {}, {}),
        (10, {"hips": (-0.32, 0.0, 0.12), "spine": (-0.48, 0.0, 0.10), "head": (0.24, 0.0, -0.12), "thigh_l": (0.42, 0.0, 0.0), "thigh_r": (-0.18, 0.0, 0.0)}, {"hips": (0.0, -0.18, 0.10)}),
        (24, {"hips": (-1.32, 0.0, 0.16), "spine": (-0.32, 0.0, 0.04), "head": (0.30, 0.0, -0.12), "thigh_l": (0.58, 0.0, 0.0), "thigh_r": (-0.30, 0.0, 0.0), "calf_l": (0.46, 0.0, 0.0)}, {"hips": (0.0, -0.56, 0.22)}),
    ]))
    armature.animation_data.action = actions[0]
    return actions


def validate(armature, actions):
    owned_meshes = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.get("vector_breach_asset") == ASSET_NAME]
    skinned = []
    unbound = []
    for obj in owned_meshes:
        modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE" and modifier.object == armature]
        weight_sum = sum(group.weight for vertex in obj.data.vertices for group in vertex.groups)
        if modifiers and obj.vertex_groups and weight_sum > 0.0:
            skinned.append(obj.name)
        else:
            unbound.append(obj.name)
    required_bones = set(BONES)
    actual_bones = {bone.name for bone in armature.data.bones}
    if not required_bones.issubset(actual_bones):
        raise RuntimeError("Missing bones: " + str(sorted(required_bones - actual_bones)))
    if unbound:
        raise RuntimeError("Unbound meshes: " + str(unbound))
    sockets = {name: bpy.data.objects.get(name) for name in ("HeadSocket", "WeaponSocket")}
    if any(value is None or value.parent != armature or value.parent_type != "BONE" for value in sockets.values()):
        raise RuntimeError("Bone sockets are not anchored to the armature")
    audit = {
        "asset": ASSET_NAME,
        "armature": armature.name,
        "bone_count": len(actual_bones),
        "bones": sorted(actual_bones),
        "mesh_count": len(owned_meshes),
        "skinned_mesh_count": len(skinned),
        "unbound_mesh_count": len(unbound),
        "unbound_meshes": unbound,
        "actions": [action.name for action in actions],
        "replaceable_nodes": ["Vest_Mk1", "Helmet_LowProfile", "WeaponSocket"],
        "interfaces": {
            "neck_to_torso_overlap_m": 0.06,
            "head_to_neck_overlap_m": 0.06,
            "vest_to_torso_overlap_m": 0.03,
            "helmet_to_head_overlap_m": 0.145,
            "weapon_socket_bone": "hand_r",
        },
    }
    print("TACTICAL_ACTOR_AUDIT=" + json.dumps(audit, sort_keys=True))
    return audit


def select_asset(root):
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in bpy.context.scene.objects:
        cursor = obj
        while cursor.parent is not None:
            cursor = cursor.parent
        if cursor == root:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def build():
    clear_owned_asset()
    fabric = make_material("M_Fabric", (0.105, 0.125, 0.145))
    armor = make_material("M_Armor", (0.045, 0.055, 0.065), 0.16, 0.48)
    skin = make_material("M_Skin", (0.31, 0.19, 0.13), 0.0, 0.92)
    metal = make_material("M_Weapon", (0.025, 0.030, 0.038), 0.78, 0.24)
    accent = make_material("M_TeamMarker", (0.70, 0.42, 0.12), 0.0, 0.54)
    root = make_empty(ASSET_NAME)
    armature = build_armature(root)
    build_meshes(armature, (fabric, armor, skin, metal, accent))
    actions = build_actions(armature)
    validate(armature, actions)
    select_asset(root)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_skins=True,
        export_all_influences=False,
    )
    print("TACTICAL_ACTOR_BUILD_OK", GLB_PATH)


build()
