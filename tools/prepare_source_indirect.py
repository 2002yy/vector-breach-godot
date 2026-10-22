"""Preserve source sun parameters and label viewer-derived ambient SH explicitly."""

import argparse
import hashlib
import json
from pathlib import Path

from source_indirect_light import (
    ambient_sh,
    complete_probe,
    indirect_energy,
    soft_diffuse,
)
from source_reflection_normalization import brdf_lookup, env_brdf


def build(path, output, brdf):
    data = json.loads(path.read_text(encoding="utf-8"))
    suns = [e for e in data["sun_entities"] if e.get("enabled") is True]
    if len(suns) != 1:
        raise ValueError("One original environment light required")
    result = {
        "schema": 1,
        "contract": "source-indirect-diagnostic-v1",
        "level": data["level"],
        "source_trace": data["source_trace"],
        "lighting_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "kind": "viewer-derived-source-sun-SH1",
        "source_sun": suns[0],
        "ambient_sh": ambient_sh(suns[0]),
        "limits": [
            "not captured engine per-view constants",
            "native dynamic-probe six-axis SH fallback only",
        ],
    }
    raw = brdf.read_bytes()
    cases = []
    for normal in [
        [1, 0, 0],
        [-1, 0, 0],
        [0, 1, 0],
        [0, -1, 0],
        [0, 0, 1],
        [0, 0, -1],
        [0.6, 0, 0.8],
    ]:
        for coverage in [0, 0.5, 0.989, 0.99, 1]:
            for skin in [0, 0.8]:
                index = len(cases)
                cube = [
                    [v * coverage for v in row]
                    for row in [
                        [0.2, 0.5, 0.8],
                        [0.6, 0.3, 0.9],
                        [1, 0.7, 0.4],
                        [0.8, 0.2, 0.5],
                        [0.4, 0.9, 0.3],
                        [0.3, 0.4, 0.6],
                    ]
                ]
                geometric = [0, 0, 1] if normal[2] > -0.9 else [0, 1, 0]
                rough = [0.2, 0.5, 1][index % 3]
                nov = abs(normal[2])
                albedo = [0.3, 0.5, 0.7]
                reflection = [0.4, 0.8, 0.6]
                ao = [0, 0.35, 1][index % 3]
                metallic = [0, 0.5, 1][(index // 3) % 3]
                single, multi = env_brdf(
                    brdf_lookup(raw, rough, nov), [0.046, 0.035, 0.02]
                )
                plain = complete_probe(cube, coverage, result["ambient_sh"], normal)
                softened = soft_diffuse(
                    cube,
                    coverage,
                    result["ambient_sh"],
                    normal,
                    geometric,
                    [1, 0.302, 0],
                    skin,
                )
                diffuse, specular = indirect_energy(
                    softened, reflection, single, multi, albedo, metallic, ao
                )
                cases.append(
                    {
                        "normal": normal,
                        "geometric": geometric,
                        "coverage": coverage,
                        "skin": skin,
                        "cube": cube,
                        "roughness": rough,
                        "ndotv": nov,
                        "albedo": albedo,
                        "reflection": reflection,
                        "ao": ao,
                        "metallic": metallic,
                        "expected": [plain, softened, diffuse, specular],
                    }
                )
    result["cases"] = cases
    if output.exists():
        raise FileExistsError("Preserve existing indirect evidence")
    output.write_text(json.dumps(result, indent=2, allow_nan=False), encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lighting", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--brdf", type=Path, required=True)
    args = parser.parse_args()
    print(
        "SOURCE_INDIRECT_INPUTS_OK",
        build(args.lighting, args.output, args.brdf)["level"],
    )
