"""Convert locally acquired Source characters; run with Blender --background --python.

No downloaded content is bundled with this tool. --source is the acquired archive root;
--output must point inside the game's ignored assets/local_reference/cs_agents directory.
"""

import argparse
import bisect
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

PROFILES = {
    "ct-st6": ("海豹突击队", "CT", "ctm_st6.smd"),
    "ct-sas-officer": ("英国特勤队", "CT", "ctm_sas_body0_model0.smd"),
    "ct-fbi": ("联邦特警", "CT", "ctm_fbi_varianta.smd"),
    "t-phoenix": ("凤凰战士", "T", "tm_phoenix.smd"),
    "t-elite": ("精英叛军", "T", "tm_leet_variantf.smd"),
    "t-blackwolf": ("黑狼", "T", "tm_balkan_variantj.smd"),
}
SAS = {
    "Pelvis": "pelvis",
    "Spine": "spine_0",
    "Spine1": "spine_1",
    "Spine2": "spine_2",
    "Spine4": "spine_3",
    "Neck1": "neck_0",
    "Head1": "head_0",
}
for side in ("L", "R"):
    for a, b in {
        "Thigh": "leg_upper",
        "Calf": "leg_lower",
        "Foot": "ankle",
        "Toe0": "ball",
        "Clavicle": "clavicle",
        "UpperArm": "arm_upper",
        "Forearm": "arm_lower",
        "Hand": "hand",
    }.items():
        SAS[side + "_" + a] = b + "_" + side
    for digit, word in enumerate(("thumb", "index", "middle", "ring", "pinky")):
        for joint in range(3):
            SAS[side + "_Finger" + str(digit) + (str(joint) if joint else "")] = (
                f"finger_{word}_{joint}_{side}"
            )
SAS = {"ValveBiped.Bip01_" + k: v for k, v in SAS.items()}
C = Matrix.Rotation(math.pi / 2, 4, "X")  # glTF Y-up -> Blender Z-up
TURN = Matrix.Rotation(math.pi, 4, "Z")  # avatars face game -Z after export


def glb(path):
    raw = path.read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20 : 20 + size]), raw[28 + size :]


