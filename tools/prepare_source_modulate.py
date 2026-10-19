"""Preserve complete VMAT data and install verified Mod2x without changing inputs.

Original exports, textures and the existing alpha manifest are immutable. Native
VTEX receipts must match both their hashes and every exported RGB pixel.
"""

import argparse
import json
import shutil
from pathlib import Path
from urllib.parse import unquote

from PIL import Image
from prepare_source_decals import read_scene, sha

CONTRACT = "source-static-overlay-mod2x-v1"
REFERENCE = (
    "ValveResourceFormat/ValveResourceFormat@54279ec226cc3e1c561b10f11f0f5e879b981e6e"
)


def install(visual, repo, receipt):
    visual, repo = visual.resolve(), repo.resolve()
    if not visual.is_relative_to(repo / "assets/local_reference"):
        raise ValueError("Expected private installed source visual")
    output = visual.parent / "source-modulate.json"
    destination_root = visual.parent / "source-modulate"
    if output.exists() or destination_root.exists():
        raise FileExistsError("Preserve previous material contract")
    decoded = {
        (str(Path(item["old_png"]).resolve()), item["texture"]): item
        for item in receipt
        if item.get("native_available")
    }
    scene = read_scene(visual)
    entries, copies = {}, {}
    for mat in scene.get("materials", []):
        native = mat.get("extras", {}).get("vmat", {})
        if native.get("ShaderName") != "csgo_static_overlay.vfx":
            continue
        if native.get("IntParams", {}).get("F_BLEND_MODE") != 3:
            continue
        # Fail closed on features this contract does not implement. Archiving
        # their values alone must never be mistaken for rendering support.
        flags = native.get("IntParams", {})
        allowed = {
            "F_BLEND_MODE",
            "g_bFogEnabled",
            "g_nTextureAddressModeU",
            "g_nTextureAddressModeV",
        }
        for key, value in flags.items():
            if key not in allowed and value != 0:
                raise ValueError("Unsupported Mod2x flag: " + key)
        if any(
            flags.get(k, 0) != 0
            for k in ("g_nTextureAddressModeU", "g_nTextureAddressModeV")
        ):
            raise ValueError("Non-repeat sampler requires a separate contract")
        floats = native.get("FloatParams", {})
        defaults = {
            "g_flModelTintAmount": 1,
            "g_flOpacityScale": 1,
            "g_flTexCoordRotation": 0,
        }
        if any(key not in defaults for key in floats):
            raise ValueError("Additional Mod2x float parameters require review")
        vectors = native.get("VectorParams", {})
        identities = {
            "g_vColorTint": [1, 1, 1, 0],
            "g_vTexCoordCenter": [0.5, 0.5, 0, 0],
            "g_vTexCoordOffset": [0, 0, 0, 0],
            "g_vTexCoordScale": [1, 1, 0, 0],
            "g_vTexCoordScrollSpeed": [0, 0, 0, 0],
        }
        for key, value in vectors.items():
            # TextureColor is source texture metadata, not a color correction.
            if key != "TextureColor" and (
                key not in identities or value != identities[key]
            ):
                raise ValueError(
                    "Additional Mod2x vector parameters require review: " + key
                )
        if floats.get("g_flTexCoordRotation", 0) != 0:
            raise ValueError("Rotated source UV requires review")
        pbr = mat["pbrMetallicRoughness"]
        if pbr.get("baseColorFactor", [1, 1, 1, 1])[3] != 1:
            raise ValueError("Exported alpha factor requires review")
        color = pbr["baseColorTexture"]
        image = scene["images"][scene["textures"][color["index"]]["source"]]
        old = (visual.parent / unquote(image["uri"])).resolve()
        if not old.is_relative_to(visual.parent):
            raise ValueError("Exported texture escapes its visual directory")
        texture = native["TextureParams"]["g_tColor"]
        item = decoded.get((str(old), texture))
        if item is None:
            raise ValueError("Missing verified native texture: " + mat["name"])
        chosen, vtex = Path(item["decoded_png"]), Path(item["native_source"])
        if sha(chosen) != item["decoded_sha256"]:
            raise ValueError("Native decode changed")
        with Image.open(chosen) as full, Image.open(old) as exported:
            if (
                full.size != exported.size
                or full.convert("RGB").tobytes() != exported.convert("RGB").tobytes()
            ):
                raise ValueError("Native RGB differs from export")
            alpha = (
                list(full.getchannel("A").getextrema())
                if "A" in full.getbands()
                else [255, 255]
            )
        destination = (destination_root / Path(texture).with_suffix(".png")).resolve()
        if not destination.is_relative_to(destination_root):
            raise ValueError("Native texture escapes private destination")
        entry = {
            "name": mat["name"],
            "source_shader": native["ShaderName"],
            "blend_mode": 3,
            "render_contract": CONTRACT,
            "texture": "res://" + destination.relative_to(repo).as_posix(),
            "opacity_multiplier": floats.get("g_flOpacityScale", 1),
            "native_material": native,
            "exported_material": mat,
            "provenance": {
                "exported_texture_sha256": sha(old),
                "native_vtex_sha256": sha(vtex),
                "decoded_sha256": sha(chosen),
                "alpha_extrema": alpha,
            },
            "render_rules": {
                "rgb_sampling": "encoded sRGB values, alpha linear",
                "equation": "D * mix(1, 2 * RGB, alpha * opacity)",
                "lighting": "unlit multiplier inherits destination lighting",
                "depth_test": True,
                "depth_write": False,
                "casts_shadow": False,
                "fog": "fade contribution to neutral multiplier using active environment distance/depth/height attenuation; volumetric scattering not reproduced",
                "offset_uv_culling_priority": "preserve effective imported material",
            },
        }
        if mat["name"] in entries and entries[mat["name"]] != entry:
            raise ValueError("Conflicting same-name Mod2x variants")
        entries[mat["name"]] = entry
        copies[destination] = chosen
    if not entries:
        raise ValueError("No Mod2x materials")
    for destination, source in copies.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    manifest = {
        "schema": 1,
        "visual_sha256": sha(visual),
        "reference": REFERENCE,
        "materials": list(entries.values()),
    }
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", type=Path, required=True)
    parser.add_argument("--decoded-receipt", type=Path, required=True)
    args = parser.parse_args()
    manifest = install(
        args.visual,
        Path(__file__).resolve().parents[1],
        json.loads(args.decoded_receipt.read_text(encoding="utf-8")),
    )
    print("SOURCE_MOD2X_INSTALLED", len(manifest["materials"]))


if __name__ == "__main__":
    main()
