"""Diagnostic native-coordinate LPV sampler; no gameplay or ambient fallback."""

import math
import struct


def vector(value, name):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError("Expected three components: " + name)
    result = [float(v) for v in value]
    if not all(math.isfinite(v) for v in result):
        raise ValueError("Nonfinite vector: " + name)
    return result


def probe_record(entity):
    """Retain all native keyvalues; derived fields never replace original inputs."""
    lower = {k.lower(): v for k, v in entity.items()}
    origin = vector(lower.get("origin"), "origin")
    minimum = vector(lower.get("box_mins"), "box_mins")
    maximum = vector(lower.get("box_maxs"), "box_maxs")
    size = [b - a for a, b in zip(minimum, maximum)]
    if min(size) <= 0:
        raise ValueError("Invalid probe bounds")
    atlas_size = [int(lower["light_probe_size_" + axis]) for axis in "xyz"]
    atlas_offset = [int(lower["light_probe_atlas_" + axis]) for axis in "xyz"]
    if min(atlas_size) <= 0 or min(atlas_offset) < 0:
        raise ValueError("Invalid atlas region")
    angles = vector(lower.get("angles", [0, 0, 0]), "angles")
    scales = vector(lower.get("scales", [1, 1, 1]), "scales")
    edge = vector(lower.get("edge_fade_dists"), "edge_fade_dists")
    supported = (
        angles[0] == 0
        and angles[2] == 0
        and scales == [1, 1, 1]
        and not lower.get("parentname")
        and not lower.get("uselocaloffset", False)
        and min(edge) >= 0
    )
    return {
        "native": entity,
        "origin": origin,
        "yaw_degrees": angles[1],
        "bounds_min": minimum,
        "bounds_size": size,
        "edge_fade": edge,
        "atlas_size": atlas_size,
        "atlas_offset": atlas_offset,
        "priority": int(lower.get("indoor_outdoor_level", 0)),
        "enabled": not lower.get("startdisabled", False),
        "sample_supported": supported,
        "texture": lower["lightprobetexture"],
        "shadow_texture": lower.get("lightprobetexture_dlshd"),
    }


class FloatVolume:
    """Unmodified HDR floats with GPU normalized-coordinate trilinear sampling."""

    def __init__(self, data, dimensions):
        self.dimensions = tuple(dimensions)
        if len(dimensions) != 3 or any(
            type(n) is not int or n <= 0 for n in dimensions
        ):
            raise ValueError("Invalid volume dimensions")
        if len(data) != math.prod(dimensions) * 16:
            raise ValueError("Float volume length does not match dimensions")
        self.data = data

    def sample(self, uvw):
        if len(uvw) != 3 or not all(math.isfinite(v) for v in uvw):
            raise ValueError("Invalid volume coordinate")
        axes = []
        for coordinate, count in zip(uvw, self.dimensions):
            position = min(max(coordinate * count - 0.5, 0), count - 1)
            low = int(math.floor(position))
            axes.append((low, min(low + 1, count - 1), position - low))
        rgb = [0.0, 0.0, 0.0]
        width, height, _ = self.dimensions
        for z in range(2):
            for y in range(2):
                for x in range(2):
                    ids = [x, y, z]
                    coords = [axis[i] for axis, i in zip(axes, ids)]
                    weight = math.prod(
                        axis[2] if i else 1 - axis[2] for axis, i in zip(axes, ids)
                    )
                    pixel = struct.unpack_from(
                        "<4f",
                        self.data,
                        ((coords[2] * height + coords[1]) * width + coords[0]) * 16,
                    )
                    if not all(math.isfinite(v) for v in pixel):
                        raise ValueError("Nonfinite HDR voxel")
                    for channel in range(3):
                        rgb[channel] += pixel[channel] * weight
        return rgb


def sample_probe(probe, volume, position, direction):
    if not probe["sample_supported"]:
        raise ValueError("Probe transform/edge rule requires further implementation")
    if (
        len(position) != 3
        or len(direction) != 3
        or not all(math.isfinite(v) for v in [*position, *direction])
    ):
        raise ValueError("Invalid position/direction")
    length = math.sqrt(sum(v * v for v in direction))
    if length <= 0:
        raise ValueError("Zero direction")
    normal = [v / length for v in direction]
    delta = [p - o for p, o in zip(position, probe["origin"])]
    yaw = math.radians(probe["yaw_degrees"])
    cosine, sine = math.cos(yaw), math.sin(yaw)
    delta = [
        cosine * delta[0] + sine * delta[1],
        -sine * delta[0] + cosine * delta[1],
        delta[2],
    ]
    local = [
        (p - b) / s for p, b, s in zip(delta, probe["bounds_min"], probe["bounds_size"])
    ]
    edge = min(
        min(c, 1 - c) * s / max(f, 0.02)
        for c, s, f in zip(local, probe["bounds_size"], probe["edge_fade"])
    )
    edge = min(max(edge, 0), 1)
    weight = edge * edge * (3 - 2 * edge)
    if weight == 0:
        return [0.0, 0.0, 0.0], 0.0
    dimensions = [volume.dimensions[0], volume.dimensions[1], volume.dimensions[2] / 6]
    if dimensions[2] != int(dimensions[2]):
        raise ValueError("Expected six directional slabs")
    if any(
        offset + size > total
        for offset, size, total in zip(
            probe["atlas_offset"], probe["atlas_size"], dimensions
        )
    ):
        raise ValueError("Probe atlas bounds exceed texture")
    # Same global half-texel clamp as VRF's atlas branch, before atlas mapping.
    clamped = [min(max(c, 0.5 / n), (n - 0.5) / n) for c, n in zip(local, dimensions)]
    uvw = [
        (c * size + offset) / n
        for c, size, offset, n in zip(
            clamped, probe["atlas_size"], probe["atlas_offset"], dimensions
        )
    ]
    result = [0.0, 0.0, 0.0]
    for axis in range(3):
        face = axis + (3 if normal[axis] <= 0 else 0)
        color = volume.sample([uvw[0], uvw[1], (uvw[2] + face) / 6])
        for channel in range(3):
            result[channel] += color[channel] * normal[axis] ** 2
    return result, weight


def sample_blended(probes, volumes, position, direction):
    """Return covered irradiance and coverage; missing SH1 fallback stays explicit."""
    result, coverage, count = [0.0, 0.0, 0.0], 0.0, 0
    for probe in sorted(probes, key=lambda p: -p["priority"]):
        if not probe["enabled"]:
            continue
        color, weight = sample_probe(
            probe, volumes[probe["texture"]], position, direction
        )
        weight *= 1 - coverage
        if weight <= 0:
            continue
        for channel in range(3):
            result[channel] += color[channel] * weight
        coverage += weight
        count += 1
        if coverage > 0.99 or count == 4:
            break
    return {
        "rgb": result,
        "coverage": coverage,
        "probe_count": count,
        "fallback_missing": coverage < 0.99,
    }
