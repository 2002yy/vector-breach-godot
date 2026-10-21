"""Native BC6H cube-array layout and box projection; no invented mip levels."""

import hashlib
import math

from source_probe_volume import probe_record


def validate_blocks(data, payload):
    if (
        data.get("schema"),
        data.get("contract"),
        data.get("format"),
        data.get("layout"),
    ) != (
        1,
        "source-reflection-blocks-v1",
        "BC6H-UFLOAT",
        "mip-ascending/cube/face/BC6H-blocks",
    ):
        raise ValueError("Unsupported reflection block contract")
    width, cubes, count = (data.get(k) for k in ("width", "cubes", "mip_count"))
    if any(type(v) is not int or v <= 0 for v in (width, cubes, count)):
        raise ValueError("Invalid reflection dimensions")
    if width > 4096 or cubes > 128 or width & (width - 1) or count > width.bit_length():
        raise ValueError("Unsupported reflection dimensions")
    if data.get("face_order") != ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]:
        raise ValueError("Unknown cube face order")
    if not isinstance(data.get("mips"), list) or len(data["mips"]) != count:
        raise ValueError("Incomplete native mip chain")
    offset = 0
    for level, mip in enumerate(data["mips"]):
        if not isinstance(mip, dict):
            raise TypeError("Invalid reflection mip metadata")
        size = max(1, width >> level)
        face_bytes = max(1, (size + 3) // 4) ** 2 * 16
        length = face_bytes * cubes * 6
        if any(
            type(mip.get(k)) is not int or mip.get(k) != v
            for k, v in {
                "level": level,
                "size": size,
                "offset": offset,
                "face_bytes": face_bytes,
                "bytes": length,
            }.items()
        ):
            raise ValueError("Reflection mip offsets/strides differ")
        if hashlib.sha256(payload[offset : offset + length]).hexdigest() != mip.get(
            "sha256"
        ):
            raise ValueError("Reflection mip hash differs")
        offset += length
    if offset != len(payload):
        raise ValueError("Trailing or truncated reflection data")


def cube_direction(face, u, v):
    """Vulkan cube face coordinates at pixel centres; Source axes retained."""
    s, t = 2 * u - 1, 2 * v - 1
    if type(face) is not int or not 0 <= face < 6:
        raise ValueError("Invalid cube face")
    return [(1, -t, -s), (-1, -t, s), (s, 1, t), (s, -1, -t), (s, -t, 1), (-s, -t, -1)][
        face
    ]


def reflection_record(entity, cubes):
    result = probe_record(entity)
    index = entity.get("array_index")
    if type(index) is not int or not 0 <= index < cubes:
        raise ValueError("Cubemap index outside native array")
    result["cube_index"] = index
    result["reflection_texture"] = entity["cubemaptexture"]
    return result


def box_direction(record, position, direction):
    """Native local-origin box projection; unsupported placement fails closed."""
    if not record["enabled"] or not record["sample_supported"]:
        return None
    if (
        len(position) != 3
        or len(direction) != 3
        or not all(math.isfinite(v) for v in (*position, *direction))
    ):
        raise ValueError("Invalid reflection ray")
    angle = math.radians(record["yaw_degrees"])
    c, s = math.cos(angle), math.sin(angle)
    relative = [p - o for p, o in zip(position, record["origin"])]
    local = [
        c * relative[0] + s * relative[1],
        -s * relative[0] + c * relative[1],
        relative[2],
    ]
    ray = [
        c * direction[0] + s * direction[1],
        -s * direction[0] + c * direction[1],
        direction[2],
    ]
    minimum = record["bounds_min"]
    maximum = [a + b for a, b in zip(minimum, record["bounds_size"])]
    if any(
        p < lo - 0.02 or p > hi + 0.02 for p, lo, hi in zip(local, minimum, maximum)
    ):
        return None
    distances = [
        max((lo - p) / d, (hi - p) / d)
        for p, d, lo, hi in zip(local, ray, minimum, maximum)
        if abs(d) > 1e-12
    ]
    if not distances:
        raise ValueError("Zero reflection ray")
    distance = abs(min(distances))
    projected = [p + d * distance for p, d in zip(local, ray)]
    length = math.sqrt(sum(v * v for v in projected))
    if length <= 1e-12:
        return None
    return [v / length for v in projected]
