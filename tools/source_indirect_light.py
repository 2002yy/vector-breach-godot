"""Controlled native probe-path indirect light; viewer-derived ambient SH is labeled."""

import math


def ambient_sh(sun):
    """Pinned VRF WorldLightingInfo.StoreSunLight/UpdateAmbientLighting candidate."""

    def linear(color):
        if len(color) != 3 or any(
            not math.isfinite(v) or not 0 <= v <= 255 for v in color
        ):
            raise ValueError("Expected native RGB8 light color")
        return [
            (
                (v / 255) / 12.92
                if v / 255 <= 0.04045
                else ((v / 255 + 0.055) / 1.055) ** 2.4
            )
            for v in color
        ]

    for key in ["brightness", "brightnessscale", "skyintensity"]:
        if not math.isfinite(sun[key]) or sun[key] < 0:
            raise ValueError("Invalid original light intensity")
    if (
        sun.get("classname") != "light_environment"
        or sun.get("enabled") is not True
        or sun.get("parentname")
        or sun.get("scales") != [1, 1, 1]
    ):
        raise ValueError("Unsupported original environment light placement")
    pitch = sun["angles"][0]
    if not math.isfinite(pitch):
        raise ValueError("Invalid source pitch")
    sky = [v * sun["skyintensity"] for v in linear(sun["skycolor"])]
    bounce = linear(sun["skyambientbounce"])
    direct = [
        v * sun["brightness"] * sun["brightnessscale"] for v in linear(sun["color"])
    ]
    sun_down = -math.sin(math.radians(pitch))
    vertical = [
        s * 0.5 - s * b * 0.5 + d * b * 0.5 * sun_down
        for s, b, d in zip(sky, bounce, direct)
    ]
    constant = [
        s * 0.5 + s * b * 0.5 + d * b * 0.5 * abs(sun_down)
        for s, b, d in zip(sky, bounce, direct)
    ]
    return [[0, 0, v, c] for v, c in zip(vertical, constant)]


def cube_irradiance(cube, normal):
    return [
        sum(cube[a if normal[a] >= 0 else a + 3][c] * normal[a] ** 2 for a in range(3))
        for c in range(3)
    ]


def complete_probe(cube, coverage, sh, normal):
    # Native dynamic-probe fallback first evaluates SH at +/- axes. This is
    # C + L dot (N*abs(N)), different from the unprobed direct SH dot (N,1).
    raw = cube_irradiance(cube, normal)
    remainder = 1 - coverage if coverage < 0.99 else 0
    return [
        v + remainder * (row[3] + sum(a * b * abs(b) for a, b in zip(row[:3], normal)))
        for v, row in zip(raw, sh)
    ]


def soft_diffuse(cube, coverage, sh, mapped, geometric, softness, skin):
    result = []
    for c in range(3):
        t = softness[c] * skin
        normal = [a * (1 - t) + b * t for a, b in zip(mapped, geometric)]
        length = math.sqrt(sum(v * v for v in normal))
        if length < 1e-6:
            normal = geometric
        else:
            normal = [v / length for v in normal]
        result.append(complete_probe(cube, coverage, sh, normal)[c])
    return result


def indirect_energy(irradiance, reflection, single, multi, albedo, metallic, ao):
    energy = [s + m for s, m in zip(single, multi)]
    diffuse = [
        i * (1 - e) * a * (1 - metallic) * ao
        for i, e, a in zip(irradiance, energy, albedo)
    ]
    specular = [r * e * ao for r, e in zip(reflection, energy)]
    return diffuse, specular
