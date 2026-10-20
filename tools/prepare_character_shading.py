"""Install native character-only masks and explicit shading contracts.

Original GLB/PNG files and source-materials.json are never rewritten. Source
VTEX bytes, decoder output and full VMAT parameters remain independently hashed.
"""

import argparse
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image
from prepare_source_decals import sha

FEATURES = {
    "F_CLOTH_SHADING": ["g_tMetalness"],
    "F_SUBSURFACE_SCATTERING": ["g_tSssMask", "g_tDiffuseFalloff"],
    "F_ANISOTROPIC_GLOSS": ["g_tAnisoGloss"],
    "F_RETRO_REFLECTIVE": ["g_tMetalness"],
    "F_ANISOTROPIC_HAIR": ["g_tSssMask", "g_tAnisoGloss"],
    "F_EYEBALLS": ["g_tEyeAlbedo1", "g_tEyeMask1"],
}


def collect(data):
    materials = {}
    for asset in data["assets"].values():
        for entry in asset["materials"]:
            native = entry["native_material"]
            flags = native.get("IntParams", {})
            if native.get("ShaderName") != "csgo_character.vfx":
                continue
            if not any(flags.get(key) == 1 for key in FEATURES):
                continue
            textures = {}
            for flag, bindings in FEATURES.items():
                if flags.get(flag) != 1:
                    continue
                for binding in bindings:
                    path = native.get("TextureParams", {}).get(binding)
                    if not path:
                        raise ValueError("Missing native feature texture: " + binding)
                    if (
                        Path(path).is_absolute()
                        or ".." in Path(path).parts
                        or ":" in path
                    ):
                        raise ValueError("Unsafe native texture path")
                    textures[binding] = path
            row = {
                "name": entry["name"],
                "native_material": native,
                "bindings": textures,
            }
            if entry["name"] in materials and materials[entry["name"]] != row:
                raise ValueError("Ambiguous same-name source character material")
            materials[entry["name"]] = row
    return materials


def install(asset_root, project, resources, decoder, work, profile="base"):
    asset_root, project = asset_root.resolve(), project.resolve()
    if not asset_root.is_relative_to(project / "assets/local_reference"):
        raise ValueError("Expected private installed asset directory")
    stem = (
        "source-character-special"
        if profile in ["special", "eyes"]
        else "source-character-shading"
    )
    if profile == "eyes":
        stem = "source-character-eyes"
    output = asset_root / (stem + ".json")
    destination = asset_root / stem
    if work.exists() or output.exists() or destination.exists():
        raise FileExistsError("Preserve previous source contracts and decoded channels")
    data = json.loads(
        (asset_root / "source-materials.json").read_text(encoding="utf-8")
    )
    for name, entry in data["assets"].items():
        source = (asset_root / name).resolve()
        if (
            not source.is_relative_to(asset_root)
            or sha(source) != entry["visual_sha256"]
        ):
            raise ValueError("Installed character changed since material audit")
    materials = collect(data)
    if not materials:
        raise ValueError("No native character feature materials")
    paths = {path for m in materials.values() for path in m["bindings"].values()}
    sources = {}
    for path in paths:
        source = (resources / (path + "_c")).resolve()
        if not source.is_relative_to(resources.resolve()) or not source.is_file():
            raise ValueError("Missing native VTEX: " + path)
        sources[path] = source
    inputs, decoded = work / "input", work / "decoded"
    inputs.mkdir(parents=True)
    decoded.mkdir()
    for path, source in sources.items():
        target = inputs / (path + "_c")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    with (work / "decode.log").open("wb") as log:
        subprocess.run(
            [
                str(decoder),
                "-i",
                str(inputs),
                "--recursive",
                "-e",
                "vtex_c",
                "-o",
                str(decoded),
                "-d",
                "--threads",
                "4",
            ],
            check=True,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    provenance = {}
    for path, source in sources.items():
        png = decoded / Path(path).with_suffix(".png")
        with Image.open(png) as image:
            image.load()
            provenance[path] = {
                "native_sha256": sha(source),
                "decoded_sha256": sha(png),
                "size": list(image.size),
                "mode": image.mode,
            }
    entries = []
    for material in materials.values():
        bindings = {}
        for key, path in material["bindings"].items():
            target = destination / Path(path).with_suffix(".png")
            bindings[key] = "res://" + target.relative_to(project).as_posix()
        native = material["native_material"]
        remaining = [
            key
            for key in [
                "F_ANISOTROPIC_HAIR",
                "F_EYEBALLS",
                "F_DISTANCE_CONTRAST_ADJUSTMENT",
            ]
            if native.get("IntParams", {}).get(key)
        ]
        entries.append(
            {
                "name": material["name"],
                "render_contract": "source-character-direct-v2",
                "native_material": native,
                "textures": bindings,
                "pending_features": remaining,
            }
        )
    for path in paths:
        target = destination / Path(path).with_suffix(".png")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(decoded / Path(path).with_suffix(".png"), target)
    manifest = {
        "schema": 1,
        "reference": "ValveResourceFormat@54279ec226cc3e1c561b10f11f0f5e879b981e6e",
        "materials": entries,
        "textures": provenance,
        "limits": [
            "Godot environment BRDF differs from Source 2",
            "skin diffuse soft normal uses geometric normal",
            "spherical tangents use the converted model frame; native bone-space equivalence requires further reference validation",
            "hair environment lobe and distance contrast remain pending",
            "eyes require independently calibrated model bone bindings",
        ],
    }
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--decoder", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument(
        "--profile", choices=["base", "special", "eyes"], default="base"
    )
    args = parser.parse_args()
    result = install(
        args.asset_root,
        Path(__file__).resolve().parents[1],
        args.resources,
        args.decoder,
        args.work,
        args.profile,
    )
    print(
        "SOURCE_CHARACTER_CHANNELS_OK",
        len(result["materials"]),
        len(result["textures"]),
    )


if __name__ == "__main__":
    main()
