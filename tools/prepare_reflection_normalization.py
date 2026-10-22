"""Bind preserved native SH and BRDF data to one verified reflection bundle."""

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path

from source_reflection_normalization import (
    brdf_lookup,
    env_brdf,
    hair_secondary_ray,
    normalization,
    normalization_sh,
)


def build(reflection, sh, brdf_dir, compiled_brdf, output):
    data = json.loads(reflection.read_text(encoding="utf-8"))
    native = json.loads(sh.read_text(encoding="utf-8"))
    if (
        native.get("compiled_sha256") != data["compiled_sha256"]
        or native["cubes"] != data["cubes"]
        or len(native["native_coefficients"]) != data["cubes"] * 27
    ):
        raise ValueError("SH array differs from reflection cubes")
    coefficients = native["native_coefficients"]
    harmonics = [
        normalization_sh(coefficients[i : i + 27])
        for i in range(0, len(coefficients), 27)
    ]
    raw = (brdf_dir / "brdf-rgba-f32.bin").read_bytes()
    if len(raw) != 64 * 64 * 3 * 16:
        raise ValueError("Invalid BRDF payload")
    if output.exists():
        raise FileExistsError("Preserve existing normalization evidence")
    output.mkdir(parents=True)
    shutil.copyfile(brdf_dir / "brdf-rgba-f32.bin", output / "brdf-rgba-f32.bin")
    cases = []
    for index, harmonic in enumerate(harmonics):
        for rough, ndotv in [(0.045, 1), (0.2, 0.75), (0.5, 0.4), (1, 0)]:
            normal = [math.sqrt(1 - ndotv * ndotv), 0, ndotv]
            irradiance = [0.3, 0.6, 0.9]
            f0 = [0.046, 0.035, 0.02]
            lut = brdf_lookup(raw, rough, ndotv)
            single, multi = env_brdf(lut, f0)
            pair = (
                [max(rough * 0.5, 0.045), rough]
                if index % 2
                else [rough, max(rough * 0.5, 0.045)]
            )
            secondary = hair_secondary_ray(
                normal,
                [0, 0, 1],
                [0, 1, 0],
                [-normal[2], 0, normal[0]],
                pair,
                0.3,
                1.25,
            )
            cases.append(
                {
                    "cube": index,
                    "roughness": rough,
                    "ndotv": ndotv,
                    "normal": normal,
                    "irradiance": irradiance,
                    "f0": f0,
                    "sh": harmonic,
                    "normalization": normalization(rough, normal, irradiance, harmonic),
                    "single": single,
                    "multi": multi,
                    "rough_xy": pair,
                    "secondary_ray": [v * 0.5 + 0.5 for v in secondary],
                }
            )
    result = {
        "schema": 1,
        "contract": "source-reflection-normalization-v1",
        "level": data["level"],
        "source_trace": data["source_trace"],
        "reflection_sha256": data["sha256"],
        "compiled_reflection_sha256": data["compiled_sha256"],
        "native_sh": native,
        "normalization_sh": harmonics,
        "brdf": {
            "file": "brdf-rgba-f32.bin",
            "sha256": hashlib.sha256(raw).hexdigest(),
            "compiled_sha256": hashlib.sha256(compiled_brdf.read_bytes()).hexdigest(),
        },
        "cases": cases,
    }
    (output / "normalization.json").write_text(
        json.dumps(result, indent=2, allow_nan=False), encoding="utf-8"
    )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ["reflection", "sh", "brdf_dir", "compiled_brdf", "output"]:
        parser.add_argument("--" + key.replace("_", "-"), type=Path, required=True)
    result = build(**vars(parser.parse_args()))
    print("REFLECTION_NORMALIZATION_INPUTS_OK", result["level"], len(result["cases"]))
