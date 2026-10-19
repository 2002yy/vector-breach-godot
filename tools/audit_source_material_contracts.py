"""Archive source material semantics and flag exports requiring visual review.

This is an inventory, never a visual acceptance result. No source asset is edited.
Use --scene for exports and --pair runtime.glb=source.gltf for converted assets.
"""

import argparse
import json
from collections import Counter
from pathlib import Path

from prepare_source_decals import read_scene, sha

SPECIAL_FEATURES = {
    "F_ANISOTROPIC_GLOSS",
    "F_CLOTH_SHADING",
    "F_SUBSURFACE_SCATTERING",
    "F_SELF_ILLUM",
    "F_FOLIAGE_ANIMATION",
    "F_VERTEX_ANIMATION",
    "F_TINT_MASK",
    "F_DETAIL_TEXTURE",
    "F_DISTANCE_CONTRAST_ADJUSTMENT",
    "F_PAINT_VERTEX_COLORS",
    "F_ALPHA_TEST",
    "F_TRANSLUCENT",
    "F_ADDITIVE_BLEND",
    "F_RENDER_BACKFACES",
    "F_TWO_SIDED",
}


def runtime_contract(asset):
    """Archive every parameter; only the audited additive rule changes rendering."""
    materials = []
    for row in asset["materials"]:
        native = row["native_material"]
        additive = native.get("IntParams", {}).get("F_ADDITIVE_BLEND") == 1
        mapped = {
            "F_RENDER_BACKFACES",
            "F_TRANSLUCENT",
            "F_SELF_ILLUM",
            "F_ADDITIVE_BLEND",
        }
        materials.append(
            {
                "name": row["name"],
                "native_material": native,
                "render_contract": "source-additive-v1"
                if additive
                else "preserve-exported-pbr-v1",
                "pending_features": [
                    key for key in row["special_features"] if key not in mapped
                ],
            }
        )
    return {
        "visual_sha256": asset["sha256"],
        "source_sha256": asset["source_sha256"],
        "materials": materials,
    }


def install_runtime_contracts(assets, repo):
    groups = {}
    for asset in assets:
        if asset["scene"] == asset["source"]:
            continue
        scene = Path(asset["scene"]).resolve()
        if not scene.is_relative_to(repo.resolve() / "assets/local_reference"):
            raise ValueError("Runtime contract must stay in private local assets")
        if any(not row["native_material"] for row in asset["materials"]):
            raise ValueError("Cannot install an incomplete material identity")
        groups.setdefault(scene.parent, {})[scene.name] = runtime_contract(asset)
    if any((folder / "source-materials.json").exists() for folder in groups):
        raise FileExistsError("Preserve previous runtime material contracts")
    for folder, entries in groups.items():
        (folder / "source-materials.json").write_text(
            json.dumps({"schema": 1, "assets": entries}, indent=2) + "\n",
            encoding="utf-8",
        )


def material_record(material, native=None):
    native = native or material.get("extras", {}).get("vmat", {})
    flags = native.get("IntParams", {})
    risks = []
    mode = flags.get("F_BLEND_MODE", 0)
    if mode > 0:
        risks.append("source_blend_mode_" + str(mode))
    if flags.get("F_ALPHA_TEST", 0) and material.get("alphaMode", "OPAQUE") != "MASK":
        risks.append("alpha_test_not_in_export")
    if flags.get("F_TRANSLUCENT", 0) and material.get("alphaMode", "OPAQUE") != "BLEND":
        risks.append("translucency_not_in_export")
    if any(
        flags.get(k, 0) for k in ("F_RENDER_BACKFACES", "F_TWO_SIDED")
    ) and not material.get("doubleSided", False):
        risks.append("source_backfaces_not_in_export")
    textures = native.get("TextureParams", {})
    if "g_tNormal" in textures and "normalTexture" not in material:
        risks.append("source_normal_not_in_export")
    if native and "vmat" not in material.get("extras", {}):
        risks.append("source_parameters_absent_from_runtime_export")
    if not native:
        risks.append("no_native_material_contract")
    features = {k: v for k, v in flags.items() if k in SPECIAL_FEATURES and v != 0}
    if features:
        risks.append("source_features_need_render_mapping")
    adjustments = {
        k: v
        for k, v in native.get("FloatParams", {}).items()
        if ("TextureColor" in k and v != 1) or ("TexCoordRotation" in k and v != 0)
    }
    if adjustments:
        risks.append("nondefault_source_color_or_uv_adjustment")
    return {
        "name": material.get("name", ""),
        "native_material": native,
        "exported_material": material,
        "risks": sorted(set(risks)),
        "special_features": features,
        "source_adjustments": adjustments,
        "acceptance": "requires_review"
        if risks
        else "no_static_flag; visual acceptance still required",
    }


def audit(scene_path, source_path=None):
    scene = read_scene(scene_path)
    source = read_scene(source_path) if source_path else scene
    materials = source.get("materials", [])
    by_name = {}
    for mat in materials:
        by_name.setdefault(mat.get("name", ""), []).append(mat)
    records = []
    for mat in scene.get("materials", []):
        variants = by_name.get(mat.get("name", ""), [])
        native = (
            variants[0].get("extras", {}).get("vmat", {}) if len(variants) == 1 else {}
        )
        record = material_record(mat, native)
        if source_path and len(variants) != 1:
            record["risks"].append("source_material_identity_ambiguous_or_missing")
        records.append(record)
    return {
        "scene": str(scene_path),
        "sha256": sha(scene_path),
        "source": str(source_path) if source_path else str(scene_path),
        "source_sha256": sha(source_path or scene_path),
        "source_materials": materials,
        "source_texture_bindings": {
            key: source.get(key, []) for key in ("images", "textures", "samplers")
        },
        "runtime_texture_bindings": {
            key: scene.get(key, []) for key in ("images", "textures", "samplers")
        },
        "materials": records,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", type=Path, action="append", default=[])
    parser.add_argument("--pair", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--install-runtime-contracts", action="store_true")
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Preserve previous audit")
    assets = [audit(p) for p in args.scene]
    assets += [audit(*(Path(x) for x in pair.split("=", 1))) for pair in args.pair]
    if not assets:
        parser.error("No scenes supplied")
    rows = [m for asset in assets for m in asset["materials"]]
    counts = Counter(risk for row in rows for risk in row["risks"])
    report = {
        "schema": 1,
        "visual_acceptance": False,
        "assets": assets,
        "summary": {
            "assets": len(assets),
            "materials": len(rows),
            "risk_counts": dict(sorted(counts.items())),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.install_runtime_contracts:
        install_runtime_contracts(assets, Path(__file__).resolve().parents[1])
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"]))


if __name__ == "__main__":
    main()
