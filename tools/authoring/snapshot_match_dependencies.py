"""Observe local match input bytes now; never backdate this as launch evidence."""

import argparse
import configparser
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from typing import Any

LEVELS = (
    "dustline-depths-original-local",
    "mirage-classic-local",
    "inferno-classic-local",
)


def snapshot(root) -> dict[str, Any]:
    root = Path(root).resolve(strict=True)
    files = {}
    maps = {}

    def read(resource):
        if not isinstance(resource, str) or not resource.startswith("res://"):
            raise ValueError("expected res:// dependency")
        relative = resource[6:]
        if "\\" in relative or ".." in relative.split("/"):
            raise ValueError("unsafe dependency path")
        path = (root / relative).resolve(strict=True)
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("dependency outside project or not a file")
        before = path.stat()
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError("dependency changed during hashing")
        files[resource] = dict(sha256=digest, bytes=after.st_size)
        return path

    def document(resource):
        return json.loads(read(resource).read_text(encoding="utf-8-sig"))

    for level in LEVELS:
        level_path = f"res://data/levels/{level}.json"
        data = document(level_path)
        if data.get("id") != level:
            raise ValueError("level identity mismatch")
        manifest_path = data.get(
            "match_manifest", "res://data/levels/match-local/dustline.json"
        )
        manifest = document(manifest_path)
        source = data.get("runtime_collision_scene", data.get("visual_scene"))
        read(source)
        if manifest.get("schema") != 1 or manifest.get("collision_path") != source:
            raise ValueError("manifest collision identity mismatch")
        if manifest.get("collision_sha256") != files[source]["sha256"]:
            raise ValueError("collision SHA mismatch")
        if (
            manifest.get("level_sha256", {}).get(level_path)
            != files[level_path]["sha256"]
        ):
            raise ValueError("level SHA mismatch")
        layout = manifest["layout"]
        if not layout.get("navigationGraph", {}).get("points") or not layout.get(
            "navigationGraph", {}
        ).get("links"):
            raise ValueError("missing navigation")
        if len(layout.get("objectives", [])) != 2 or any(
            len(layout.get("matchSpawns", {}).get(side, [])) != 5
            for side in ("T", "CT")
        ):
            raise ValueError("invalid objectives/spawns")
        sidecar = source + ".import"
        config = configparser.ConfigParser(interpolation=None, strict=False)
        config.read_string(read(sidecar).read_text(encoding="utf-8-sig"))
        compiled = json.loads(config["remap"]["path"])
        if not compiled.startswith("res://.godot/imported/") or not compiled.endswith(
            ".scn"
        ):
            raise ValueError("invalid compiled remap")
        read(compiled)
        cache = (
            "res://assets/local_reference/collision_cache/"
            + hashlib.sha256(source.encode()).hexdigest()
            + ".res"
        )
        # Missing cache is a supported runtime fallback; partial/stale caches fail this audit.
        cache_file = root / cache[6:]
        cache_receipt = root / (cache[6:] + ".json")
        cache_status = "absent_runtime_fallback"
        if cache_file.exists() or cache_receipt.exists():
            read(cache)
            receipt = document(cache + ".json")
            expected = dict(
                version=1,
                source=source,
                source_sha256=files[source]["sha256"],
                import_sha256=files[sidecar]["sha256"],
                cache_sha256=files[cache]["sha256"],
            )
            if any(receipt.get(key) != value for key, value in expected.items()):
                raise ValueError("collision cache SHA/identity mismatch")
            cache_status = "byte_identity_verified_engine_checked_by_runtime"
        maps[level] = dict(
            manifest=manifest_path,
            source=source,
            compiled=compiled,
            cache_status=cache_status,
        )
    return dict(
        schema=1,
        observed_utc=datetime.now(timezone.utc).isoformat(),
        root=str(root),
        files=files,
        maps=maps,
        limits=[
            "Observation starts now; no claim about earlier launches.",
            "Complements tracked source fingerprint; does not replace it.",
            "Hashes imported collision and cache bytes; runtime validates engine/cache shape semantics.",
            "Visual textures are outside this gameplay-input snapshot.",
        ],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = snapshot(args.root)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )
    print(
        json.dumps(
            {"files": len(result["files"]), "observed_utc": result["observed_utc"]}
        )
    )
