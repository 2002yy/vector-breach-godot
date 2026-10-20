"""Keep real opaque geometry while excluding nonstructural source surfaces."""

import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest


class ClassicOccluderTests(unittest.TestCase):
    def test_helpers_effects_and_overlays_cannot_occlude_real_props(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            vertices = struct.pack("<9f", 0, 0, 0, 2, 0, 0, 0, 2, 0)
            indices = struct.pack("<3H", 0, 1, 2)
            original = vertices + indices
            (root / "mesh.bin").write_bytes(original)
            materials = [
                {"name": name}
                for name in [
                    "real_wall",
                    "bucket_tools",
                    "gardening_tools",
                    "wrongway_timer",
                    "toolssolidblocklight",
                    "toolsblocklight",
                ]
            ] + [
                {
                    "name": "dust",
                    "extras": {"vmat": {"ShaderName": "csgo_effects.vfx"}},
                },
                {
                    "name": "decal",
                    "extras": {"vmat": {"ShaderName": "csgo_static_overlay.vfx"}},
                },
                {"name": "foliage", "alphaMode": "MASK"},
            ]
            scene = {
                "asset": {"version": "2.0"},
                "buffers": [{"uri": "mesh.bin", "byteLength": len(original)}],
                "bufferViews": [
                    {"buffer": 0, "byteOffset": 0, "byteLength": len(vertices)},
                    {
                        "buffer": 0,
                        "byteOffset": len(vertices),
                        "byteLength": len(indices),
                    },
                ],
                "accessors": [
                    {
                        "bufferView": 0,
                        "componentType": 5126,
                        "count": 3,
                        "type": "VEC3",
                    },
                    {
                        "bufferView": 1,
                        "componentType": 5123,
                        "count": 3,
                        "type": "SCALAR",
                    },
                ],
                "materials": materials,
                "meshes": [
                    {
                        "primitives": [
                            {
                                "attributes": {"POSITION": 0},
                                "indices": 1,
                                "material": index,
                            }
                            for index in range(len(materials))
                        ]
                    }
                ],
                "nodes": [{"mesh": 0}],
                "scenes": [{"nodes": [0]}],
            }
            source = root / "scene.gltf"
            encoded = json.dumps(scene)
            source.write_text(encoded, encoding="utf-8")
            tool = Path(__file__).resolve().parents[1] / "build_classic_occluder.py"
            subprocess.run(
                [
                    sys.executable,
                    str(tool),
                    "--source",
                    str(source),
                    "--output",
                    str(root / "result.bin"),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            receipt = json.loads((root / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["opaque_source_triangles"], 3)
            self.assertEqual(receipt["occluder_triangles"], 3)
            self.assertEqual(
                (root / "result.bin").read_bytes(), struct.pack("<I", 9) + vertices * 3
            )
            self.assertEqual((root / "mesh.bin").read_bytes(), original)
            self.assertEqual(source.read_text(encoding="utf-8"), encoded)


if __name__ == "__main__":
    unittest.main()
