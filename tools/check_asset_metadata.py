from __future__ import annotations

import re
import subprocess
from pathlib import Path, PurePosixPath

from asset_metadata_policy import (
    FLATTENED_SOURCE_EXTENSIONS,
    METADATA_REQUIRED_SOURCE_EXTENSIONS,
    SCHEMA_VERSION,
    load_metadata,
    metadata_path_for_source,
    source_path_for_metadata,
)


ROOT = Path(__file__).resolve().parents[1]
ASSET_ID_RE = re.compile(r"^VB-[A-Z0-9]+(?:-[A-Z0-9]+)*$")
CATEGORIES = {
    "map",
    "character",
    "weapon",
    "prop",
    "environment",
    "ui",
    "audio",
    "vfx",
    "texture",
    "material",
    "other",
}
SOURCE_ROLES = {"canonical_master", "canonical_input"}
ORIGINS = {"project-authored", "acquired", "ai-generated", "mixed", "unknown"}
LICENSE_STATUSES = {"project-owned", "permitted", "restricted", "unknown"}
AI_USAGE = {"none", "assisted", "generated", "unknown"}
UNITS = {"meter", "centimeter", "none", "unknown"}
REVIEW_STATUSES = {"draft", "approved", "legacy-imported", "blocked"}


def tracked_files() -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return {
        item.decode("utf-8").replace("\\", "/")
        for item in result.stdout.split(b"\0")
        if item
    }


def require_enum(
    violations: list[str], metadata_path: str, field_name: str, value: object, allowed: set[str]
) -> None:
    if not isinstance(value, str) or value not in allowed:
        violations.append(
            f"{metadata_path}: {field_name} must be one of {sorted(allowed)}, got {value!r}"
        )


def is_normalized_repo_path(path: str) -> bool:
    if not path or "\\" in path or path.startswith("/"):
        return False
    pure = PurePosixPath(path)
    if pure.is_absolute() or any(part in {"", ".", ".."} for part in pure.parts):
        return False
    return pure.as_posix() == path


