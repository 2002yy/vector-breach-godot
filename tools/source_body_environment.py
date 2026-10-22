"""Native character probe-combo cloth rules, independent CPU diagnostic oracle."""

import argparse
import itertools
import json
import math
from pathlib import Path

from source_reflection_normalization import brdf_lookup, env_brdf


def specular_color(albedo, metal, hair, cloth, tint, scale):
    dielectric = 0.04 * (1 - hair) + 0.046 * hair
    return [
        (
            dielectric * (1 - cloth)
            + min(max(t * math.sqrt(max(a, 0)) * scale, 0), 1) * cloth
        )
        * (1 - metal)
        + a * metal
        for a, t in zip(albedo, tint)
    ]


def body_brdf(lut, f0, roughness, nov, cloth):
    ggx, _ = env_brdf(lut, f0)
    inv_rough = 1 / max(roughness * roughness, 1e-5)
    charlie = (2 + inv_rough) * max((1 - nov) * 0.5, 0) ** (inv_rough * 0.5) * 0.125
    single = [s * (1 - cloth) + f * charlie * cloth for s, f in zip(ggx, f0)]
    missing = 1 - lut[1]
    average = [f + (1 - f) / 21 for f in f0]
    multi = [s * f / (1 - f * missing) * missing for s, f in zip(single, average)]
    return single, multi


def body_energy(irradiance, reflection, single, multi, albedo, metal, ao, cloth):
    diffuse = [
        i * (1 - (s + m) * (1 - cloth)) * a * (1 - metal) * ao
        for i, s, m, a in zip(irradiance, single, multi, albedo)
    ]
    specular = [
        r * (s + m * (1 - cloth)) * ao for r, s, m in zip(reflection, single, multi)
    ]
    return diffuse, specular


def primary_ray(warped, mapped, view, cloth, roughness):
    primary = [w * (1 - cloth) + n * cloth for w, n in zip(warped, mapped)]
    dot = sum(n * v for n, v in zip(primary, view))
    reflected = [2 * dot * n - v for n, v in zip(primary, view)]
    smooth = min(max(1 - roughness * roughness, 0), 1)
    weight = smooth * (math.sqrt(smooth) + roughness * roughness)
    ray = [n * (1 - weight) + r * weight for n, r in zip(primary, reflected)]
    length = math.sqrt(sum(v * v for v in ray))
    return primary, [v / length * 0.5 + 0.5 for v in ray]


def cases(raw):
    result = []
    for roughness, nov, cloth, metal, ao in itertools.product(
        [0.1, 0.5, 1], [0, 0.5, 1], [0, 0.5, 1], [0, 0.5, 1], [0, 0.35, 1]
    ):
        albedo, tint, irradiance, reflection = (
            [0.3, 0.5, 0.7],
            [0.2, 0.8, 1],
            [0.4, 0.7, 0.2],
            [0.8, 0.4, 0.6],
        )
        f0 = specular_color(albedo, metal, 0.4, cloth, tint, 1.2)
        single, multi = body_brdf(
            brdf_lookup(raw, roughness, nov), f0, roughness, nov, cloth
        )
        diffuse, specular = body_energy(
            irradiance, reflection, single, multi, albedo, metal, ao, cloth
        )
        view = [math.sqrt(1 - nov * nov), 0, nov]
        primary, ray = primary_ray([0.8, 0, 0.6], [0, 0, 1], view, cloth, roughness)
        result.append(
            {
                "albedo": albedo,
                "metal": metal,
                "hair": 0.4,
                "irradiance": irradiance,
                "ao": ao,
                "reflection": reflection,
                "cloth": cloth,
                "view": view,
                "roughness": roughness,
                "tint": tint,
                "scale": 1.2,
                "expected": [f0, single, multi, diffuse, specular, ray, primary],
            }
        )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--brdf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(cases(args.brdf.read_bytes()), stream, allow_nan=False)
