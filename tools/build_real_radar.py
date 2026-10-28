"""Derive local-only height-sliced radar atlases from unchanged collision GLB."""

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def multiply(a, b):
    return [
        sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
        for c in range(4)
        for r in range(4)
    ]


def node_matrix(node):
    if "matrix" in node:
        return node["matrix"]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    tx, ty, tz = node.get("translation", [0, 0, 0])
    return [
        (1 - 2 * (y * y + z * z)) * sx,
        2 * (x * y + z * w) * sx,
        2 * (x * z - y * w) * sx,
        0,
        2 * (x * y - z * w) * sy,
        (1 - 2 * (x * x + z * z)) * sy,
        2 * (y * z + x * w) * sy,
        0,
        2 * (x * z + y * w) * sz,
        2 * (y * z - x * w) * sz,
        (1 - 2 * (x * x + y * y)) * sz,
        0,
        tx,
        ty,
        tz,
        1,
    ]


def transform(matrix, vertex):
    return tuple(
        sum(matrix[c * 4 + r] * vertex[c] for c in range(3)) + matrix[12 + r]
        for r in range(3)
    )


def world_to_uv(point, bounds):
    return ((point[0] - bounds[0]) / bounds[2], (point[1] - bounds[1]) / bounds[3])


def read_triangles(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError("invalid GLB header")
    offset, model, blob = 12, None, None
    while offset < length:
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + size]
        offset += size
        if kind == 0x4E4F534A:
            model = json.loads(chunk)
        elif kind == 0x004E4942:
            blob = chunk
    if model is None or blob is None:
        raise ValueError("GLB JSON/BIN missing")

    def accessor(index):
        item = model["accessors"][index]
        if "sparse" in item or item.get("normalized", False):
            raise ValueError("unsupported sparse/normalized collision accessor")
        view = model["bufferViews"][item["bufferView"]]
        if view.get("buffer", 0) != 0:
            raise ValueError("external collision buffer")
        code = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[item["componentType"]]
        count = {"SCALAR": 1, "VEC3": 3}[item["type"]]
        record = struct.Struct("<" + code * count)
        begin = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        stride = view.get("byteStride", record.size)
        return [
            record.unpack_from(blob, begin + i * stride) for i in range(item["count"])
        ]

    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    triangles = []

    def visit(index, parent):
        node = model["nodes"][index]
        matrix = multiply(parent, node_matrix(node))
        if "mesh" in node:
            for primitive in model["meshes"][node["mesh"]]["primitives"]:
                if primitive.get("mode", 4) != 4:
                    raise ValueError("collision primitive is not triangles")
                positions = [
                    transform(matrix, v)
                    for v in accessor(primitive["attributes"]["POSITION"])
                ]
                indices = (
                    [v[0] for v in accessor(primitive["indices"])]
                    if "indices" in primitive
                    else range(len(positions))
                )
                for i in range(0, len(indices), 3):
                    triangles.append(tuple(positions[indices[i + j]] for j in range(3)))
        for child in node.get("children", []):
            visit(child, matrix)

    scene = model["scenes"][model.get("scene", 0)]
    for index in scene["nodes"]:
        visit(index, identity)
    return triangles


def normal(triangle):
    a, b, c = triangle
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    n = (
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    )
    length = math.sqrt(sum(c * c for c in n))
    return n, length


def slice_segment(triangle, height):
    points = []
    for i in range(3):
        a, b = triangle[i], triangle[(i + 1) % 3]
        if (a[1] <= height < b[1]) or (b[1] <= height < a[1]):
            t = (height - a[1]) / (b[1] - a[1])
            points.append((a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2])))
    return points if len(points) == 2 else []


