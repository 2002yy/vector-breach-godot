"""Register the Source2Viewer 20.1 overlay offset without rewriting original assets."""

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit


def is_overlay(vmat):
    flags = vmat.get("IntParams", {})
    shader = vmat.get("ShaderName", "")
    return (
        any(flags.get(key) == 1 for key in ["F_OVERLAY", "F_DEPTHBIAS", "F_DEPTH_BIAS"])
        or shader.endswith("static_overlay.vfx")
        or shader == "citadel_overlay.vfx"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", type=Path, required=True)
    parser.add_argument("--static-batch-cell", type=int, choices=[0, 8, 16], default=0)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    visual = args.visual.resolve()
    if not visual.is_relative_to(repo / "assets/local_reference"):
        raise ValueError("Expected installed private visual")
    receipt = json.loads(
        visual.with_suffix(".receipt.json").read_text(encoding="utf-8")
    )
    if receipt.get("source_exporter") != "Source2Viewer-CLI 20.1":
        raise ValueError("Unknown exporter; do not apply a guessed offset")
    digest = hashlib.sha256(visual.read_bytes()).hexdigest()
    if digest != receipt["output_sha256"]:
        raise ValueError("Visual changed since its verified conversion")
    scene = json.loads(visual.read_text(encoding="utf-8"))
    dependencies = receipt.get("copied_dependency_sha256", {})
    for buffer in scene.get("buffers", []):
        uri = buffer.get("uri", "")
        if uri.startswith("data:"):
            continue  # Embedded positions were covered by the JSON hash above.
        location = urlsplit(uri)
        path = (visual.parent / unquote(location.path)).resolve()
        if (
            not uri
            or location.scheme
            or location.netloc
            or location.query
            or location.fragment
            or not path.is_relative_to(visual.parent)
        ):
            raise ValueError("Expected a local verified geometry buffer: " + uri)
        expected = dependencies.get(uri)
        if not expected or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError("Geometry buffer changed or lacks a receipt: " + uri)
    predicates = {}
    for material in scene.get("materials", []):
        name = material["name"]
        flag = is_overlay(material.get("extras", {}).get("vmat", {}))
        if name in predicates and predicates[name] != flag:
            raise ValueError("Ambiguous overlay material name: " + name)
        predicates[name] = flag
    names = sorted(
        {
            m["name"]
            for m in scene.get("materials", [])
            if is_overlay(m.get("extras", {}).get("vmat", {}))
        }
    )
    if not names:
        raise ValueError("No verified overlay materials")
    output = visual.parent / "source-overlay-offset.json"
    if output.exists():
        raise FileExistsError("Preserve the installed manifest: " + str(output))
    manifest = {
        "schema": 1,
        "exporter": "Source2Viewer-CLI 20.1",
        "visual_sha256": digest,
        "materials": names,
        "exported_offset_m": 0.01 / 0.0254,
        "surface_offset_m": 0.001,
        "static_batch_cell_m": args.static_batch_cell,
        "source": "https://github.com/ValveResourceFormat/ValveResourceFormat/blob/20.1/ValveResourceFormat/IO/GltfModelExporter.Mesh.cs#L23",
    }
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("SOURCE_OVERLAY_OFFSET_REGISTERED", len(names), output)


if __name__ == "__main__":
    main()
