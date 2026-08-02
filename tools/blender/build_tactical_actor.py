"""Deterministically build Vector Breach's shared low-poly tactical actor.

The generated GLB deliberately contains visuals and named animation sockets only.
Godot owns the capsule collision hull and five-zone hit model.
"""

import bpy
import os

ROOT_NAME = "TacticalActor_LowPoly"
OUTPUT_DIR = r"C:\Users\Zhang\Desktop\3Dgame\godot\assets\models\characters"
GLB_PATH = os.path.join(OUTPUT_DIR, "tactical_actor_lowpoly.glb")
BLEND_PATH = os.path.join(
    r"C:\Users\Zhang\Desktop\3Dgame\godot\tools\blender\source",
    "tactical_actor_lowpoly_source.blend",
)


def material(name, color, metallic=0.0, roughness=0.75):
    value = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    bsdf = value.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return value


FABRIC = material("M_Fabric", (0.105, 0.125, 0.145))
ARMOR = material("M_Armor", (0.045, 0.055, 0.065), 0.16, 0.48)
SKIN = material("M_Skin", (0.31, 0.19, 0.13), 0.0, 0.92)
METAL = material("M_Weapon", (0.025, 0.030, 0.038), 0.78, 0.24)
ACCENT = material("M_TeamMarker", (0.70, 0.42, 0.12), 0.0, 0.54)
OWNED_NAMES = {
    ROOT_NAME, "VisualRig", "Hips", "Torso", "ChestPlate", "Vest_Mk1", "VestPouch_L", "VestPouch_R",
    "UtilityBelt", "Backpack", "TeamChestMarker", "TeamPatch_L", "TeamPatch_R", "HeadSocket", "Head", "Helmet_LowProfile", "HelmetVisor",
    "LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "LeftHand", "RightHand",
    "LeftHip", "RightHip", "LeftLeg", "RightLeg", "LeftKneePad", "RightKneePad", "LeftBoot", "RightBoot",
    "WeaponSocket", "Carbine_Visual", "CarbineStock", "CarbineMuzzle",
}


def is_owned_name(name):
    return any(name == base or name.startswith(base + ".") for base in OWNED_NAMES)


def blender_location(location):
    """Map design-space Y-up positions to Blender's Z-up authoring space."""
    x, y, z = location
    return (x, -z, y)


def blender_scale(scale):
    x, y, z = scale
    return (x, z, y)


def empty(name, location, parent):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = blender_location(location)
    obj.parent = parent
    obj["vector_breach_asset"] = ROOT_NAME
    return obj


def finish(obj, name, parent, mat):
    obj.name = name
    obj.parent = parent
    obj.data.materials.append(mat)
    obj["vector_breach_asset"] = ROOT_NAME
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def cube(name, location, scale, parent, mat):
    bpy.ops.mesh.primitive_cube_add(location=blender_location(location))
    obj = bpy.context.object
    obj.scale = blender_scale(scale)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, parent, mat)


def cylinder(name, location, radius, depth, parent, mat, vertices=8):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=blender_location(location)
    )
    return finish(bpy.context.object, name, parent, mat)


def sphere(name, location, radius, parent, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=8, ring_count=4, radius=radius, location=blender_location(location)
    )
    return finish(bpy.context.object, name, parent, mat)


