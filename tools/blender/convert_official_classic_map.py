"""Adapt a verified Source 2 Viewer 20.1 glTF without replacing original materials.

Alignment metadata is private. Visual and player-collision outputs stay separate.
Blender -b --python this.py -- --source scene.gltf --metadata native.json
--kind visual --output assets/local_reference/.../official/map.gltf
"""

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--kind", choices=["visual", "collision"], required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    if args.output.exists():
        raise FileExistsError("Keep existing validated output; choose a fresh path")
    units = json.loads(args.metadata.read_text(encoding="utf-8"))["units"]
    offset = Vector(units["sourceToWebOffset"]) * (
        0.0254 / float(units["sourceToWebScale"])
    )
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    excluded = []
    if args.kind == "collision":
        for obj in list(bpy.context.scene.objects):
            # Dedicated grenade-only clips and sky boundaries are not player solids.
            # Preserve source player/NPC clips, pass-bullet surfaces and ladders.
            if obj.name.startswith(("physics_csgo_grenadeclip", "physics_sky")):
                excluded.append(obj.name)
                bpy.data.objects.remove(obj, do_unlink=True)
    roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
    alignment = bpy.data.objects.new("OfficialSourceAlignment", None)
    bpy.context.collection.objects.link(alignment)
    for obj in roots:
        obj.parent = alignment
    # VRF 20.1 converts Source inches to glTF metres and maps axes to (y,z,x).
    # The installed research maps use (x,z,-y)+offset. In Blender Z-up this is
    # a quarter turn around Z, followed by the independently recorded offset.
    alignment.rotation_euler.z = math.pi / 2
    alignment.location = (offset.x, -offset.z, offset.y)
    bpy.context.view_layer.update()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise ValueError("Empty mesh export (check the _physics sidecar for physics)")
    if args.kind == "collision":
        for obj in meshes:
            obj.name = "COLLISION_ONLY_" + obj.name
    textures = [image for image in bpy.data.images if image.source == "FILE"]
    if args.kind == "visual" and not textures:
        raise ValueError("Original visual export must contain textures")
    corners = [
        obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box
    ]
    bounds = [
        [min(v[i] for v in corners) for i in range(3)],
        [max(v[i] for v in corners) for i in range(3)],
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output),
        export_format="GLB" if args.output.suffix == ".glb" else "GLTF_SEPARATE",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_draco_mesh_compression_enable=False,
    )
    receipt = {
        "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
        "alignment_metadata_sha256": hashlib.sha256(
            args.metadata.read_bytes()
        ).hexdigest(),
        "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "kind": args.kind,
        "source_exporter": "Source2Viewer-CLI 20.1",
        "scale_applied": 1,
        "decimation": False,
        "meshes": len(meshes),
        "triangles": sum(
            len(poly.vertices) - 2 for obj in meshes for poly in obj.data.polygons
        ),
        "textures": len(textures),
        "blender_bounds": bounds,
        "excluded_non_player_physics": excluded,
    }
    args.output.with_suffix(".receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    print("OFFICIAL_MAP_CONVERTED=" + json.dumps(receipt), flush=True)


if __name__ == "__main__":
    main()
