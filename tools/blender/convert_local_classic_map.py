"""Decode an acquired native map; retain every triangle and source material slot.

Blender --background --python this.py -- --source map-native.glb --output map.glb
--source-scale 0.02. Source assets remain outside Git; no decimation or ground fill.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-scale", type=float, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    factor = 0.0254 / args.source_scale
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        obj.name = "COLLISION_" + obj.name
    # Scale the entire imported hierarchy, including translations, exactly once.
    for obj in list(bpy.context.scene.objects):
        if obj.parent is None:
            obj.location *= factor
            obj.scale *= factor
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output),
        export_format="GLB",
        export_yup=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_draco_mesh_compression_enable=False,
    )
    receipt = {
        "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
        "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "meters_per_source_unit": 0.0254,
        "scale": factor,
        "triangles": sum(len(obj.data.polygons) for obj in meshes),
        "decimation": False,
        "original_textures": False,
    }
    args.output.with_suffix(".receipt.json").write_text(
        json.dumps(receipt, indent=2), encoding="utf-8"
    )
    print("CLASSIC_MAP_CONVERTED=" + json.dumps(receipt), flush=True)


if __name__ == "__main__":
    main()
