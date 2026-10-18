"""Select unchanged large opaque source triangles for conservative occlusion.

Requires numpy. Never fills holes, uses collision geometry, changes render meshes,
or includes alpha-tested/blended surfaces. The binary is consumed by
tools/authoring/save_classic_occluder.gd. Source coordinates remain private.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path
from urllib.parse import unquote

import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-area", type=float, default=0.25)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    scene = json.loads(args.source.read_text(encoding="utf-8"))
    buffers = []
    for item in scene["buffers"]:
        path = (args.source.parent / unquote(item["uri"])).resolve()
        if not path.is_relative_to(args.source.parent.resolve()):
            raise ValueError("Buffer outside source directory")
        buffers.append(np.memmap(path, mode="r", dtype=np.uint8))

    def accessor(index):
        item = scene["accessors"][index]
        if "sparse" in item:
            raise ValueError("Sparse accessors require explicit support")
        view = scene["bufferViews"][item["bufferView"]]
        dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[
            item["componentType"]
        ]
        components = {"SCALAR": 1, "VEC3": 3}[item["type"]]
        width = np.dtype(dtype).itemsize
        return np.ndarray(
            (item["count"], components),
            dtype=dtype,
            buffer=buffers[view["buffer"]],
            offset=view.get("byteOffset", 0) + item.get("byteOffset", 0),
            strides=(view.get("byteStride", width * components), width),
        )

    triangles = []
    opaque_count = 0

    def visit(index, parent):
        nonlocal opaque_count
        node = scene["nodes"][index]
        if any(
            word in node.get("name", "").lower()
            for word in ["cb_bl_mesh_blocklight", "light_environment"]
        ):
            return
        if "matrix" in node:
            local = np.array(node["matrix"]).reshape(4, 4).T
        else:
            x, y, z, w = node.get("rotation", [0, 0, 0, 1])
            local = np.eye(4)
            local[:3, :3] = np.array(
                [
                    [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
                ]
            ) @ np.diag(node.get("scale", [1, 1, 1]))
            local[:3, 3] = node.get("translation", [0, 0, 0])
        world = parent @ local
        if "mesh" in node:
            for primitive in scene["meshes"][node["mesh"]]["primitives"]:
                if primitive.get("mode", 4) != 4:
                    continue
                material = scene["materials"][primitive["material"]]
                if material.get("alphaMode", "OPAQUE") != "OPAQUE":
                    continue
                # Shader-unaware exports label translucent dust/steam as opaque.
                # They are effects, never structural occluders, even before the
                # optional runtime shader adaptation is installed.
                if (
                    material.get("extras", {}).get("vmat", {}).get("ShaderName")
                    == "csgo_effects.vfx"
                ):
                    continue
                positions = accessor(primitive["attributes"]["POSITION"])
                indices = accessor(primitive["indices"]).reshape(-1, 3)
                points = positions[indices] @ world[:3, :3].T + world[:3, 3]
                areas = (
                    np.linalg.norm(
                        np.cross(
                            points[:, 1] - points[:, 0], points[:, 2] - points[:, 0]
                        ),
                        axis=1,
                    )
                    / 2
                )
                selected = points[areas >= args.min_area]
                opaque_count += len(points)
                if len(selected):
                    triangles.append(selected.astype("<f4"))
        for child in node.get("children", []):
            visit(child, world)

    for index in scene["scenes"][scene.get("scene", 0)]["nodes"]:
        visit(index, np.eye(4))
    vertices = np.concatenate(triangles).reshape(-1, 3)
    if not np.isfinite(vertices).all():
        raise ValueError("Nonfinite occluder")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("xb") as stream:
        stream.write(struct.pack("<I", len(vertices)))
        stream.write(vertices.tobytes())
    receipt = {
        "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
        "opaque_source_triangles": opaque_count,
        "occluder_triangles": len(vertices) // 3,
        "min_triangle_area_m2": args.min_area,
        "method": "unchanged opaque render triangles only; no hole filling or collision geometry",
    }
    args.output.with_suffix(".json").write_text(
        json.dumps(receipt, indent=2), encoding="utf-8"
    )
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
