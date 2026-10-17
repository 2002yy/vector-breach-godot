"""Align a VRF 20.1 map by its root transform, preserving meshes and PNG bytes.

Avoid a large Blender round trip: only the scene root and shared-light ownership
change. No mesh decimation, UV rebuild, texture recompression or material rewrite.
"""

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path
from urllib.parse import unquote


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Existing output preserved; choose a new path")
    scene = json.loads(args.source.read_text(encoding="utf-8"))
    units = json.loads(args.metadata.read_text(encoding="utf-8"))["units"]
    scale = float(units["sourceToWebScale"])
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("Invalid alignment metadata scale")
    offset = [float(v) * 0.0254 / scale for v in units["sourceToWebOffset"]]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for item in scene.get("buffers", []) + scene.get("images", []):
        uri = item.get("uri", "")
        if not uri or uri.startswith("data:") or uri in hashes:
            continue
        relative = Path(unquote(uri))
        source = (args.source.parent / relative).resolve()
        destination = (args.output.parent / relative).resolve()
        if not source.is_relative_to(
            args.source.parent.resolve()
        ) or not destination.is_relative_to(args.output.parent.resolve()):
            raise ValueError("Only local contained glTF dependencies are supported")
        if destination.exists():
            raise FileExistsError("Existing dependency preserved: " + str(destination))
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        source_hash = sha256(source)
        if sha256(destination) != source_hash:
            raise ValueError("Copy verification failed")
        hashes[uri] = source_hash
    # The game owns its sun/sky. Keep source lights in the unchanged raw export.
    lights = len(
        scene.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", [])
    )
    scene.get("extensions", {}).pop("KHR_lights_punctual", None)
    for field in ["extensionsUsed", "extensionsRequired"]:
        if field in scene:
            scene[field] = [v for v in scene[field] if v != "KHR_lights_punctual"]
    for node in scene.get("nodes", []):
        node.get("extensions", {}).pop("KHR_lights_punctual", None)
    for entry in scene["scenes"]:
        index = len(scene["nodes"])
        scene["nodes"].append(
            {
                "name": "OfficialSourceAlignment",
                "translation": offset,
                "rotation": [0, math.sin(math.pi / 4), 0, math.cos(math.pi / 4)],
                "children": entry["nodes"],
            }
        )
        entry["nodes"] = [index]
    args.output.write_text(json.dumps(scene, separators=(",", ":")), encoding="utf-8")
    receipt = {
        "source_sha256": sha256(args.source),
        "output_sha256": sha256(args.output),
        "alignment_metadata_sha256": sha256(args.metadata),
        "source_exporter": "Source2Viewer-CLI 20.1",
        "meshes": len(scene.get("meshes", [])),
        "materials": len(scene.get("materials", [])),
        "images": len(scene.get("images", [])),
        "decimation": False,
        "texture_recompression": False,
        "source_lights_owned_by_game": lights,
        "copied_dependency_sha256": hashes,
    }
    args.output.with_suffix(".receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "OFFICIAL_GLTF_ALIGNED",
        json.dumps(
            {k: v for k, v in receipt.items() if k != "copied_dependency_sha256"}
        ),
    )


if __name__ == "__main__":
    main()