def build(project, level_name, output, resolution=1536):
    # Pillow is authoring-only; runtime and pure contract tests need no dependency.
    from PIL import Image, ImageDraw, ImageFilter

    level_path = project / "data/levels" / (level_name + ".json")
    level = json.loads(level_path.read_text(encoding="utf-8-sig"))
    source = level["runtime_collision_scene"]
    source_path = project / source.removeprefix("res://")
    triangles = read_triangles(source_path)
    floors = []
    bins = {}
    anchors = [
        (team, tuple(point)) for team, point in level.get("spawnHints", {}).items()
    ]
    if not anchors:
        anchors = [
            (
                str(point.get("route", index)),
                (float(point["x"]), float(point["y"]), float(point["z"])),
            )
            for index, point in enumerate(level.get("spawnPoints", []))
        ]
    if not anchors:
        anchors = [
            (
                "start",
                (
                    float(level["start"][0]),
                    float(level["startHeight"]),
                    float(level["start"][1]),
                ),
            )
        ]
    spawn_heights = [float(point[1]) - 0.9 for _, point in anchors]
    low, high = min(spawn_heights) - 6, max(spawn_heights) + 6
    for triangle in triangles:
        n, length = normal(triangle)
        y = sum(p[1] for p in triangle) / 3
        if length > 0 and n[1] / length >= 0.55 and low <= y <= high:
            floors.append((triangle, y))
            key = round(y / 0.5) * 0.5
            bins[key] = bins.get(key, 0) + abs(n[1]) * 0.5
    if not floors:
        raise ValueError("no upward collision surfaces in playable height range")
    centers = []
    for height in sorted(bins, key=lambda key: (-bins[key], key)):
        if bins[height] >= 5 and all(abs(height - c) >= 1.5 for c in centers):
            centers.append(height)
        if len(centers) >= 12:
            break
    for height in spawn_heights:
        if all(abs(height - c) > 1.25 for c in centers):
            centers.append(height)
    centers.sort()
    points = [p for tri, _ in floors for p in tri]
    xmin, xmax = min(p[0] for p in points) - 2, max(p[0] for p in points) + 2
    zmin, zmax = min(p[2] for p in points) - 2, max(p[2] for p in points) + 2
    bounds = [xmin, zmin, xmax - xmin, zmax - zmin]
    output.mkdir(parents=True, exist_ok=True)
    if (output / "atlas.json").exists():
        raise ValueError("atlas exists; use a new output version")
    layers = []

    def pixel(point):
        u, v = world_to_uv(point, bounds)
        return u * (resolution - 1), v * (resolution - 1)

    context_image = Image.new("RGBA", (resolution, resolution))
    context_draw = ImageDraw.Draw(context_image)
    for triangle, _ in floors:
        context_draw.polygon(
            [pixel((p[0], p[2])) for p in triangle], fill=(40, 48, 45, 255)
        )
    for index, center in enumerate(centers):
        image = context_image.copy()
        draw = ImageDraw.Draw(image)
        active_mask = Image.new("L", image.size)
        active_draw = ImageDraw.Draw(active_mask)
        count = 0
        for triangle, y in sorted(floors, key=lambda item: item[1]):
            if abs(y - center) > 1.4:
                continue
            value = int(115 + 45 * max(0, 1 - abs(y - center) / 1.4))
            draw.polygon(
                [pixel((p[0], p[2])) for p in triangle],
                fill=(value, value + 8, value + 5, 255),
            )
            active_draw.polygon([pixel((p[0], p[2])) for p in triangle], fill=255)
            count += 1
        edge = active_mask.filter(ImageFilter.FIND_EDGES)
        outline = Image.new("RGBA", image.size, (215, 220, 208, 255))
        image.paste(outline, (0, 0), edge)
        draw = ImageDraw.Draw(image)
        walls = 0
        for triangle in triangles:
            segment = slice_segment(triangle, center + 0.85)
            if segment:
                draw.line(
                    [pixel(p) for p in segment], fill=(225, 226, 211, 255), width=2
                )
                walls += 1
        filename = f"layer-{index:02d}.png"
        image.save(output / filename)
        layers.append(
            dict(
                height=center,
                texture=filename,
                sha256=sha(output / filename),
                floor_triangles=count,
                wall_segments=walls,
            )
        )
    calibration = []
    for team, point in anchors:
        calibration.append(
            dict(
                label=team,
                world_xz=[point[0], point[2]],
                uv=world_to_uv((point[0], point[2]), bounds),
            )
        )
    manifest = dict(
        schema=1,
        level=level_name,
        source=source,
        source_sha256=sha(source_path),
        source_import_sha256=sha(Path(str(source_path) + ".import")),
        level_sha256=sha(level_path),
        generator_sha256=sha(Path(__file__)),
        world_rect=bounds,
        resolution=resolution,
        meters_per_pixel=[bounds[2] / (resolution - 1), bounds[3] / (resolution - 1)],
        layers=layers,
        calibration=calibration,
        representation="height_slice_with_dim_full_collision_ground_context",
        context_floor_triangles=len(floors),
        original_overview_art=False,
    )
    (output / "atlas.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "REAL_RADAR_BUILT",
        level_name,
        "triangles",
        len(triangles),
        "floors",
        len(floors),
        "layers",
        len(layers),
        flush=True,
    )
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("level")
    parser.add_argument("output", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--resolution", type=int, default=1536)
    args = parser.parse_args()
    if not 128 <= args.resolution <= 4096:
        parser.error("resolution must be 128..4096")
    build(args.project, args.level, args.output, args.resolution)
