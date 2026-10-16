"""Convert a pinned Awpy AWMH collision mesh using the visual export's transform.

This is approximate, source-derived collision (Awpy's grid simplification).
Keep its receipt and audit contact/navigation before enabling a local map.
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--physics", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    raw = args.physics.read_bytes()
    magic, version, vertices, triangles = struct.unpack_from("<4sIII", raw)
    if magic != b"AWMH" or version != 1:
        raise ValueError("Unsupported collision mesh")
    if len(raw) != 16 + vertices * 12 + triangles * 12:
        raise ValueError("Invalid collision mesh length")
    units = json.loads(args.metadata.read_text(encoding="utf-8"))["units"]
    factor = 0.0254 / units["sourceToWebScale"]
    offset = np.array(units["sourceToWebOffset"]) * factor
    source = np.frombuffer(raw, dtype="<f4", count=vertices * 3, offset=16).reshape(
        -1, 3
    )
    # Blender Z-up. GLB export converts to Godot X/Y/-Z source axes.
    points = source * 0.0254 + np.array([offset[0], -offset[2], offset[1]])
    faces = np.frombuffer(
        raw, dtype="<u4", count=triangles * 3, offset=16 + vertices * 12
    ).reshape(-1, 3)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new("AuthoredSourcePhysics")
    mesh.from_pydata(points.tolist(), [], faces.tolist())
    obj = bpy.data.objects.new("COLLISION_ONLY_SourcePhysics", mesh)
    bpy.context.collection.objects.link(obj)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output), export_format="GLB", export_normals=False
    )
    receipt = {
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "metadata_sha256": hashlib.sha256(args.metadata.read_bytes()).hexdigest(),
        "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "triangles": triangles,
        "approximate": True,
        "source": "https://github.com/pnxenopoulos/awpy-data/releases/tag/2000933",
    }
    args.output.with_suffix(".receipt.json").write_text(
        json.dumps(receipt, indent=2), encoding="utf-8"
    )
    print("CLASSIC_COLLISION_CONVERTED=" + json.dumps(receipt), flush=True)


if __name__ == "__main__":
    main()
