#!/usr/bin/env python3
"""Audit freshly rebuilt Blender-owned GLB runtime assets without imposing budgets.

Step 15 starts with measurement, not guessed thresholds. This script discovers GLB
runtime outputs from canonical Blender sidecars, validates basic GLB/glTF structural
integrity, and writes deterministic baseline metrics for later contract design.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets-source" / "blender"
REPORT_PATH = ROOT / "reports" / "runtime_asset_baseline.json"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
TRIANGLES = 4
TRIANGLE_STRIP = 5
TRIANGLE_FAN = 6


class AuditError(RuntimeError):
    pass


def _require_index(value: Any, size: int, label: str) -> None:
    if not isinstance(value, int) or value < 0 or value >= size:
        raise AuditError(f"{label} index out of range: {value!r} (size={size})")


def _finite_values(value: Any, label: str) -> None:
    if not isinstance(value, list):
        raise AuditError(f"{label} must be an array")
    for item in value:
        if not isinstance(item, (int, float)) or isinstance(item, bool) or not math.isfinite(float(item)):
            raise AuditError(f"{label} contains non-finite/non-numeric value: {item!r}")


def _load_glb(path: Path) -> tuple[dict[str, Any], bytes, int]:
    data = path.read_bytes()
    if len(data) < 20:
        raise AuditError(f"GLB too small: {path} ({len(data)} bytes)")

    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise AuditError(f"invalid GLB magic for {path}: {magic!r}")
    if version != 2:
        raise AuditError(f"unsupported GLB version for {path}: {version}")
    if declared_length != len(data):
        raise AuditError(
            f"GLB declared length mismatch for {path}: declared={declared_length} actual={len(data)}"
        )

    offset = 12
    chunks: list[tuple[int, bytes]] = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise AuditError(f"truncated GLB chunk header in {path} at offset {offset}")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        end = offset + chunk_length
        if end > len(data):
            raise AuditError(f"truncated GLB chunk in {path}: type={chunk_type:#x}")
        if chunk_length % 4 != 0:
            raise AuditError(f"unaligned GLB chunk in {path}: length={chunk_length}")
        chunks.append((chunk_type, data[offset:end]))
        offset = end

    if not chunks or chunks[0][0] != JSON_CHUNK:
        raise AuditError(f"first GLB chunk must be JSON in {path}")
    if sum(1 for chunk_type, _ in chunks if chunk_type == JSON_CHUNK) != 1:
        raise AuditError(f"GLB must contain exactly one JSON chunk: {path}")

    json_bytes = chunks[0][1].rstrip(b" \t\r\n\x00")
    try:
        gltf = json.loads(json_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AuditError(f"invalid glTF JSON in {path}: {exc}") from exc
    if not isinstance(gltf, dict):
        raise AuditError(f"glTF JSON root must be an object: {path}")

    bin_chunks = [chunk for chunk_type, chunk in chunks if chunk_type == BIN_CHUNK]
    if len(bin_chunks) > 1:
        raise AuditError(f"GLB contains multiple BIN chunks: {path}")
    return gltf, (bin_chunks[0] if bin_chunks else b""), len(data)


def _triangle_count(mode: int, element_count: int) -> int:
    if mode == TRIANGLES:
        return element_count // 3
    if mode in (TRIANGLE_STRIP, TRIANGLE_FAN):
        return max(0, element_count - 2)
    return 0


def _validate_and_measure(asset_id: str, category: str, rel_path: str) -> dict[str, Any]:
    path = ROOT / rel_path
    if not path.is_file():
        raise AuditError(f"runtime output missing: {rel_path}")

    gltf, bin_chunk, file_size = _load_glb(path)
    asset = gltf.get("asset")
    if not isinstance(asset, dict) or asset.get("version") != "2.0":
        raise AuditError(f"glTF asset.version must be '2.0': {rel_path}")

    scenes = gltf.get("scenes", [])
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    materials = gltf.get("materials", [])
    textures = gltf.get("textures", [])
    images = gltf.get("images", [])
    samplers = gltf.get("samplers", [])
    skins = gltf.get("skins", [])
    animations = gltf.get("animations", [])
    accessors = gltf.get("accessors", [])
    buffer_views = gltf.get("bufferViews", [])
    buffers = gltf.get("buffers", [])

    named_lists = {
        "scenes": scenes,
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "textures": textures,
        "images": images,
        "samplers": samplers,
        "skins": skins,
        "animations": animations,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": buffers,
    }
    for name, value in named_lists.items():
        if not isinstance(value, list):
            raise AuditError(f"{rel_path}: {name} must be an array")

    default_scene = gltf.get("scene")
    if default_scene is not None:
        _require_index(default_scene, len(scenes), f"{rel_path}: scene")

    for scene_index, scene in enumerate(scenes):
        if not isinstance(scene, dict):
            raise AuditError(f"{rel_path}: scene[{scene_index}] must be an object")
        for node_index in scene.get("nodes", []):
            _require_index(node_index, len(nodes), f"{rel_path}: scene[{scene_index}].nodes")

    for node_index, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise AuditError(f"{rel_path}: node[{node_index}] must be an object")
        for child in node.get("children", []):
            _require_index(child, len(nodes), f"{rel_path}: node[{node_index}].children")
        if "mesh" in node:
            _require_index(node["mesh"], len(meshes), f"{rel_path}: node[{node_index}].mesh")
        if "skin" in node:
            _require_index(node["skin"], len(skins), f"{rel_path}: node[{node_index}].skin")
        for transform_key in ("matrix", "translation", "rotation", "scale"):
            if transform_key in node:
                _finite_values(node[transform_key], f"{rel_path}: node[{node_index}].{transform_key}")

    for buffer_index, buffer in enumerate(buffers):
        if not isinstance(buffer, dict):
            raise AuditError(f"{rel_path}: buffer[{buffer_index}] must be an object")
        byte_length = buffer.get("byteLength")
        if not isinstance(byte_length, int) or byte_length < 0:
            raise AuditError(f"{rel_path}: buffer[{buffer_index}].byteLength invalid")
        if buffer_index == 0 and "uri" not in buffer and byte_length > len(bin_chunk):
            raise AuditError(
                f"{rel_path}: BIN chunk shorter than buffer[0] ({len(bin_chunk)} < {byte_length})"
            )

    for view_index, view in enumerate(buffer_views):
        if not isinstance(view, dict):
            raise AuditError(f"{rel_path}: bufferView[{view_index}] must be an object")
        buffer_index = view.get("buffer")
        _require_index(buffer_index, len(buffers), f"{rel_path}: bufferView[{view_index}].buffer")
        byte_offset = view.get("byteOffset", 0)
        byte_length = view.get("byteLength")
        if not isinstance(byte_offset, int) or byte_offset < 0 or not isinstance(byte_length, int) or byte_length < 0:
            raise AuditError(f"{rel_path}: invalid bufferView[{view_index}] byte range")
        if byte_offset + byte_length > buffers[buffer_index]["byteLength"]:
            raise AuditError(f"{rel_path}: bufferView[{view_index}] exceeds declared buffer bounds")
        stride = view.get("byteStride")
        if stride is not None and (not isinstance(stride, int) or stride <= 0):
            raise AuditError(f"{rel_path}: invalid bufferView[{view_index}].byteStride")

    for accessor_index, accessor in enumerate(accessors):
        if not isinstance(accessor, dict):
            raise AuditError(f"{rel_path}: accessor[{accessor_index}] must be an object")
        count = accessor.get("count")
        if not isinstance(count, int) or count < 0:
            raise AuditError(f"{rel_path}: accessor[{accessor_index}].count invalid")
        if "bufferView" in accessor:
            _require_index(
                accessor["bufferView"], len(buffer_views), f"{rel_path}: accessor[{accessor_index}].bufferView"
            )
        for extrema in ("min", "max"):
            if extrema in accessor:
                _finite_values(accessor[extrema], f"{rel_path}: accessor[{accessor_index}].{extrema}")
        sparse = accessor.get("sparse")
        if sparse is not None:
            if not isinstance(sparse, dict):
                raise AuditError(f"{rel_path}: accessor[{accessor_index}].sparse must be an object")
            for sparse_part in ("indices", "values"):
                part = sparse.get(sparse_part)
                if not isinstance(part, dict) or "bufferView" not in part:
                    raise AuditError(f"{rel_path}: malformed sparse {sparse_part} in accessor[{accessor_index}]")
                _require_index(
                    part["bufferView"],
                    len(buffer_views),
                    f"{rel_path}: accessor[{accessor_index}].sparse.{sparse_part}.bufferView",
                )

    primitive_count = 0
    vertex_count = 0
    triangle_count = 0
    for mesh_index, mesh in enumerate(meshes):
        if not isinstance(mesh, dict) or not isinstance(mesh.get("primitives"), list):
            raise AuditError(f"{rel_path}: mesh[{mesh_index}].primitives must be an array")
        for primitive_index, primitive in enumerate(mesh["primitives"]):
            if not isinstance(primitive, dict):
                raise AuditError(f"{rel_path}: mesh[{mesh_index}].primitive[{primitive_index}] invalid")
            primitive_count += 1
            attributes = primitive.get("attributes", {})
            if not isinstance(attributes, dict):
                raise AuditError(f"{rel_path}: primitive attributes must be an object")
            for semantic, accessor_index in attributes.items():
                _require_index(
                    accessor_index,
                    len(accessors),
                    f"{rel_path}: mesh[{mesh_index}].primitive[{primitive_index}].attributes[{semantic}]",
                )
            if "material" in primitive:
                _require_index(
                    primitive["material"], len(materials), f"{rel_path}: mesh[{mesh_index}].material"
                )
            element_count = 0
            if "indices" in primitive:
                _require_index(
                    primitive["indices"], len(accessors), f"{rel_path}: mesh[{mesh_index}].indices"
                )
                element_count = accessors[primitive["indices"]]["count"]
            elif "POSITION" in attributes:
                element_count = accessors[attributes["POSITION"]]["count"]
            if "POSITION" in attributes:
                vertex_count += accessors[attributes["POSITION"]]["count"]
            triangle_count += _triangle_count(primitive.get("mode", TRIANGLES), element_count)

    for image_index, image in enumerate(images):
        if not isinstance(image, dict):
            raise AuditError(f"{rel_path}: image[{image_index}] must be an object")
        if "bufferView" in image:
            _require_index(image["bufferView"], len(buffer_views), f"{rel_path}: image[{image_index}].bufferView")

    for texture_index, texture in enumerate(textures):
        if not isinstance(texture, dict):
            raise AuditError(f"{rel_path}: texture[{texture_index}] must be an object")
        if "source" in texture:
            _require_index(texture["source"], len(images), f"{rel_path}: texture[{texture_index}].source")
        if "sampler" in texture:
            _require_index(texture["sampler"], len(samplers), f"{rel_path}: texture[{texture_index}].sampler")

    total_joints = 0
    for skin_index, skin in enumerate(skins):
        if not isinstance(skin, dict) or not isinstance(skin.get("joints"), list):
            raise AuditError(f"{rel_path}: skin[{skin_index}].joints must be an array")
        total_joints += len(skin["joints"])
        for joint in skin["joints"]:
            _require_index(joint, len(nodes), f"{rel_path}: skin[{skin_index}].joints")
        if "skeleton" in skin:
            _require_index(skin["skeleton"], len(nodes), f"{rel_path}: skin[{skin_index}].skeleton")
        if "inverseBindMatrices" in skin:
            _require_index(
                skin["inverseBindMatrices"],
                len(accessors),
                f"{rel_path}: skin[{skin_index}].inverseBindMatrices",
            )

    animation_channels = 0
    for animation_index, animation in enumerate(animations):
        if not isinstance(animation, dict):
            raise AuditError(f"{rel_path}: animation[{animation_index}] must be an object")
        anim_samplers = animation.get("samplers", [])
        channels = animation.get("channels", [])
        if not isinstance(anim_samplers, list) or not isinstance(channels, list):
            raise AuditError(f"{rel_path}: animation[{animation_index}] samplers/channels invalid")
        for sampler_index, sampler in enumerate(anim_samplers):
            if not isinstance(sampler, dict):
                raise AuditError(f"{rel_path}: animation sampler invalid")
            _require_index(
                sampler.get("input"), len(accessors), f"{rel_path}: animation[{animation_index}].sampler[{sampler_index}].input"
            )
            _require_index(
                sampler.get("output"), len(accessors), f"{rel_path}: animation[{animation_index}].sampler[{sampler_index}].output"
            )
        animation_channels += len(channels)
        for channel_index, channel in enumerate(channels):
            if not isinstance(channel, dict):
                raise AuditError(f"{rel_path}: animation channel invalid")
            _require_index(
                channel.get("sampler"),
                len(anim_samplers),
                f"{rel_path}: animation[{animation_index}].channel[{channel_index}].sampler",
            )
            target = channel.get("target")
            if not isinstance(target, dict):
                raise AuditError(f"{rel_path}: animation channel target invalid")
            if "node" in target:
                _require_index(
                    target["node"], len(nodes), f"{rel_path}: animation[{animation_index}].channel[{channel_index}].target.node"
                )

    extensions_used = gltf.get("extensionsUsed", [])
    extensions_required = gltf.get("extensionsRequired", [])
    if not isinstance(extensions_used, list) or not isinstance(extensions_required, list):
        raise AuditError(f"{rel_path}: extension declarations must be arrays")

    return {
        "asset_id": asset_id,
        "category": category,
        "path": rel_path,
        "file_size_bytes": file_size,
        "generator": asset.get("generator", ""),
        "scenes": len(scenes),
        "nodes": len(nodes),
        "meshes": len(meshes),
        "primitives": primitive_count,
        "vertices_by_primitive": vertex_count,
        "triangles": triangle_count,
        "materials": len(materials),
        "textures": len(textures),
        "images": len(images),
        "skins": len(skins),
        "skin_joints_total": total_joints,
        "animations": len(animations),
        "animation_channels": animation_channels,
        "accessors": len(accessors),
        "buffer_views": len(buffer_views),
        "buffers": len(buffers),
        "extensions_used": sorted(str(value) for value in extensions_used),
        "extensions_required": sorted(str(value) for value in extensions_required),
    }


def _discover_jobs() -> list[tuple[str, str, str]]:
    jobs: list[tuple[str, str, str]] = []
    for sidecar in sorted(SOURCE_ROOT.rglob("*.asset.json")):
        metadata = json.loads(sidecar.read_text(encoding="utf-8"))
        if not isinstance(metadata, dict) or metadata.get("authoring_tool") != "Blender":
            continue
        asset_id = metadata.get("asset_id")
        category = metadata.get("category")
        outputs = metadata.get("runtime_outputs")
        if not isinstance(asset_id, str) or not asset_id or not isinstance(category, str) or not category:
            raise AuditError(f"invalid Blender metadata identity: {sidecar.relative_to(ROOT).as_posix()}")
        if not isinstance(outputs, list):
            raise AuditError(f"runtime_outputs must be an array: {sidecar.relative_to(ROOT).as_posix()}")
        for output in outputs:
            if isinstance(output, str) and output.lower().endswith(".glb"):
                jobs.append((asset_id, category, output))
    if not jobs:
        raise AuditError("no Blender-owned GLB runtime outputs discovered")
    paths = [job[2] for job in jobs]
    if len(paths) != len(set(paths)):
        raise AuditError("duplicate GLB runtime output discovered in metadata")
    return jobs


def main() -> int:
    try:
        jobs = _discover_jobs()
        metrics = [_validate_and_measure(*job) for job in jobs]
    except (AuditError, OSError, json.JSONDecodeError) as exc:
        print("ASSET_RUNTIME_BASELINE_AUDIT=FAIL")
        print(f"- {exc}")
        return 1

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "schema_version": 1,
        "mode": "baseline_audit_no_budgets",
        "glb_count": len(metrics),
        "assets": metrics,
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    for metric in metrics:
        print("ASSET_RUNTIME_BASELINE=" + json.dumps(metric, sort_keys=True, separators=(",", ":")))
    print(
        "ASSET_RUNTIME_BASELINE_SUMMARY="
        + json.dumps(
            {
                "glb_count": len(metrics),
                "total_file_size_bytes": sum(item["file_size_bytes"] for item in metrics),
                "total_triangles": sum(item["triangles"] for item in metrics),
                "total_materials": sum(item["materials"] for item in metrics),
                "total_animations": sum(item["animations"] for item in metrics),
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    print(f"report={REPORT_PATH.relative_to(ROOT).as_posix()}")
    print("ASSET_RUNTIME_BASELINE_AUDIT=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
