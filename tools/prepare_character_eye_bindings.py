"""Calibrate native eye radius against preserved export and converted bind bones.

This only adds a new sidecar, never modifies original models or material files.
Source2Viewer exports Source inches as metres; conversion rotates X/Z and
normalizes body height. Fit that known similarity over every matching bone.
"""

import argparse
import json
import math
import struct
from pathlib import Path

from prepare_source_decals import sha

EYE_BONES = ("eyeball_l", "eyeball_r", "eye_target")


def positions(data):
    nodes = data["nodes"]
    parents = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}

    def transform(point, node):
        if "matrix" in node:
            m = node["matrix"]
            return [
                sum(m[c * 4 + r] * point[c] for c in range(3)) + m[12 + r]
                for r in range(3)
            ]
        p = [a * b for a, b in zip(point, node.get("scale", [1, 1, 1]))]
        q = node.get("rotation", [0, 0, 0, 1])

        def cross(a, b):
            return [
                a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0],
            ]

        t = [2 * v for v in cross(q[:3], p)]
        u = cross(q[:3], t)
        return [
            p[i] + q[3] * t[i] + u[i] + node.get("translation", [0, 0, 0])[i]
            for i in range(3)
        ]

    result = {}
    joints = {j for skin in data.get("skins", []) for j in skin["joints"]}
    for index in joints:
        p, cursor, seen = [0, 0, 0], index, set()
        while cursor is not None:
            if cursor in seen:
                raise ValueError("Cyclic skeleton")
            seen.add(cursor)
            p = transform(p, nodes[cursor])
            cursor = parents.get(cursor)
        result[nodes[index]["name"]] = p
    return result


def calibrate(original, converted):
    if not all(b in original and b in converted for b in EYE_BONES):
        raise ValueError("Missing native eye/target bones")
    common = sorted(original.keys() & converted.keys())
    if len(common) < 6:
        raise ValueError("Insufficient bind-pose evidence")
    x = [[-original[b][0], original[b][1], -original[b][2]] for b in common]
    y = [converted[b] for b in common]
    xm = [sum(p[i] for p in x) / len(x) for i in range(3)]
    ym = [sum(p[i] for p in y) / len(y) for i in range(3)]
    denominator = sum((p[i] - xm[i]) ** 2 for p in x for i in range(3))
    if denominator < 1e-12:
        raise ValueError("Degenerate bind pose")
    scale = (
        sum((p[i] - xm[i]) * (q[i] - ym[i]) for p, q in zip(x, y) for i in range(3))
        / denominator
    )
    offset = [ym[i] - scale * xm[i] for i in range(3)]
    error = max(
        math.dist([scale * p[i] + offset[i] for i in range(3)], q) for p, q in zip(x, y)
    )
    if not (0.1 < scale < 10) or error > 0.0001:
        raise ValueError("Converted skeleton differs from verified export frame")
    return {
        "source_unit_m": 0.0254 * scale,
        "bones_checked": len(common),
        "max_residual_m": error,
        "rest_positions": {b: converted[b] for b in EYE_BONES},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--exports", type=Path, required=True)
    args = parser.parse_args()
    output = args.asset_root / "source-character-eye-bindings.json"
    if output.exists():
        raise FileExistsError("Preserve prior calibration")
    models = {}
    for model, export in [
        ("t-elite", "tm_leet_variantf"),
        ("t-blackwolf", "tm_balkan_variantj"),
        ("t-phoenix", "tm_phoenix"),
    ]:
        source = args.exports / (export + ".gltf")
        target = args.asset_root / (model + ".glb")
        raw = target.read_bytes()
        length = struct.unpack_from("<I", raw, 12)[0]
        row = calibrate(
            positions(json.loads(source.read_text(encoding="utf-8"))),
            positions(json.loads(raw[20 : 20 + length])),
        )
        row.update(original_sha256=sha(source), visual_sha256=sha(target))
        models[target.name] = row
    output.write_text(
        json.dumps({"schema": 1, "models": models}, indent=2) + "\n", encoding="utf-8"
    )
    print("SOURCE_EYE_BINDINGS_OK", json.dumps(models))


if __name__ == "__main__":
    main()
