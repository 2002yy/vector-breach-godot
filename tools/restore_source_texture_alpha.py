"""Recover original VTEX alpha omitted by a shader-unaware glTF export.

Decode with Source 2 Viewer, never paint or synthesize pixels. Apply only if RGB
bytes match and the original texture has a nonconstant transparency channel.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from urllib.parse import unquote

from PIL import Image


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-gltf", type=Path, required=True)
    parser.add_argument("--target-gltf", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--decoder", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.source_gltf.read_text(encoding="utf-8"))
    inputs = args.work / "input"
    decoded = args.work / "decoded"
    if inputs.exists() or decoded.exists():
        raise FileExistsError(
            "Keep earlier alpha evidence; choose a new work directory"
        )
    inputs.mkdir(parents=True)
    decoded.mkdir()
    candidates = {}
    for material in data.get("materials", []):
        if material.get("alphaMode", "OPAQUE") not in ["MASK", "BLEND"]:
            continue
        color = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if not color:
            continue
        uri = data["images"][data["textures"][color["index"]]["source"]]["uri"]
        target = (args.target_gltf.parent / unquote(uri)).resolve()
        if not target.is_relative_to(args.target_gltf.parent.resolve()):
            raise ValueError("Texture outside private output folder")
        with Image.open(target) as image:
            if "A" in image.getbands():
                continue
        vmat = material.get("extras", {}).get("vmat", {})
        texture = vmat.get("TextureParams", {}).get("g_tColor")
        if not texture or Path(texture).stem != Path(uri).stem:
            continue
        source = (args.resources / (texture + "_c")).resolve()
        if not source.is_relative_to(args.resources.resolve()) or not source.is_file():
            raise ValueError("Missing verified VTEX source")
        if uri not in candidates:
            relative = source.relative_to(args.resources.resolve())
            staged = inputs / relative
            staged.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, staged)
            candidates[uri] = {
                "source": source,
                "target": target,
                "decoded": decoded / relative.with_suffix(".png"),
            }
    log = args.work / "decode.log"
    with log.open("wb") as stream:
        result = subprocess.run(
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
            stdout=stream,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if result.returncode != 0:
        raise RuntimeError("Texture decoder failed; inspect decode.log")
    changes = []
    for uri, record in candidates.items():
        original = record["decoded"]
        if not original.is_file():
            raise ValueError("Missing decoded texture at its resource path: " + uri)
        with Image.open(original) as full, Image.open(record["target"]) as old:
            if "A" not in full.getbands():
                continue
            minimum, maximum = full.getchannel("A").getextrema()
            if minimum == maximum:
                continue
            if (
                full.size != old.size
                or full.convert("RGB").tobytes() != old.convert("RGB").tobytes()
            ):
                raise ValueError(
                    "Decoder changed RGB; investigate before replacing " + uri
                )
        changes.append((uri, record, original))
    restored = []
    for uri, record, original in changes:
        backup = args.work / "before" / unquote(uri)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(record["target"], backup)
        shutil.copy2(original, record["target"])
        restored.append(
            {
                "uri": uri,
                "source_vtex_sha256": digest(record["source"]),
                "before_sha256": digest(backup),
                "decoded_png_sha256": digest(original),
            }
        )
    receipt = {
        "candidate_count": len(candidates),
        "restored": restored,
        "method": "Source2Viewer native VTEX decode; RGB identity verified",
    }
    (args.work / "receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    asset_receipt = args.target_gltf.with_suffix(".receipt.json")
    output = json.loads(asset_receipt.read_text(encoding="utf-8"))
    previous = output.get("native_alpha_restorations", [])
    replaced = {record["uri"] for record in restored}
    output["native_alpha_restorations"] = [
        record for record in previous if record["uri"] not in replaced
    ] + restored
    for record in restored:
        output["copied_dependency_sha256"][record["uri"]] = record["decoded_png_sha256"]
    asset_receipt.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print("ORIGINAL_ALPHA_RESTORED", len(restored), "of", len(candidates), "candidates")


if __name__ == "__main__":
    main()
