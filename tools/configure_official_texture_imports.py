"""Use desktop 3D texture compression/mipmaps while preserving source PNG bytes."""

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from urllib.parse import unquote


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    args = parser.parse_args()
    scene = json.loads(args.visual.read_text(encoding="utf-8"))
    receipt_path = args.visual.with_suffix(".receipt.json")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    settings = {
        "compress/mode": "2",
        "compress/high_quality": "true",
        "mipmaps/generate": "true",
    }
    changed = []
    for uri in sorted({record.get("uri", "") for record in scene.get("images", [])}):
        if not uri or uri.startswith("data:"):
            continue
        source = (args.visual.parent / unquote(uri)).resolve()
        if not source.is_relative_to(args.visual.parent.resolve()):
            raise ValueError("Texture outside map resource directory")
        with source.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != receipt["copied_dependency_sha256"][uri]:
            raise ValueError("Source texture changed since verification: " + uri)
        metadata = source.with_name(source.name + ".import")
        text = metadata.read_text(encoding="utf-8")
        updated = text
        for key, value in settings.items():
            updated, count = re.subn(
                r"(?m)^" + re.escape(key) + r"=.*$", key + "=" + value, updated
            )
            if count != 1:
                raise ValueError("Missing or ambiguous import setting: " + key)
        if updated == text:
            continue
        backup = args.backup_dir / metadata.name
        if backup.exists():
            raise FileExistsError("Existing import backup preserved")
        args.backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(metadata, backup)
        metadata.write_text(updated, encoding="utf-8")
        changed.append(uri)
    receipt["gpu_import"] = {
        "format": "desktop high-quality VRAM compression",
        "mipmaps": True,
        "source_png_bytes_unchanged": True,
    }
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print("OFFICIAL_TEXTURE_IMPORTS_CONFIGURED", len(changed))


if __name__ == "__main__":
    main()