def main() -> int:
    tracked = tracked_files()
    source_masters = {
        path
        for path in tracked
        if path.startswith("assets-source/")
        and Path(path).suffix.lower() in METADATA_REQUIRED_SOURCE_EXTENSIONS
    }
    metadata_files = {
        path for path in tracked if path.startswith("assets-source/") and path.endswith(".asset.json")
    }
    violations: list[str] = []

    for source_path in sorted(source_masters):
        metadata_path = metadata_path_for_source(source_path)
        if metadata_path not in metadata_files:
            violations.append(f"missing metadata sidecar for canonical source master: {source_path}")

    seen_asset_ids: dict[str, str] = {}
    for metadata_path in sorted(metadata_files):
        source_path = source_path_for_metadata(metadata_path)
        if source_path is None or source_path not in tracked:
            violations.append(f"{metadata_path}: sidecar source file is missing or untracked")
            continue

        metadata = load_metadata(ROOT, metadata_path)
        if metadata is None:
            violations.append(f"{metadata_path}: invalid JSON object")
            continue

        if metadata.get("schema_version") != SCHEMA_VERSION:
            violations.append(
                f"{metadata_path}: schema_version must be {SCHEMA_VERSION}, got {metadata.get('schema_version')!r}"
            )

        asset_id = metadata.get("asset_id")
        if not isinstance(asset_id, str) or ASSET_ID_RE.fullmatch(asset_id) is None:
            violations.append(f"{metadata_path}: invalid asset_id {asset_id!r}")
        elif asset_id in seen_asset_ids:
            violations.append(
                f"{metadata_path}: duplicate asset_id {asset_id!r}; first used by {seen_asset_ids[asset_id]}"
            )
        else:
            seen_asset_ids[asset_id] = metadata_path

        display_name = metadata.get("display_name")
        if not isinstance(display_name, str) or not display_name.strip():
            violations.append(f"{metadata_path}: display_name must be a non-empty string")

        require_enum(violations, metadata_path, "category", metadata.get("category"), CATEGORIES)
        require_enum(
            violations, metadata_path, "source_role", metadata.get("source_role"), SOURCE_ROLES
        )

        if metadata.get("source_path") != source_path:
            violations.append(
                f"{metadata_path}: source_path must exactly match adjacent source {source_path!r}"
            )

        authoring_tool = metadata.get("authoring_tool")
        if not isinstance(authoring_tool, str) or not authoring_tool.strip():
            violations.append(f"{metadata_path}: authoring_tool must be a non-empty string")

        provenance = metadata.get("provenance")
        if not isinstance(provenance, dict):
            violations.append(f"{metadata_path}: provenance must be an object")
        else:
            require_enum(violations, metadata_path, "provenance.origin", provenance.get("origin"), ORIGINS)
            require_enum(
                violations,
                metadata_path,
                "provenance.license_status",
                provenance.get("license_status"),
                LICENSE_STATUSES,
            )
            require_enum(
                violations,
                metadata_path,
                "provenance.ai_usage",
                provenance.get("ai_usage"),
                AI_USAGE,
            )

        runtime_outputs = metadata.get("runtime_outputs")
        if not isinstance(runtime_outputs, list):
            violations.append(
                f"{metadata_path}: runtime_outputs must be a list of tracked repository paths under assets/"
            )
        else:
            seen_outputs: set[str] = set()
            for item in runtime_outputs:
                if not isinstance(item, str) or not is_normalized_repo_path(item):
                    violations.append(
                        f"{metadata_path}: runtime_outputs entries must be normalized repository paths, got {item!r}"
                    )
                    continue
                if not item.startswith("assets/"):
                    violations.append(
                        f"{metadata_path}: runtime output must live under assets/: {item!r}"
                    )
                    continue
                if item not in tracked:
                    violations.append(
                        f"{metadata_path}: runtime output is missing or untracked: {item!r}"
                    )
                if item in seen_outputs:
                    violations.append(
                        f"{metadata_path}: duplicate runtime output path: {item!r}"
                    )
                seen_outputs.add(item)

        scale = metadata.get("scale")
        if not isinstance(scale, dict):
            violations.append(f"{metadata_path}: scale must be an object")
        else:
            require_enum(violations, metadata_path, "scale.unit", scale.get("unit"), UNITS)

        review = metadata.get("review")
        if not isinstance(review, dict):
            violations.append(f"{metadata_path}: review must be an object")
        else:
            require_enum(
                violations, metadata_path, "review.status", review.get("status"), REVIEW_STATUSES
            )

        suffix = Path(source_path).suffix.lower()
        source_role = metadata.get("source_role")
        allow_flattened = metadata.get("allow_flattened_source", False)
        if source_path in source_masters and source_role != "canonical_master":
            violations.append(
                f"{metadata_path}: editable master must use source_role='canonical_master'"
            )
        if allow_flattened:
            if suffix not in FLATTENED_SOURCE_EXTENSIONS:
                violations.append(
                    f"{metadata_path}: allow_flattened_source is only valid for flattened source formats"
                )
            if source_role != "canonical_input":
                violations.append(
                    f"{metadata_path}: flattened source exception requires source_role='canonical_input'"
                )
            if not isinstance(provenance, dict) or provenance.get("origin") in (None, "unknown"):
                violations.append(
                    f"{metadata_path}: flattened source exception requires known provenance.origin"
                )
            if not isinstance(provenance, dict) or provenance.get("license_status") not in {
                "project-owned",
                "permitted",
            }:
                violations.append(
                    f"{metadata_path}: flattened source exception requires license_status project-owned/permitted"
                )

    if violations:
        print("ASSET_METADATA_POLICY=FAIL")
        for violation in violations:
            print(f"- {violation}")
        return 1

    print("ASSET_METADATA_POLICY=PASS")
    print(f"canonical_source_masters={len(source_masters)}")
    print(f"metadata_sidecars={len(metadata_files)}")
    print(f"metadata_coverage={len(source_masters)}/{len(source_masters)}")
    print(f"unique_asset_ids={len(seen_asset_ids)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
