"""Install verified private resources and explicitly archive the frozen baseline."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from urllib.parse import unquote


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--level", type=Path, required=True)
    parser.add_argument("--visual", required=True)
    parser.add_argument("--collision", required=True)
    parser.add_argument("--source-vpk", type=Path, required=True)
    parser.add_argument("--expected-sha1", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--replace-frozen-baseline", action="store_true", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    data = json.loads(args.level.read_text(encoding="utf-8"))
    if data["id"] not in ["inferno-classic-local", "mirage-classic-local"]:
        raise ValueError("Unregistered classic map")
    if args.level.resolve() != repo / "data/levels" / (data["id"] + ".json"):
        raise ValueError("Install must explicitly target the authoritative level JSON")
    if args.source_vpk.stem != "de_" + data["id"].split("-")[0]:
        raise ValueError("Wrong official source map")
    for value in [args.visual, args.collision]:
        if not value.startswith("res://assets/local_reference/"):
            raise ValueError("Official assets must stay in the private resource layer")
        path = (repo / value.removeprefix("res://")).resolve()
        if (
            not path.is_relative_to(repo / "assets/local_reference")
            or not path.is_file()
        ):
            raise ValueError("Missing private resource")
        if path.suffix == ".gltf":
            scene = json.loads(path.read_text(encoding="utf-8"))
            for record in scene.get("buffers", []) + scene.get("images", []):
                uri = record.get("uri", "")
                if (
                    uri
                    and not uri.startswith("data:")
                    and not (path.parent / unquote(uri)).is_file()
                ):
                    raise ValueError("Missing exported glTF dependency: " + uri)
    with args.source_vpk.open("rb") as source:
        digest = hashlib.file_digest(source, "sha1").hexdigest()
    if digest != args.expected_sha1.lower():
        raise ValueError("Official VPK does not match the selected Steam manifest")
    baseline = repo / data["match_manifest"].removeprefix("res://")
    if not baseline.resolve().is_relative_to(repo / "data/levels/match-local"):
        raise ValueError("Frozen baseline must be in the private match directory")
    args.backup_dir.mkdir(parents=True, exist_ok=True)
    backups = [
        (args.level, args.backup_dir / "levels" / args.level.name),
        (baseline, args.backup_dir / "match-local" / baseline.name),
    ]
    for source, destination in backups:
        if destination.exists():
            raise FileExistsError("Existing backup preserved: " + str(destination))
    for source, destination in backups:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    previous = data.get("sourceTrace", {})
    data.update(
        designRevision="official-resources-native-physics-v1",
        visual_scene=args.visual,
        runtime_collision_scene=args.collision,
        runtime_collision_from_visual=False,
        reconstructed_materials=False,
        original_reference_materials=True,
        navigationAuthoring="recast",
        hidden_visual_name_contains=["cb_bl_mesh_blocklight", "light_environment"],
        assetNotice="Local research only. Valve map geometry and original textures; Godot materials, lighting and gameplay adaptation.",
    )
    with args.source_vpk.open("rb") as source:
        source_sha = hashlib.file_digest(source, "sha256").hexdigest()
    data["sourceTrace"] = {
        "app": 730,
        "depot": 2347770,
        "manifest": args.manifest,
        "referenceMap": args.source_vpk.stem,
        "vpkSha256": source_sha,
        "originalTextures": True,
        "referenceAssetsCommitted": False,
        "sourceExporter": "Source2Viewer-CLI 20.1",
        "collisionApproximation": False,
        "collisionPolicy": "Undecimated native player solids; grenade-only clips and sky excluded",
        "previousReconstruction": previous,
    }
    args.level.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # The explicit flag authorizes this single archived baseline replacement.
    # Re-author with tools/author_classic_match.gd; runtime never regenerates it.
    baseline.unlink()
    print(
        "OFFICIAL_LEVEL_PREPARED",
        data["id"],
        "frozen baseline archived; explicit re-authoring required",
    )


if __name__ == "__main__":
    main()
