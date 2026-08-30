#!/usr/bin/env python3
"""Validate freshly rebuilt Blender-owned GLB outputs against Step 15 contracts."""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path
from typing import Any

from check_runtime_asset_contracts import BUDGET_KEYS

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets-source" / "blender"
REPORT_PATH = ROOT / "reports" / "runtime_asset_validation.json"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
TRIANGLE_MODES = {4, 5, 6}
COMPONENT_SIZES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
INDEX_TYPES = {5121, 5123, 5125}
IMAGE_MIME_TYPES = {"image/png", "image/jpeg", "image/webp"}


class ValidationError(RuntimeError):
    pass


def require_index(value: Any, size: int, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0 or value >= size:
        raise ValidationError(f"{label} index out of range: {value!r} (size={size})")
    return value


def require_int(value: Any, label: str, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ValidationError(f"{label} must be integer >= {minimum}, got {value!r}")
    return value


def finite_array(value: Any, label: str, length: int | None = None) -> None:
    if not isinstance(value, list) or (length is not None and len(value) != length):
        raise ValidationError(f"{label} must be an array" + (f" of length {length}" if length else ""))
    if any(not isinstance(x, (int, float)) or isinstance(x, bool) or not math.isfinite(float(x)) for x in value):
        raise ValidationError(f"{label} contains non-finite/non-numeric values")


def load_glb(path: Path) -> tuple[dict[str, Any], bytes, int]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValidationError(f"GLB too small: {path}")
    magic, version, declared = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or declared != len(data):
        raise ValidationError(f"invalid GLB header: {path}")
    offset = 12
    chunks: list[tuple[int, bytes]] = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValidationError(f"truncated GLB chunk header: {path}")
        length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        end = offset + length
        if length % 4 or end > len(data) or chunk_type not in {JSON_CHUNK, BIN_CHUNK}:
            raise ValidationError(f"invalid GLB chunk: {path}")
        chunks.append((chunk_type, data[offset:end]))
        offset = end
    if not chunks or chunks[0][0] != JSON_CHUNK or sum(t == JSON_CHUNK for t, _ in chunks) != 1:
        raise ValidationError(f"GLB must contain exactly one leading JSON chunk: {path}")
    bins = [chunk for chunk_type, chunk in chunks if chunk_type == BIN_CHUNK]
    if len(bins) > 1:
        raise ValidationError(f"GLB contains multiple BIN chunks: {path}")
    try:
        gltf = json.loads(chunks[0][1].rstrip(b" \t\r\n\0").decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValidationError(f"invalid glTF JSON: {path}: {exc}") from exc
    if not isinstance(gltf, dict):
        raise ValidationError(f"glTF root must be an object: {path}")
    return gltf, bins[0] if bins else b"", len(data)


def triangle_count(mode: int, count: int) -> int:
    if mode == 4:
        if count % 3:
            raise ValidationError(f"triangle element count must be divisible by 3, got {count}")
        return count // 3
    if mode in {5, 6}:
        return max(0, count - 2)
    raise ValidationError(f"unsupported primitive mode {mode}")


def texture_info(value: Any, textures: list[Any], label: str) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise ValidationError(f"{label} must be an object")
    require_index(value.get("index"), len(textures), f"{label}.index")


def validate_graph(nodes: list[Any], rel: str) -> None:
    parents = [0] * len(nodes)
    for i, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise ValidationError(f"{rel}: node[{i}] must be an object")
        children = node.get("children", [])
        if not isinstance(children, list) or len(children) != len(set(children)):
            raise ValidationError(f"{rel}: node[{i}].children invalid/duplicated")
        for child in children:
            child = require_index(child, len(nodes), f"{rel}: node[{i}].children")
            parents[child] += 1
            if parents[child] > 1:
                raise ValidationError(f"{rel}: node[{child}] has multiple parents")
    state = [0] * len(nodes)

    def visit(i: int) -> None:
        if state[i] == 1:
            raise ValidationError(f"{rel}: scene graph cycle at node[{i}]")
        if state[i] == 2:
            return
        state[i] = 1
        for child in nodes[i].get("children", []):
            visit(child)
        state[i] = 2

    for i in range(len(nodes)):
        visit(i)


def validate_contract(contract: Any, rel: str) -> tuple[dict[str, int], dict[str, int], set[str]]:
    if not isinstance(contract, dict) or contract.get("format") != "glb2":
        raise ValidationError(f"{rel}: contract format must be glb2")
    maximums = contract.get("max")
    if not isinstance(maximums, dict) or set(maximums) != BUDGET_KEYS:
        raise ValidationError(f"{rel}: contract max keys invalid")
    for key, value in maximums.items():
        require_int(value, f"{rel}: contract.max.{key}")
    minimums = contract.get("min", {})
    if not isinstance(minimums, dict) or not set(minimums).issubset(BUDGET_KEYS):
        raise ValidationError(f"{rel}: contract min keys invalid")
    for key, value in minimums.items():
        require_int(value, f"{rel}: contract.min.{key}")
        if value > maximums[key]:
            raise ValidationError(f"{rel}: contract min {key} exceeds max")
    allowed = contract.get("allowed_extensions_used", [])
    if not isinstance(allowed, list) or any(not isinstance(x, str) or not x for x in allowed) or len(allowed) != len(set(allowed)):
        raise ValidationError(f"{rel}: allowed_extensions_used invalid")
    return maximums, minimums, set(allowed)


def validate_asset(asset_id: str, category: str, rel: str, contract: dict[str, Any]) -> dict[str, Any]:
    path = ROOT / rel
    if not path.is_file():
        raise ValidationError(f"runtime output missing: {rel}")
    maximums, minimums, allowed_extensions = validate_contract(contract, rel)
    gltf, bin_chunk, file_size = load_glb(path)
    asset = gltf.get("asset")
    if not isinstance(asset, dict) or asset.get("version") != "2.0":
        raise ValidationError(f"{rel}: asset.version must be 2.0")

    def array(name: str) -> list[Any]:
        value = gltf.get(name, [])
        if not isinstance(value, list):
            raise ValidationError(f"{rel}: {name} must be an array")
        return value

    scenes, nodes, meshes = array("scenes"), array("nodes"), array("meshes")
    materials, textures, images = array("materials"), array("textures"), array("images")
    samplers, skins, animations = array("samplers"), array("skins"), array("animations")
    accessors, views, buffers = array("accessors"), array("bufferViews"), array("buffers")
    used, required = array("extensionsUsed"), array("extensionsRequired")
    if any(not isinstance(x, str) or not x for x in used + required):
        raise ValidationError(f"{rel}: extension declarations invalid")
    if required:
        raise ValidationError(f"{rel}: extensionsRequired must be empty")
    undeclared = set(used) - allowed_extensions
    if undeclared:
        raise ValidationError(f"{rel}: extensionsUsed exceeds contract allowlist: {sorted(undeclared)}")

    if len(scenes) != 1 or gltf.get("scene") != 0:
        raise ValidationError(f"{rel}: production GLB must have one default scene at index 0")
    if len(buffers) != 1:
        raise ValidationError(f"{rel}: production GLB must have one embedded buffer")
    validate_graph(nodes, rel)
    roots = scenes[0].get("nodes", []) if isinstance(scenes[0], dict) else None
    if not isinstance(roots, list):
        raise ValidationError(f"{rel}: scene[0].nodes must be an array")
    for root in roots:
        require_index(root, len(nodes), f"{rel}: scene[0].nodes")

    for i, node in enumerate(nodes):
        if "matrix" in node and any(k in node for k in ("translation", "rotation", "scale")):
            raise ValidationError(f"{rel}: node[{i}] mixes matrix and TRS")
        for key, length in (("matrix", 16), ("translation", 3), ("rotation", 4), ("scale", 3)):
            if key in node:
                finite_array(node[key], f"{rel}: node[{i}].{key}", length)
        if "mesh" in node:
            require_index(node["mesh"], len(meshes), f"{rel}: node[{i}].mesh")
        if "skin" in node:
            require_index(node["skin"], len(skins), f"{rel}: node[{i}].skin")

    buffer = buffers[0]
    if not isinstance(buffer, dict) or "uri" in buffer:
        raise ValidationError(f"{rel}: external buffer URI is forbidden")
    declared_buffer = require_int(buffer.get("byteLength"), f"{rel}: buffer.byteLength")
    if declared_buffer > len(bin_chunk) or len(bin_chunk) - declared_buffer > 3:
        raise ValidationError(f"{rel}: embedded BIN length mismatch")

    for i, view in enumerate(views):
        if not isinstance(view, dict):
            raise ValidationError(f"{rel}: bufferView[{i}] must be an object")
        require_index(view.get("buffer"), len(buffers), f"{rel}: bufferView[{i}].buffer")
        offset = require_int(view.get("byteOffset", 0), f"{rel}: bufferView[{i}].byteOffset")
        length = require_int(view.get("byteLength"), f"{rel}: bufferView[{i}].byteLength")
        if offset + length > declared_buffer:
            raise ValidationError(f"{rel}: bufferView[{i}] exceeds buffer bounds")

    for i, accessor in enumerate(accessors):
        if not isinstance(accessor, dict):
            raise ValidationError(f"{rel}: accessor[{i}] must be an object")
        ctype, atype = accessor.get("componentType"), accessor.get("type")
        if ctype not in COMPONENT_SIZES or atype not in TYPE_COMPONENTS:
            raise ValidationError(f"{rel}: accessor[{i}] componentType/type invalid")
        count = require_int(accessor.get("count"), f"{rel}: accessor[{i}].count")
        byte_offset = require_int(accessor.get("byteOffset", 0), f"{rel}: accessor[{i}].byteOffset")
        if byte_offset % COMPONENT_SIZES[ctype]:
            raise ValidationError(f"{rel}: accessor[{i}] byteOffset misaligned")
        if "bufferView" in accessor:
            view_index = require_index(accessor["bufferView"], len(views), f"{rel}: accessor[{i}].bufferView")
            element_size = COMPONENT_SIZES[ctype] * TYPE_COMPONENTS[atype]
            stride = views[view_index].get("byteStride", element_size)
            if not isinstance(stride, int) or stride < element_size:
                raise ValidationError(f"{rel}: accessor[{i}] invalid stride")
            required_bytes = byte_offset if count == 0 else byte_offset + stride * (count - 1) + element_size
            if required_bytes > views[view_index]["byteLength"]:
                raise ValidationError(f"{rel}: accessor[{i}] exceeds bufferView bounds")
        elif accessor.get("sparse") is None and count:
            raise ValidationError(f"{rel}: accessor[{i}] has no storage")
        for key in ("min", "max"):
            if key in accessor:
                finite_array(accessor[key], f"{rel}: accessor[{i}].{key}")

    primitive_count = vertex_count = triangles = 0
    for mi, mesh in enumerate(meshes):
        primitives = mesh.get("primitives") if isinstance(mesh, dict) else None
        if not isinstance(primitives, list) or not primitives:
            raise ValidationError(f"{rel}: mesh[{mi}].primitives invalid")
        for pi, primitive in enumerate(primitives):
            if not isinstance(primitive, dict):
                raise ValidationError(f"{rel}: primitive[{mi}:{pi}] invalid")
            primitive_count += 1
            mode = primitive.get("mode", 4)
            if mode not in TRIANGLE_MODES:
                raise ValidationError(f"{rel}: primitive[{mi}:{pi}] uses non-triangle mode {mode}")
            attrs = primitive.get("attributes")
            if not isinstance(attrs, dict) or "POSITION" not in attrs:
                raise ValidationError(f"{rel}: primitive[{mi}:{pi}] missing POSITION")
            for semantic, accessor_index in attrs.items():
                require_index(accessor_index, len(accessors), f"{rel}: attribute {semantic}")
            position = accessors[attrs["POSITION"]]
            if position.get("type") != "VEC3" or position.get("componentType") != 5126:
                raise ValidationError(f"{rel}: POSITION must be FLOAT VEC3")
            if "material" in primitive:
                require_index(primitive["material"], len(materials), f"{rel}: primitive material")
            element_count = position["count"]
            if "indices" in primitive:
                index_accessor = accessors[require_index(primitive["indices"], len(accessors), f"{rel}: primitive indices")]
                if index_accessor.get("type") != "SCALAR" or index_accessor.get("componentType") not in INDEX_TYPES:
                    raise ValidationError(f"{rel}: indices must use unsigned SCALAR accessor")
                element_count = index_accessor["count"]
            vertex_count += position["count"]
            triangles += triangle_count(mode, element_count)

    for i, image in enumerate(images):
        if not isinstance(image, dict) or "uri" in image or "bufferView" not in image:
            raise ValidationError(f"{rel}: image[{i}] must be embedded")
        require_index(image["bufferView"], len(views), f"{rel}: image[{i}].bufferView")
        if image.get("mimeType") not in IMAGE_MIME_TYPES:
            raise ValidationError(f"{rel}: image[{i}] mimeType unsupported")
    for i, texture in enumerate(textures):
        if not isinstance(texture, dict):
            raise ValidationError(f"{rel}: texture[{i}] invalid")
        require_index(texture.get("source"), len(images), f"{rel}: texture[{i}].source")
        if "sampler" in texture:
            require_index(texture["sampler"], len(samplers), f"{rel}: texture[{i}].sampler")
    for i, material in enumerate(materials):
        if not isinstance(material, dict):
            raise ValidationError(f"{rel}: material[{i}] invalid")
        pbr = material.get("pbrMetallicRoughness", {})
        if not isinstance(pbr, dict):
            raise ValidationError(f"{rel}: material[{i}].pbrMetallicRoughness invalid")
        texture_info(pbr.get("baseColorTexture"), textures, f"{rel}: material[{i}].baseColorTexture")
        texture_info(pbr.get("metallicRoughnessTexture"), textures, f"{rel}: material[{i}].metallicRoughnessTexture")
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            texture_info(material.get(key), textures, f"{rel}: material[{i}].{key}")

    joints_total = 0
    for i, skin in enumerate(skins):
        joints = skin.get("joints") if isinstance(skin, dict) else None
        if not isinstance(joints, list) or not joints or len(joints) != len(set(joints)):
            raise ValidationError(f"{rel}: skin[{i}].joints invalid")
        joints_total += len(joints)
        for joint in joints:
            require_index(joint, len(nodes), f"{rel}: skin[{i}].joints")
        if "inverseBindMatrices" in skin:
            ibm = accessors[require_index(skin["inverseBindMatrices"], len(accessors), f"{rel}: inverseBindMatrices")]
            if ibm.get("type") != "MAT4" or ibm.get("componentType") != 5126 or ibm.get("count") != len(joints):
                raise ValidationError(f"{rel}: inverseBindMatrices must match joint count")

    animation_channels = 0
    for ai, animation in enumerate(animations):
        anim_samplers = animation.get("samplers") if isinstance(animation, dict) else None
        channels = animation.get("channels") if isinstance(animation, dict) else None
        if not isinstance(anim_samplers, list) or not isinstance(channels, list):
            raise ValidationError(f"{rel}: animation[{ai}] invalid")
        for sampler in anim_samplers:
            if not isinstance(sampler, dict):
                raise ValidationError(f"{rel}: animation sampler invalid")
            input_acc = accessors[require_index(sampler.get("input"), len(accessors), f"{rel}: animation input")]
            require_index(sampler.get("output"), len(accessors), f"{rel}: animation output")
            if input_acc.get("type") != "SCALAR" or input_acc.get("componentType") != 5126 or input_acc.get("count", 0) <= 0:
                raise ValidationError(f"{rel}: animation input must be non-empty FLOAT SCALAR")
        animation_channels += len(channels)
        for channel in channels:
            if not isinstance(channel, dict):
                raise ValidationError(f"{rel}: animation channel invalid")
            require_index(channel.get("sampler"), len(anim_samplers), f"{rel}: animation channel sampler")
            target = channel.get("target")
            if not isinstance(target, dict) or target.get("path") not in {"translation", "rotation", "scale", "weights"}:
                raise ValidationError(f"{rel}: animation target invalid")
            require_index(target.get("node"), len(nodes), f"{rel}: animation target node")

    metrics = {
        "file_size_bytes": file_size,
        "nodes": len(nodes), "meshes": len(meshes), "primitives": primitive_count,
        "vertices_by_primitive": vertex_count, "triangles": triangles,
        "materials": len(materials), "textures": len(textures), "images": len(images),
        "skins": len(skins), "skin_joints_total": joints_total,
        "animations": len(animations), "animation_channels": animation_channels,
    }
    for key, value in metrics.items():
        if value > maximums[key]:
            raise ValidationError(f"{rel}: budget exceeded for {key}: actual={value} max={maximums[key]}")
        if key in minimums and value < minimums[key]:
            raise ValidationError(f"{rel}: minimum not met for {key}: actual={value} min={minimums[key]}")
    return {"asset_id": asset_id, "category": category, "path": rel, "metrics": metrics, "extensions_used": sorted(used)}


def discover_jobs() -> list[tuple[str, str, str, dict[str, Any]]]:
    jobs: list[tuple[str, str, str, dict[str, Any]]] = []
    for sidecar in sorted(SOURCE_ROOT.rglob("*.asset.json")):
        metadata = json.loads(sidecar.read_text(encoding="utf-8"))
        if not isinstance(metadata, dict) or metadata.get("authoring_tool") != "Blender":
            continue
        contracts = metadata.get("runtime_contracts")
        if not isinstance(contracts, dict):
            raise ValidationError(f"missing runtime_contracts: {sidecar.relative_to(ROOT)}")
        for output in metadata.get("runtime_outputs", []):
            if isinstance(output, str) and output.lower().endswith(".glb"):
                contract = contracts.get(output)
                if not isinstance(contract, dict):
                    raise ValidationError(f"missing contract for {output}")
                jobs.append((metadata["asset_id"], metadata["category"], output, contract))
    if not jobs:
        raise ValidationError("no Blender-owned GLBs discovered")
    if len({job[2] for job in jobs}) != len(jobs):
        raise ValidationError("duplicate GLB runtime output discovered")
    return jobs


def main() -> int:
    try:
        assets = [validate_asset(*job) for job in discover_jobs()]
    except (ValidationError, OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        print("ASSET_RUNTIME_VALIDATION=FAIL")
        print(f"- {exc}")
        return 1
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps({"schema_version": 1, "glb_count": len(assets), "assets": assets}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for asset in assets:
        print("ASSET_RUNTIME_VALIDATED=" + json.dumps(asset, sort_keys=True, separators=(",", ":")))
    print(f"validated_glbs={len(assets)}")
    print("ASSET_RUNTIME_VALIDATION=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
