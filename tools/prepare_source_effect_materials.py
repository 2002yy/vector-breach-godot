"""Decode original Source 2 effect inputs into an optional private shader manifest.

Keep the map glTF, source textures, collision and frozen layout byte-identical.
This is a Godot mask/blend adaptation, not the complete Source 2 effect renderer.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--decoder", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    visual = args.visual.resolve()
    output = visual.parent / "source-effects.json"
    target = visual.parent / "source-effects"
    if not visual.is_relative_to(repo / "assets/local_reference"):
        raise ValueError("Expected a private installed visual")
    if output.exists() or target.exists() or args.work.exists():
        raise FileExistsError("Preserve previous evidence; choose a fresh target/work")
    scene = json.loads(visual.read_text(encoding="utf-8"))
    entries = []
    sources = {}
    resources = args.resources.resolve()
    for material in scene.get("materials", []):
        vmat = material.get("extras", {}).get("vmat", {})
        if vmat.get("ShaderName") != "csgo_effects.vfx":
            continue
        entry = {
            "name": material["name"],
            "source_shader": vmat["ShaderName"],
            "source_vmat": vmat["Name"],
            "additive": bool(vmat.get("IntParams", {}).get("F_ADDITIVE_BLEND", 0)),
            "opacity": vmat.get("FloatParams", {}).get("g_flOpacityScale", 1.0),
        }
        for parameter, key in [
            ("g_tColor", "color_texture"),
            ("g_tMask1", "mask1"),
            ("g_tMask2", "mask2"),
            ("g_tMask3", "mask3"),
        ]:
            relative = Path(vmat["TextureParams"][parameter] + "_c")
            source = (resources / relative).resolve()
            if not source.is_relative_to(resources) or not source.is_file():
                raise ValueError("Missing verified effect input: " + str(relative))
            sources[relative] = source
            png = target / relative.with_suffix(".png")
            entry[key] = "res://" + png.relative_to(repo).as_posix()
        for index in range(1, 4):
            vectors = vmat.get("VectorParams", {})
            entry[f"mask{index}_scale"] = vectors.get(f"g_vMask{index}Scale", [1, 1])[
                :2
            ]
            entry[f"mask{index}_pan"] = vectors.get(f"g_vMask{index}PanSpeed", [0, 0])[
                :2
            ]
        entries.append(entry)
    if not entries:
        raise ValueError("No supported source effects")
    inputs = args.work / "inputs"
    decoded = args.work / "decoded"
    inputs.mkdir(parents=True)
    for relative, source in sources.items():
        staged = inputs / relative
        staged.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, staged)
    with (args.work / "decode.log").open("wb") as log:
        subprocess.run(
            [
                str(args.decoder),
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
            stdout=log,
            stderr=subprocess.STDOUT,
            check=True,
        )
    # Validate the complete decode before installing any output.
    for relative in sources:
        if not (decoded / relative.with_suffix(".png")).is_file():
            raise ValueError("Decoder omitted " + str(relative))
    hashes = []
    for relative, source in sources.items():
        png = decoded / relative.with_suffix(".png")
        destination = target / relative.with_suffix(".png")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(png, destination)
        hashes.append(
            {
                "source": str(source),
                "source_sha256": sha(source),
                "png": str(destination),
                "png_sha256": sha(destination),
            }
        )
    manifest = {
        "schema": 1,
        "materials": entries,
        "method": "Original VTEX decode with Godot alpha/mask/panning and blend adaptation; Source 2 depth feather/fresnel not reproduced",
    }
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    receipt = {
        "visual_sha256_unchanged": sha(visual),
        "manifest_sha256": sha(output),
        "textures": hashes,
        "materials": entries,
    }
    (args.work / "receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    print("SOURCE_EFFECT_INPUTS_INSTALLED", len(entries), len(sources))


if __name__ == "__main__":
    main()
