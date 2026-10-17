"""Adapt CRC-verified local Source 2 exports; never bundles third-party content.

Run in Blender. Original exports and existing game assets are never overwritten.
Body and dedicated first-person groups are deliberately separated. Native game
rules remain authoritative; this tool only prepares presentation resources.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import convert_local_cs_characters as shared

SOURCES = {
    "ct-st6": "ctm_st6_variante",
    "ct-sas-officer": "ctm_sas_variantf",
    "ct-fbi": "ctm_fbi_varianta",
    "t-phoenix": "tm_phoenix",
    "t-elite": "tm_leet_variantf",
    "t-blackwolf": "tm_balkan_variantj",
}


def transform_geometry(obj, matrix):
    # Mesh.transform defaults to leaving shape keys in the previous coordinate
    # frame. Native T bodies have morph targets: their Basis would then ignore
    # the body turn/scale while the skeleton and gloves use the new frame.
    keys = obj.data.shape_keys
    expected = [matrix @ p.co for p in keys.reference_key.data] if keys else []
    obj.data.transform(matrix, shape_keys=True)
    if keys:
        error = max(
            (p.co - target).length
            for p, target in zip(keys.reference_key.data, expected)
        )
        if error > 0.00001:
            raise ValueError("Morph Basis and skeletal coordinate frames diverged")


def imported(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.animation_data_clear()
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    # Blender's bone custom-shape Icosphere is an inspection helper, not an asset.
    meshes = [
        o
        for o in bpy.data.objects
        if o.type == "MESH"
        and any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers)
    ]
    for obj in meshes:
        transform_geometry(obj, obj.matrix_world)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    arm.data.transform(arm.matrix_world)
    arm.parent = None
    arm.matrix_world = Matrix.Identity(4)
    return arm, meshes


def body(id_, source, output, motions):
    arm, meshes = imported(source)
    third = [
        o for o in meshes if ".thirdperson_" in o.name or o.name.endswith(".defusekit")
    ]
    first = [o for o in meshes if ".firstperson_" in o.name]
    if not third or not first:
        raise ValueError(
            "Expected distinct original body and dedicated first-person groups"
        )
    points = [v.co for o in third for v in o.data.vertices]
    low, high = min(v.z for v in points), max(v.z for v in points)
    transform = (
        shared.TURN
        @ Matrix.Scale(1.8 / (high - low), 4)
        @ Matrix.Translation((0, 0, -low))
    )
    for obj in meshes:
        transform_geometry(obj, transform)
    arm.data.transform(transform)
    actions = shared.retarget(arm, motions)
    target = output / (id_ + ".glb")
    shared.export(target, [arm] + third, True)
    arms = {
        side: shared.arm_asset(
            arm, first, side, output / (id_ + "-arm-" + side + ".glb")
        )
        for side in ("L", "R")
    }
    paths = [target] + [output / (id_ + "-arm-" + side + ".glb") for side in ("L", "R")]
    return {
        "name": shared.PROFILES[id_][0],
        "team": shared.PROFILES[id_][1],
        "source": str(source),
        "source_sha256": digest(source),
        "provenance": "Valve official Steam depot; native firstperson groups",
        "body": target.name,
        "arms": arms,
        "clips": [a.name for a in actions],
        "animation_adaptation": "existing shared combat motions retargeted; native topology/UV/skin preserved",
        "files": {p.name: digest(p) for p in paths},
    }


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--motions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only", choices=SOURCES, nargs="+")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    if args.output.resolve().parts[-3:] != ("assets", "local_reference", "cs_official"):
        raise ValueError("Output must end in assets/local_reference/cs_official")
    args.output.mkdir(parents=True, exist_ok=True)
    manifest_path = args.output / "manifest.json"
    manifest = (
        json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest_path.exists()
        else {"version": 1, "profiles": {}}
    )
    motions = shared.Motions(args.motions)
    for id_, name in SOURCES.items():
        if args.only and id_ not in args.only:
            continue
        for suffix in (".glb", "-arm-L.glb", "-arm-R.glb"):
            if (args.output / (id_ + suffix)).exists():
                raise FileExistsError(
                    "Preserve existing converted resources; choose a fresh output or archive explicitly"
                )
        manifest["profiles"][id_] = body(
            id_, args.source / (name + ".gltf"), args.output, motions
        )
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print("OFFICIAL_CHARACTER_EXPORTED", id_, flush=True)


if __name__ == "__main__":
    main()
