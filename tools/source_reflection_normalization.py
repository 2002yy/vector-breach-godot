"""Native radiance L2 -> luminance L1 and BRDF-array CPU reference."""

import math
import struct


def normalization_sh(coefficients):
    if len(coefficients) != 27 or not all(math.isfinite(v) for v in coefficients):
        raise ValueError("Expected 27 finite planar RGB radiance coefficients")
    luma = [
        sum(
            coefficients[c * 9 + band] * weight
            for c, weight in enumerate([0.2125, 0.7154, 0.0721])
        )
        for band in range(4)
    ]
    return [
        luma[3] * 0.325735,
        luma[1] * 0.325735,
        luma[2] * 0.325735,
        luma[0] * 0.282095,
    ]


def normalization(roughness, normal, irradiance, sh):
    baked = sum(a * b for a, b in zip([*normal, 1], sh))
    if baked <= 0:
        return 1.0
    luma = sum(a * b for a, b in zip(irradiance, [0.2125, 0.7154, 0.0721]))
    return min(luma / baked, max(roughness * 2 + 1, 1))


def brdf_lookup(raw, roughness, ndotv):
    if len(raw) != 64 * 64 * 3 * 16:
        raise ValueError("Expected original 64x64x3 RGBA float LUT")
    if not 0 <= roughness <= 1 or not 0 <= ndotv <= 1:
        raise ValueError("BRDF lookup outside physical domain")
    x, y = roughness * 63, math.sqrt(1 - ndotv) * 63
    x0, y0 = int(x), int(y)
    result = [0.0] * 4
    for ix in range(2):
        for iy in range(2):
            weight = ((x - x0) if ix else (1 - (x - x0))) * (
                (y - y0) if iy else (1 - (y - y0))
            )
            pixel = struct.unpack_from(
                "<4f", raw, ((64 + min(y0 + iy, 63)) * 64 + min(x0 + ix, 63)) * 16
            )
            result = [a + b * weight for a, b in zip(result, pixel)]
    return result


def env_brdf(lut, f0):
    single = [lut[0] * (1 - f) + lut[1] * f for f in f0]
    missing = 1 - lut[1]
    average = [f + (1 - f) / 21 for f in f0]
    multi = [s * a / (1 - a * missing) * missing for s, a in zip(single, average)]
    return single, multi


def hair_secondary_ray(normal, view, tangent, bitangent, rough_xy, shift, scale):
    def unit(value, fallback):
        length = math.sqrt(sum(v * v for v in value))
        return [v / length for v in value] if length > 1e-6 else fallback

    def cross(a, b):
        return [
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        ]

    wider_x = rough_xy[0] >= rough_xy[1]
    shift_axis, warp_axis = (tangent, bitangent) if wider_x else (bitangent, tangent)
    warp = (1 - min(rough_xy[0] / rough_xy[1], rough_xy[1] / rough_xy[0])) * 0.5
    warped = unit(cross(cross(view, warp_axis), warp_axis), normal)
    shifted = unit([n - a * shift for n, a in zip(normal, shift_axis)], normal)
    secondary = unit(
        [n * (1 - warp) + w * warp for n, w in zip(shifted, warped)], shifted
    )
    roughness = min(sum(rough_xy) * 0.5 * scale, 1)
    square = roughness * roughness
    smoothness = 1 - square
    dominant = smoothness * (math.sqrt(smoothness) + square)
    reflected = [
        -v + 2 * sum(a * b for a, b in zip(view, secondary)) * n
        for v, n in zip(view, secondary)
    ]
    return unit(
        [n * (1 - dominant) + r * dominant for n, r in zip(secondary, reflected)],
        secondary,
    )
