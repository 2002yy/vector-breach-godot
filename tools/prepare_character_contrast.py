"""Preserve native VTEX reflectivity and resolve character dynamic uniforms.

The reflectivity binding remains an explicit diagnostic candidate. No model,
texture, old sidecar or gameplay setting is rewritten or enabled by this tool.
"""

import argparse
import json
import math
import struct
from pathlib import Path, PurePosixPath

from prepare_source_decals import sha


def read_reflectivity(raw):
    if len(raw) < 16:
        raise ValueError("Truncated resource header")
    size, header, resource_version, relative, count = struct.unpack_from("<IHHII", raw)
    table = 8 + relative
    if header != 12 or resource_version != 1 or not 16 <= size <= len(raw):
        raise ValueError("Unsupported resource header")
    if count > 128 or table < 16 or table + count * 12 > size:
        raise ValueError("Invalid resource block table")
    result = None
    for index in range(count):
        block = table + index * 12
        kind, relative, length = struct.unpack_from("<4sII", raw, block)
        if kind != b"DATA":
            continue
        start = block + 4 + relative
        if (
            result is not None
            or length < 40
            or start < table + count * 12
            or start + length > size
        ):
            raise ValueError("Invalid texture DATA block")
        version, flags, *rgba = struct.unpack_from("<HH4f", raw, start)
        width, height, depth = struct.unpack_from("<HHH", raw, start + 20)
        if version != 1 or not width or not height or depth != 1:
            raise ValueError("Expected version 1 2D texture")
        if not all(math.isfinite(v) and 0 <= v <= 1 for v in rgba):
            raise ValueError("Invalid LDR reflectivity")
        result = {
            "reflectivity_rgba": rgba,
            "dimensions": [width, height, depth],
            "flags": flags,
        }
    if result is None:
        raise ValueError("Missing texture DATA")
    return result


def effective_uniforms(native):
    flags = native.get("IntParams", {})
    for key in ("F_TRANSLUCENT", "F_DISTANCE_CONTRAST_ADJUSTMENT"):
        if flags.get(key, 0) not in (0, 1):
            raise ValueError("Invalid native feature flag")
    raw = float(native.get("FloatParams", {}).get("g_fDistanceContrastExposure", 0.6))
    if not math.isfinite(raw) or not 0 <= raw <= 1:
        raise ValueError("Invalid exposure")
    translucent = flags.get("F_TRANSLUCENT", 0) == 1
    return {
        "exposure_raw": raw,
        "exposure_effective": raw if translucent else 1 - raw,
        "material_adjustment": flags.get("F_DISTANCE_CONTRAST_ADJUSTMENT", 0) == 1
        and not translucent,
    }


def collect(data, resources):
    entries = {}
    resources = resources.resolve()
    for asset in data["assets"].values():
        for entry in asset["materials"]:
            native = entry["native_material"]
            if native.get("ShaderName") != "csgo_character.vfx":
                continue
            texture = native.get("TextureParams", {}).get("g_tColor", "")
            path = PurePosixPath(texture)
            if (
                not texture
                or path.is_absolute()
                or ".." in path.parts
                or ":" in texture
                or "\\" in texture
                or path.suffix != ".vtex"
            ):
                raise ValueError("Unsafe or missing native color texture")
            source = (resources / (texture + "_c")).resolve()
            if not source.is_relative_to(resources):
                raise ValueError("Native texture escaped resource root")
            metadata = read_reflectivity(source.read_bytes())
            row = {
                "name": entry["name"],
                "native_material": native,
                "texture": texture,
                "native_sha256": sha(source),
                "average_basis": "vtex-reflectivity-candidate",
                **metadata,
                **effective_uniforms(native),
            }
            if row["name"] in entries and entries[row["name"]] != row:
                raise ValueError("Conflicting same-name material")
            entries[row["name"]] = row
    return list(entries.values())


def install(asset_root, project, resources):
    asset_root, project = asset_root.resolve(), project.resolve()
    if not asset_root.is_relative_to(project / "assets/local_reference"):
        raise ValueError("Expected private asset root")
    output = asset_root / "source-character-contrast-inputs.json"
    if output.exists():
        raise FileExistsError("Preserve previous input contract")
    manifest = asset_root / "source-materials.json"
    data = json.loads(manifest.read_text(encoding="utf-8"))
    for name, entry in data["assets"].items():
        source = (asset_root / name).resolve()
        if (
            not source.is_relative_to(asset_root)
            or sha(source) != entry["visual_sha256"]
        ):
            raise ValueError("Installed model changed since audit")
    rows = collect(data, resources)
    if not rows:
        raise ValueError("No native character materials")
    result = {
        "schema": 1,
        "contract": "source-character-contrast-inputs-v1",
        "materials_manifest_sha256": sha(manifest),
        "materials": rows,
        "limits": [
            "VTEX reflectivity to TextureAverageColor binding requires native reference",
            "directional irradiance and FogModificationAmount must be independently supplied",
            "diagnostic only; does not enable gameplay",
        ],
    }
    with output.open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    args = parser.parse_args()
    result = install(
        args.asset_root, Path(__file__).resolve().parents[1], args.resources
    )
    print("CHARACTER_CONTRAST_INPUTS_OK materials=", len(result["materials"]))


if __name__ == "__main__":
    main()
