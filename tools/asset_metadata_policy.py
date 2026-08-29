from __future__ import annotations

import json
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
SOURCE_MASTER_EXTENSIONS = {".blend", ".blend1", ".kra", ".psd"}
FLATTENED_SOURCE_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".ktx",
    ".ktx2",
    ".dds",
}
KNOWN_LICENSE_STATUSES = {"project-owned", "permitted"}


def metadata_path_for_source(source_path: str) -> str:
    return source_path + ".asset.json"


def source_path_for_metadata(metadata_path: str) -> str | None:
    suffix = ".asset.json"
    if not metadata_path.endswith(suffix):
        return None
    return metadata_path[: -len(suffix)]


def load_metadata(root: Path, metadata_path: str) -> dict[str, Any] | None:
    try:
        value = json.loads((root / metadata_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def allows_flattened_source(root: Path, source_path: str, tracked: set[str]) -> bool:
    metadata_path = metadata_path_for_source(source_path)
    if metadata_path not in tracked:
        return False
    metadata = load_metadata(root, metadata_path)
    if metadata is None:
        return False
    provenance = metadata.get("provenance")
    if not isinstance(provenance, dict):
        return False
    return (
        metadata.get("schema_version") == SCHEMA_VERSION
        and metadata.get("source_path") == source_path
        and metadata.get("source_role") == "canonical_input"
        and metadata.get("allow_flattened_source") is True
        and provenance.get("origin") not in (None, "unknown")
        and provenance.get("license_status") in KNOWN_LICENSE_STATUSES
    )
