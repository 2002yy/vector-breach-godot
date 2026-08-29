from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Iterable

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
GEOMETRY_TYPES = {"MESH", "ARMATURE"}
UNIT_SCALE_EPSILON = 1e-4
NONZERO_SCALE_EPSILON = 1e-8


def _script_args() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _arg_value(name: str) -> str | None:
    args = _script_args()
    try:
        index = args.index(name)
    except ValueError:
        return None
    if index + 1 >= len(args):
        return None
    return args[index + 1]


def _repo_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(PROJECT_ROOT.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _finite(values: Iterable[float]) -> bool:
    return all(math.isfinite(float(value)) for value in values)


def _packed_image(image: bpy.types.Image) -> bool:
    if getattr(image, "packed_file", None) is not None:
        return True
    packed_files = getattr(image, "packed_files", None)
    return packed_files is not None and len(packed_files) > 0


def _safe_name(kind: str, name: str, violations: list[str]) -> None:
    if not name or name != name.strip():
        violations.append(f"{kind} has an empty or whitespace-padded name: {name!r}")
        return
    if "/" in name or "\\" in name:
        violations.append(f"{kind} name contains a path separator: {name!r}")
    if any(ord(char) < 32 or ord(char) == 127 for char in name):
        violations.append(f"{kind} name contains a control character: {name!r}")


def validate_loaded_asset(
    metadata_path: Path | None = None,
    logical_source_path: Path | None = None,
) -> dict:
    violations: list[str] = []
    opened_blend_path = Path(bpy.data.filepath).resolve() if bpy.data.filepath else None
    source_path = logical_source_path.resolve() if logical_source_path is not None else opened_blend_path

    if opened_blend_path is None:
        violations.append("opened Blender file has no filepath")

    if source_path is None:
        violations.append("canonical Blender source path is unknown")
    else:
        try:
            relative_source = source_path.relative_to(PROJECT_ROOT.resolve()).as_posix()
        except ValueError:
            relative_source = source_path.as_posix()
            violations.append(f"canonical Blender source is outside repository: {relative_source}")
        else:
            if not relative_source.startswith("assets-source/blender/"):
                violations.append(
                    f"canonical Blender source is outside assets-source/blender/: {relative_source}"
                )

        if metadata_path is None:
            metadata_path = Path(str(source_path) + ".asset.json")

    metadata: dict | None = None
    if metadata_path is not None:
        metadata_path = metadata_path.resolve()
        try:
            value = json.loads(metadata_path.read_text(encoding="utf-8"))
            metadata = value if isinstance(value, dict) else None
        except (OSError, json.JSONDecodeError) as exc:
            violations.append(f"metadata sidecar cannot be loaded: {_repo_path(metadata_path)} ({exc})")
        else:
            if metadata is None:
                violations.append(f"metadata sidecar must contain a JSON object: {_repo_path(metadata_path)}")

    if metadata is not None and source_path is not None:
        metadata_source = metadata.get("source_path")
        if not isinstance(metadata_source, str) or not metadata_source:
            violations.append("metadata source_path must be a non-empty string")
        else:
            expected = (PROJECT_ROOT / metadata_source).resolve()
            if expected != source_path:
                violations.append(
                    "metadata source_path does not match canonical Blender source: "
                    f"{metadata_source!r} != {_repo_path(source_path)!r}"
                )

    for kind, datablocks in (
        ("object", bpy.data.objects),
        ("collection", bpy.data.collections),
        ("material", bpy.data.materials),
    ):
        for datablock in datablocks:
            _safe_name(kind, datablock.name, violations)

    missing_textures: list[str] = []
    for image in bpy.data.images:
        if image.source != "FILE" or _packed_image(image):
            continue
        raw_path = image.filepath
        if not raw_path:
            missing_textures.append(f"{image.name}: empty filepath")
            continue
        resolved = Path(bpy.path.abspath(raw_path)).resolve()
        if not resolved.is_file():
            missing_textures.append(f"{image.name}: {_repo_path(resolved)}")
    for item in missing_textures:
        violations.append(f"missing external texture: {item}")

    checked_geometry = 0
    for obj in bpy.data.objects:
        transform_values = tuple(obj.location) + tuple(obj.rotation_euler) + tuple(obj.scale)
        if not _finite(transform_values):
            violations.append(f"object transform contains non-finite values: {obj.name!r}")
            continue

        if obj.type not in GEOMETRY_TYPES:
            continue
        checked_geometry += 1

        scale = tuple(float(value) for value in obj.scale)
        if any(abs(value) <= NONZERO_SCALE_EPSILON for value in scale):
            violations.append(f"geometry object has zero/near-zero scale: {obj.name!r} {scale!r}")
        if any(value < 0.0 for value in scale):
            violations.append(f"geometry object has negative/mirrored scale: {obj.name!r} {scale!r}")
        if any(abs(value - 1.0) > UNIT_SCALE_EPSILON for value in scale):
            violations.append(f"geometry object has unapplied scale: {obj.name!r} {scale!r}")

        determinant = float(obj.matrix_world.to_3x3().determinant())
        if not math.isfinite(determinant) or abs(determinant) <= NONZERO_SCALE_EPSILON:
            violations.append(
                f"geometry object has a singular/non-finite world transform: {obj.name!r} determinant={determinant!r}"
            )

    summary = {
        "source": _repo_path(source_path) if source_path is not None else None,
        "opened_blend": _repo_path(opened_blend_path) if opened_blend_path is not None else None,
        "metadata": _repo_path(metadata_path) if metadata_path is not None else None,
        "objects": len(bpy.data.objects),
        "geometry_objects": checked_geometry,
        "materials": len(bpy.data.materials),
        "images": len(bpy.data.images),
        "missing_external_textures": len(missing_textures),
        "violations": len(violations),
    }
    return {"violations": violations, "summary": summary}


def main() -> int:
    metadata_arg = _arg_value("--metadata")
    source_arg = _arg_value("--source")
    metadata_path = (PROJECT_ROOT / metadata_arg).resolve() if metadata_arg else None
    logical_source_path = (PROJECT_ROOT / source_arg).resolve() if source_arg else None
    result = validate_loaded_asset(metadata_path, logical_source_path)
    violations = result["violations"]

    if violations:
        print("BLENDER_ASSET_VALIDATION=FAIL")
        for violation in violations:
            print(f"- {violation}")
        print("BLENDER_ASSET_SUMMARY=" + json.dumps(result["summary"], sort_keys=True))
        return 1

    print("BLENDER_ASSET_VALIDATION=PASS")
    print("BLENDER_ASSET_SUMMARY=" + json.dumps(result["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