class Motions:
    def __init__(self, root):
        self.skel, _ = glb(root / "models/t-phoenix.glb")
        self.doc, self.binary = glb(root / "support/animations.glb")
        self.parents = {
            c: i
            for i, n in enumerate(self.skel["nodes"])
            for c in n.get("children", [])
        }
        self.rest = self.globals({})
        self.channels = {}
        for clip in self.doc["animations"]:
            channels = {}
            for channel in clip["channels"]:
                sampler = clip["samplers"][channel["sampler"]]
                name = self.doc["nodes"][channel["target"]["node"]]["name"]
                channels[(name, channel["target"]["path"])] = (
                    self.accessor(sampler["input"]),
                    self.accessor(sampler["output"]),
                )
            self.channels[clip["name"]] = channels

    def accessor(self, index):
        a = self.doc["accessors"][index]
        v = self.doc["bufferViews"][a["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        return [
            struct.unpack_from(
                "<" + "f" * width,
                self.binary,
                v.get("byteOffset", 0) + a.get("byteOffset", 0) + i * width * 4,
            )
            for i in range(a["count"])
        ]

    def globals(self, values):
        cache = {}

        def solve(i):
            if i in cache:
                return cache[i]
            node = self.skel["nodes"][i]
            name = node.get("name", "")
            q = values.get((name, "rotation"), node.get("rotation", (0, 0, 0, 1)))
            t = values.get((name, "translation"), node.get("translation", (0, 0, 0)))
            if "matrix" in node and not values.get((name, "rotation")):
                local = Matrix(
                    [node["matrix"][k : k + 4] for k in range(0, 16, 4)]
                ).transposed()
            else:
                local = Matrix.LocRotScale(
                    Vector(t), Quaternion((q[3], q[0], q[1], q[2])), Vector((1, 1, 1))
                )
            cache[i] = solve(self.parents[i]) @ local if i in self.parents else local
            return cache[i]

        return {
            n.get("name", ""): C @ solve(i) for i, n in enumerate(self.skel["nodes"])
        }

    def pose(self, name, time):
        values = {}
        for key, (times, samples) in self.channels[name].items():
            ts = [t[0] for t in times]
            i = max(0, bisect.bisect_right(ts, time) - 1)
            j = min(i + 1, len(ts) - 1)
            weight = (time - ts[i]) / (ts[j] - ts[i]) if ts[j] > ts[i] else 0
            if key[1] == "rotation":
                a = samples[i]
                b = samples[j]
                q = Quaternion((a[3], *a[:3])).slerp(Quaternion((b[3], *b[:3])), weight)
                values[key] = (q.x, q.y, q.z, q.w)
            else:
                values[key] = tuple(
                    x + (y - x) * weight for x, y in zip(samples[i], samples[j])
                )
        return self.globals(values)

    def duration(self, name):
        return max(times[-1][0] for times, _ in self.channels[name].values())


def materials(meshes):
    used = {m for o in meshes for m in o.data.materials if m}
    for material in used:
        old = list(material.node_tree.nodes)
        images = {
            n.label.lower(): n.image for n in old if n.type == "TEX_IMAGE" and n.image
        }
        base = images.get("$basetexture") or images.get("$iris")
        normal = images.get("$bumpmap")
        material.node_tree.nodes.clear()
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        output = nodes.new("ShaderNodeOutputMaterial")
        shader.inputs["Roughness"].default_value = 0.76
        shader.inputs["Base Color"].default_value = (0.08, 0.065, 0.045, 1)
        if "lens" in material.name.lower() or "glass" in material.name.lower():
            shader.inputs["Roughness"].default_value = 0.25
            shader.inputs["Metallic"].default_value = 0.25
        links.new(shader.outputs["BSDF"], output.inputs["Surface"])
        if base:
            base.colorspace_settings.name = "sRGB"
            node = nodes.new("ShaderNodeTexImage")
            node.image = base
            links.new(node.outputs["Color"], shader.inputs["Base Color"])
        if normal:
            normal.colorspace_settings.name = "Non-Color"
            node = nodes.new("ShaderNodeTexImage")
            node.image = normal
            bump = nodes.new("ShaderNodeNormalMap")
            bump.inputs["Strength"].default_value = 0.65
            links.new(node.outputs["Color"], bump.inputs["Color"])
            links.new(bump.outputs["Normal"], shader.inputs["Normal"])
        # Mobile-sized embedded textures; SourceIO already flips DirectX normal green.
        for image in (base, normal):
            if image and max(image.size) > 1024:
                ratio = 1024 / max(image.size)
                image.scale(round(image.size[0] * ratio), round(image.size[1] * ratio))


def normalize(arm, meshes, sas):
    # SourceIO produces Z-up for this GMod port and Y-up for the five SFM ports.
    orient = Matrix.Identity(4) if sas else C
    for o in meshes:
        o.data.transform(orient @ o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    arm.data.transform(orient @ arm.matrix_world)
    arm.matrix_world = Matrix.Identity(4)
    for old, new in SAS.items():
        if old in arm.data.bones:
            arm.data.bones[old].name = new
            for obj in meshes:
                if old in obj.vertex_groups:
                    obj.vertex_groups[old].name = new
    coords = [v.co for obj in meshes for v in obj.data.vertices]
    low = min(v.z for v in coords)
    high = max(v.z for v in coords)
    scale = 1.8 / (high - low)
    mat = TURN @ Matrix.Scale(scale, 4) @ Matrix.Translation((0, 0, -low))
    for obj in meshes:
        obj.data.transform(mat)
    arm.data.transform(mat)


def retarget(arm, motions):
    rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    actions = []
    clips = {
        "idle": "rifle/idle",
        "run": "rifle/run_n",
        "crouch": "rifle/crouchIdle",
        "death": "death",
        "pistol_idle": "pistol/idle",
        "pistol_run": "pistol/run_n",
        "pistol_crouch": "pistol/crouchIdle",
        "knife_idle": "knife/idle",
        "knife_run": "knife/run_n",
        "knife_crouch": "knife/crouchIdle",
        "reload": "rifle/reload",
        "pistol_reload": "pistol/reload",
    }
    # Retarget rotations independently of the character height normalization.
    align = TURN
    src_rest = {n: align @ m for n, m in motions.rest.items()}
    arm.animation_data_create()
    bpy.context.scene.render.fps = 30
    ratio = arm.data.bones["pelvis"].head_local.z / motions.rest["pelvis"].translation.z
    for name, source in clips.items():
        length = motions.duration(source)
        target_length = 0.76 if name == "death" else max(length, 1.2)
        frames = max(2, round(target_length * 30))
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        for frame in range(frames + 1):
            time = (frame / frames) * length
            pose = {n: align @ m for n, m in motions.pose(source, time).items()}
            globals_ = {}
            for bone in arm.pose.bones:
                b = bone.bone
                name_ = bone.name
                r = rest[name_]
                parent = bone.parent
                base = (
                    globals_[parent.name] @ rest[parent.name].inverted() @ r
                    if parent
                    else r.copy()
                )
                if name_ in pose and name_ in src_rest:
                    rotation = (
                        pose[name_].to_quaternion()
                        @ src_rest[name_].to_quaternion().inverted()
                        @ r.to_quaternion()
                    )
                    position = base.translation
                    if name_ == "pelvis":
                        position = (
                            r.translation
                            + (pose[name_].translation - src_rest[name_].translation)
                            * ratio
                        )
                    base = Matrix.LocRotScale(position, rotation, Vector((1, 1, 1)))
                globals_[name_] = base
                local = (
                    (rest[parent.name].inverted() @ r).inverted()
                    @ globals_[parent.name].inverted()
                    @ base
                    if parent
                    else r.inverted() @ base
                )
                bone.matrix_basis = local
                bone.keyframe_insert("location", frame=frame)
                bone.keyframe_insert("rotation_quaternion", frame=frame)
            bpy.context.scene.frame_set(frame)
        actions.append(action)
    # A short additive hit flinch baked over the ready stance.
    idle = actions[0]
    hit = bpy.data.actions.new("hit")
    hit.use_fake_user = True
    arm.animation_data.action = idle
    bpy.context.scene.frame_set(0)
    poses = {b.name: b.matrix_basis.copy() for b in arm.pose.bones}
    arm.animation_data.action = hit
    for frame, angle in [(0, 0), (2, -0.11), (7, 0)]:
        for b in arm.pose.bones:
            b.matrix_basis = poses[b.name]
            if b.name == "spine_3":
                b.rotation_quaternion = b.rotation_quaternion @ Quaternion(
                    (1, 0, 0), angle
                )
            b.keyframe_insert("location", frame=frame)
            b.keyframe_insert("rotation_quaternion", frame=frame)
    arm.animation_data.action = idle
    bpy.context.scene.frame_set(0)
    return actions + [hit]


def export(path, objects, animated):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_animations=animated,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_def_bones=False,
        export_force_sampling=True,
        export_apply=False,
        export_image_format="AUTO",
        export_yup=animated,
    )


def arm_asset(arm, meshes, side, output):
    """Keep connected original topology and skin weights; trim only at the elbow."""
    arm.animation_data_clear()
    for b in arm.pose.bones:
        b.matrix_basis = Matrix.Identity(4)
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    hand = arm.data.bones["hand_" + side]
    fore = arm.data.bones["arm_lower_" + side]
    middle = arm.data.bones["finger_middle_0_" + side]
    index = arm.data.bones["finger_index_0_" + side]
    pinky = arm.data.bones["finger_pinky_0_" + side]
    z = -(middle.head_local - hand.head_local).normalized()
    x = (index.head_local - pinky.head_local).normalized()
    if side == "L":
        x = -x
    y = z.cross(x).normalized()
    x = y.cross(z).normalized()
    frame = Matrix((x, y, z)).transposed().to_4x4()
    frame.translation = hand.head_local
    inverse = frame.inverted()
    selected = []
    descendants = {fore.name} | {b.name for b in fore.children_recursive}
    for source in meshes:
        obj = source.copy()
        obj.data = source.data.copy()
        bpy.context.collection.objects.link(obj)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        layer = bm.verts.layers.deform.active
        groups = {g.index: g.name for g in obj.vertex_groups}
        keep = []
        for v in bm.verts:
            weights = v[layer]
            dominant = max(weights.keys(), key=weights.get) if len(weights) else -1
            if groups.get(dominant) in descendants:
                keep.append(v)
        keep = set(keep)
        bmesh.ops.delete(
            bm, geom=[v for v in bm.verts if v not in keep], context="VERTS"
        )
        bm.to_mesh(obj.data)
        bm.free()
        if not obj.data.polygons:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        obj.data.transform(inverse, shape_keys=True)
        selected.append(obj)
    copy = arm.copy()
    copy.data = arm.data.copy()
    copy.name = "ArmRig"
    copy.animation_data_clear()
    bpy.context.collection.objects.link(copy)
    copy.data.transform(inverse)
    for obj in selected:
        for mod in obj.modifiers:
            if mod.type == "ARMATURE":
                mod.object = copy
    for b in copy.pose.bones:
        b.matrix_basis = Matrix.Identity(4)
    export(output, [copy] + selected, False)
    info = {
        "forearm": list((inverse @ fore.head_local)),
        "hand_bone": hand.name,
        "forearm_bone": fore.name,
        "vertices": sum(len(o.data.vertices) for o in selected),
        "grip_frame": [list((C.inverted() @ frame).col[i])[:3] for i in range(4)],
    }
    for obj in selected + [copy]:
        bpy.data.objects.remove(obj, do_unlink=True)
    return info


def import_source(root, record, cache):
    sys.path.insert(0, str(root / "tools"))
    import SourceIO

    SourceIO.register()
    from SourceIO.blender_bindings.models import import_model
    from SourceIO.blender_bindings.models.common import put_into_collections
    from SourceIO.blender_bindings.operators.import_settings_base import ModelOptions
    from SourceIO.library.shared.content_manager import ContentManager
    from SourceIO.library.shared.content_manager.providers.loose_files import (
        LooseFilesContentProvider,
    )
    from SourceIO.library.shared.app_id import SteamAppId
    from SourceIO.library.utils import FileBuffer, TinyPath

    bpy.ops.wm.read_factory_settings(use_empty=True)
    manager = ContentManager()
    for directory in (root / "native").iterdir():
        manager.add_child(LooseFilesContentProvider(TinyPath(str(directory))))
    options = ModelOptions.default()
    options.import_physics = False
    options.create_flex_drivers = False
    options.bodygroup_vis_switches = False
    native_relative = Path(record["model"].replace("\\", "/").split("/native/", 1)[1])
    path = TinyPath(str(root / "native" / native_relative))
    with FileBuffer(path) as stream:
        container = import_model(path, stream, manager, options, SteamAppId.GARRYS_MOD)
    put_into_collections(container, record["id"], bodygroup_grouping=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(cache))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only", choices=PROFILES)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    root = args.source
    args.output.mkdir(parents=True, exist_ok=True)
    if args.output.resolve().parts[-3:] != ("assets", "local_reference", "cs_agents"):
        raise ValueError("Output must end in assets/local_reference/cs_agents")
    motions = Motions(root)
    manifest = {"version": 1, "profiles": {}}
    receipt = args.output / "manifest.json"
    if args.only and receipt.exists():
        manifest = json.loads(receipt.read_text(encoding="utf-8"))
    records = json.loads((root / "DELIVERY.json").read_text(encoding="utf-8"))[
        "packages"
    ]
    for record in records:
        id_ = record["id"]
        if args.only and args.only != id_:
            continue
        cache = root / "converted-20261016" / (id_ + ".blend")
        cache.parent.mkdir(exist_ok=True)
        if not cache.exists():
            import_source(root, record, cache)
        bpy.ops.wm.open_mainfile(filepath=str(cache))
        label, team, body = PROFILES[id_]
        arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        selected = []
        for obj in list(bpy.data.objects):
            if obj.type == "MESH":
                # One bodygroup per character, plus original gloves and SAS accessories.
                keep = (
                    obj.name == body
                    or ("glove" in obj.name.lower())
                    or (id_ == "ct-sas-officer" and "keychain" not in obj.name)
                )
                if keep:
                    selected.append(obj)
                else:
                    bpy.data.objects.remove(obj, do_unlink=True)
        materials(selected)
        normalize(arm, selected, id_ == "ct-sas-officer")
        actions = retarget(arm, motions)
        body_path = args.output / (id_ + ".glb")
        export(body_path, [arm] + selected, True)
        arms = {}
        for side in ("L", "R"):
            arms[side] = arm_asset(
                arm, selected, side, args.output / (id_ + "-arm-" + side + ".glb")
            )
        files = [body_path] + [
            args.output / (id_ + "-arm-" + s + ".glb") for s in ("L", "R")
        ]
        manifest["profiles"][id_] = {
            "name": label,
            "team": team,
            "source": record["source"],
            "body": body_path.name,
            "arms": arms,
            "clips": [a.name for a in actions],
            "files": {
                p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files
            },
        }
        receipt.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print("CHARACTER_EXPORTED", id_, flush=True)


if __name__ == "__main__":
    main()
