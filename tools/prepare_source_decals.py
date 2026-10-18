"""Install verified native alpha beside immutable original map textures.

Consume receipts produced by native VTEX decoding. RGB must match the current
export pixel-for-pixel. Existing RGBA exports may be retained without decoding.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
from urllib.parse import unquote

from PIL import Image


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_scene(path):
    if path.suffix == ".gltf":
        return json.loads(path.read_text(encoding="utf-8"))
    with path.open("rb") as stream:
        magic, version, _ = struct.unpack("<4sII", stream.read(12))
        size, kind = struct.unpack("<I4s", stream.read(8))
        if magic != b"glTF" or version != 2 or kind != b"JSON":
            raise ValueError("Expected a glTF 2 export")
        return json.loads(stream.read(size))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--decoded-receipt", type=Path, action="append", default=[])
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    visual = args.visual.resolve()
    if not visual.is_relative_to(repo / "assets/local_reference"):
        raise ValueError("Expected an installed private visual")
    if sha(visual) != args.expected_sha256:
        raise ValueError("Visual changed since its audited baseline")
    output = visual.parent / "source-decal-alpha.json"
    target = visual.parent / "source-decals"
    if output.exists() or target.exists():
        raise FileExistsError("Preserve previous manifests and decoded inputs")
    decoded = {}
    for receipt in args.decoded_receipt:
        for item in json.loads(receipt.read_text(encoding="utf-8")):
            if item.get("native_available"):
                decoded[(str(Path(item["old_png"]).resolve()), item["texture"])] = item
    scene = read_scene(visual)
    entries, copies, inputs = {}, {}, []
    for mat in scene.get("materials", []):
        native = mat.get("extras", {}).get("vmat", {})
        mode = native.get("IntParams", {}).get("F_BLEND_MODE")
        if native.get("ShaderName") != "csgo_static_overlay.vfx" or mode not in [1, 2]:
            continue
        if mat.get("alphaMode", "OPAQUE") != "OPAQUE":
            continue
        color = mat["pbrMetallicRoughness"]["baseColorTexture"]
        image = scene["images"][scene["textures"][color["index"]]["source"]]
        old = (visual.parent / unquote(image["uri"])).resolve()
        if not old.is_relative_to(visual.parent):
            raise ValueError("Texture outside the installed visual directory")
        texture = native["TextureParams"]["g_tColor"]
        item = decoded.get((str(old), texture))
        chosen, destination = old, old
        provenance = {"exported_png": str(old), "exported_sha256": sha(old)}
        if item:
            chosen = Path(item["decoded_png"]).resolve()
            if sha(chosen) != item["decoded_sha256"]:
                raise ValueError("Decoded native input changed")
            relative = Path(texture).with_suffix(".png")
            destination = (target / relative).resolve()
            if not destination.is_relative_to(target):
                raise ValueError("Native texture escapes its private destination")
            copies[destination] = chosen
            provenance.update(
                native_vtex=str(item["native_source"]),
                native_vtex_sha256=sha(Path(item["native_source"])),
                decoded_sha256=item["decoded_sha256"],
                alpha_source="native VTEX decode; RGB identity checked",
            )
        else:
            provenance["alpha_source"] = (
                "existing exported RGBA; native VTEX not reacquired"
            )
        with Image.open(chosen) as full, Image.open(old) as exported:
            if (
                full.size != exported.size
                or full.convert("RGB").tobytes() != exported.convert("RGB").tobytes()
            ):
                raise ValueError("Decoded RGB differs from the original export")
            if "A" not in full.getbands():
                raise ValueError("No verified alpha for " + mat["name"])
            minimum, maximum = full.getchannel("A").getextrema()
            if minimum == maximum:
                raise ValueError("Constant alpha requires a separate material review")
            provenance["alpha_extrema"] = [minimum, maximum]
        opacity = float(native.get("FloatParams", {}).get("g_flOpacityScale", 1.0))
        factor = mat.get("pbrMetallicRoughness", {}).get(
            "baseColorFactor", [1, 1, 1, 1]
        )
        if float(factor[3]) != 1.0:
            raise ValueError("Review existing opacity before applying a second factor")
        entry = {
            "name": mat["name"],
            "source_shader": native["ShaderName"],
            "blend_mode": mode,
            "texture": "res://" + destination.relative_to(repo).as_posix(),
            "opacity_multiplier": opacity,
            "alpha_test": native.get("FloatParams", {}).get(
                "g_flAlphaTestReference", 0.5
            ),
            "no_shadow": native.get("IntParams", {}).get("F_DO_NOT_CAST_SHADOWS") == 1,
        }
        if entry["name"] in entries and entries[entry["name"]] != entry:
            raise ValueError("Conflicting same-name native decal variants")
        entries[entry["name"]] = entry
        inputs.append(provenance)
    if not entries:
        raise ValueError("No verified alpha/cutout overlays")
    # Finish validation before installing any output, and never rewrite old PNGs.
    for destination, source in copies.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    manifest = {
        "schema": 1,
        "visual_sha256": args.expected_sha256,
        "materials": list(entries.values()),
        "inputs": inputs,
    }
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        "SOURCE_DECAL_ALPHA_INSTALLED",
        len(entries),
        "materials",
        len(copies),
        "native PNGs",
    )


if __name__ == "__main__":
    main()