def build():
    # The recipe owns only this named root; no unrelated Blender objects are removed.
    for obj in list(bpy.data.objects):
        if obj.get("vector_breach_asset") == ROOT_NAME or is_owned_name(obj.name):
            bpy.data.objects.remove(obj, do_unlink=True)

    root = empty(ROOT_NAME, (0.0, 0.0, 0.0), None)
    visual_rig = empty("VisualRig", (0.0, 0.0, 0.0), root)
    hips = empty("Hips", (0.0, 0.93, 0.0), visual_rig)

    # 1) Major silhouette: 1.80m standing height, 0.72m shoulder span.
    torso = cube("Torso", (0.0, 0.34, 0.0), (0.27, 0.34, 0.16), hips, FABRIC)
    torso.rotation_euler.x = 0.04
    chest = cube("ChestPlate", (0.0, 0.39, -0.17), (0.30, 0.25, 0.055), hips, ARMOR)
    vest = cube("Vest_Mk1", (0.0, 0.18, -0.18), (0.31, 0.22, 0.05), hips, ARMOR)
    pouch_l = cube("VestPouch_L", (-0.17, 0.10, -0.245), (0.10, 0.10, 0.055), hips, ACCENT)
    pouch_r = cube("VestPouch_R", (0.17, 0.10, -0.245), (0.10, 0.10, 0.055), hips, ACCENT)
    chest_marker = cube("TeamChestMarker", (0.0, 0.44, -0.235), (0.13, 0.035, 0.018), hips, ACCENT)
    belt = cube("UtilityBelt", (0.0, -0.12, -0.02), (0.30, 0.05, 0.18), hips, ARMOR)
    backpack = cube("Backpack", (0.0, 0.22, 0.20), (0.23, 0.27, 0.10), hips, ARMOR)

    # 2) Head assembly seats directly on the torso top plane (hips y + 0.68).
    head_socket = empty("HeadSocket", (0.0, 0.73, 0.0), hips)
    sphere("Head", (0.0, 0.17, 0.0), 0.20, head_socket, SKIN)
    helmet = sphere("Helmet_LowProfile", (0.0, 0.25, 0.01), 0.225, head_socket, ARMOR)
    helmet.scale.z = 1.08
    visor = cube("HelmetVisor", (0.0, 0.24, -0.19), (0.18, 0.055, 0.025), head_socket, METAL)

    # 3) Limbs are parented to animation sockets, not to collision/hit volumes.
    for side, x, sign in (("Left", -0.37, -1.0), ("Right", 0.37, 1.0)):
        shoulder = empty(side + "Shoulder", (x, 0.50, 0.0), hips)
        arm = cylinder(side + "Arm", (0.0, -0.20, 0.0), 0.085, 0.48, shoulder, FABRIC)
        arm.rotation_euler.x = 0.10
        cube("TeamPatch_" + side[0], (0.0, -0.06, -0.085), (0.095, 0.030, 0.018), shoulder, ACCENT)
        hand = sphere(side + "Hand", (0.0, -0.47, -0.02), 0.10, shoulder, SKIN)
        shoulder.rotation_euler.z = -sign * 0.12
    for side, x in (("Left", -0.16), ("Right", 0.16)):
        hip = empty(side + "Hip", (x, -0.18, 0.0), hips)
        leg = cylinder(side + "Leg", (0.0, -0.34, 0.0), 0.105, 0.68, hip, FABRIC)
        knee = cube(side + "KneePad", (0.0, -0.35, -0.105), (0.115, 0.10, 0.035), hip, ARMOR)
        boot = cube(side + "Boot", (0.0, -0.71, -0.07), (0.13, 0.09, 0.20), hip, METAL)

    # 4) Weapon anchor is an explicit named socket shared by every loadout.
    weapon_socket = empty("WeaponSocket", (0.26, 0.25, -0.28), hips)
    rifle_body = cube("Carbine_Visual", (0.0, 0.0, -0.26), (0.055, 0.06, 0.36), weapon_socket, METAL)
    rifle_stock = cube("CarbineStock", (0.0, 0.0, 0.16), (0.07, 0.07, 0.14), weapon_socket, ARMOR)
    muzzle = cylinder("CarbineMuzzle", (0.0, 0.0, -0.64), 0.045, 0.14, weapon_socket, METAL)
    muzzle.rotation_euler.x = 1.5708

    # Export only the asset hierarchy, with named sockets intact.
    # Export only this hierarchy; the open Blender scene can contain unrelated objects.
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in bpy.context.scene.objects:
        cursor = obj
        while cursor.parent is not None:
            cursor = cursor.parent
        if cursor == root:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials='EXPORT',
    )
    print("TACTICAL_ACTOR_BUILD_OK", GLB_PATH)


build()
