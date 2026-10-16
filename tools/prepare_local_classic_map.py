"""Prepare local JSON from separately reviewed placement hints, without embedding
Valve-derived map coordinates in public code. Existing baselines are preserved.

Hints JSON: spawnHints {T:[x,y,z], CT:[x,y,z]}, spawnYawDegrees {T:n, CT:n},
landmarks [{name:site-a/site-b,x:n,y:n,z:n,h:n}]. All coordinates are meters.
"""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", choices=["inferno", "mirage"], required=True)
    parser.add_argument("--hints", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError(
            "Existing local level preserved; choose a new output and review its diff"
        )
    hints = json.loads(args.hints.read_text(encoding="utf-8"))
    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    if {record["name"] for record in hints["landmarks"]} != {"site-a", "site-b"}:
        raise ValueError("Two reviewed objectives are required")
    start = hints["spawnHints"]["T"]
    site = next(item for item in hints["landmarks"] if item["name"] == "site-a")
    map_id = f"{args.map}-classic-local"
    root = f"res://assets/local_reference/classic_maps/{args.map}"
    data = {
        "id": map_id,
        "name": "炼狱小镇 Inferno" if args.map == "inferno" else "荒漠迷城 Mirage",
        "designRevision": "native-geometry-reconstructed-materials-v1",
        "visual_scene": root + "/map.glb",
        "runtime_collision_scene": root + "/collision.glb",
        "runtime_collision_from_visual": False,
        "reconstructed_materials": True,
        "localOnly": True,
        "match_manifest": f"res://data/levels/match-local/{map_id}.json",
        "navigationAuthoring": "recast",
        "buildOptions": {"arena_floor_enabled": False, "arena_bounds_enabled": False},
        "arenaSize": 150,
        "arenaSizeX": 150,
        "arenaSizeZ": 150,
        "boundaryHeight": 25,
        "start": [start[0], start[2]],
        "startHeight": start[1],
        "startYawDegrees": hints["spawnYawDegrees"]["T"],
        "exit": [site["x"], site["z"]],
        "exitHeight": site["y"],
        "enemies": 10,
        "sourceTrace": {
            "repository": "https://github.com/sliuhaob/mirage-utility-lab",
            "commit": "776f381d4a6e1b606190cbc9ab7430e68a03572f",
            "sourceVpkSha256": metadata.get("sourceSha256"),
            "referenceAssetsCommitted": False,
            "originalTextures": False,
            "metersPerSourceUnit": 0.0254,
            "collisionSource": "https://github.com/pnxenopoulos/awpy-data/releases/tag/2000933",
            "collisionApproximation": "Awpy world physics; grid simplified, contact audit required",
        },
        "assetNotice": "Local research only. Valve-derived geometry; reconstructed CC0 materials, not original textures.",
        "environment": {"ambient_light_energy": 0.45, "sun_energy": 0.8},
        "lights": {"points": [], "colors": []},
        "routes": {},
        "spawnPoints": [],
    }
    for key in ["spawnHints", "spawnYawDegrees", "landmarks"]:
        data[key] = hints[key]
    for key in [
        "emptyRoutes",
        "drops",
        "walls",
        "covers",
        "floors",
        "stairs",
        "ramps",
        "catwalks",
        "overheads",
        "obstacles",
    ]:
        data[key] = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("LOCAL_LEVEL_PREPARED=" + str(args.output))


if __name__ == "__main__":
    main()
