import json
import math
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_real_radar import (
    node_matrix,
    normal,
    read_triangles,
    slice_segment,
    transform,
    world_to_uv,
)


class RealRadarTests(unittest.TestCase):
    def test_world_uv_handles_non_square_offset_maps(self):
        rect = [-10, 20, 80, 40]
        self.assertEqual(world_to_uv((-10, 20), rect), (0, 0))
        self.assertEqual(world_to_uv((70, 60), rect), (1, 1))
        self.assertEqual(world_to_uv((30, 30), rect), (0.5, 0.25))

    def test_node_trs_matches_rotation_scale_translation(self):
        matrix = node_matrix(
            dict(
                translation=[2, 3, 4],
                scale=[2, 3, 4],
                rotation=[0, 0, math.sqrt(0.5), math.sqrt(0.5)],
            )
        )
        vertex = transform(matrix, [1, 0, 0])
        for actual, expected in zip(vertex, [2, 5, 4]):
            self.assertAlmostEqual(actual, expected)

    def test_body_height_sections_keep_original_wall_shape(self):
        triangle = ((0, 0, 0), (4, 0, 0), (0, 4, 0))
        self.assertEqual(slice_segment(triangle, 2), [(2, 0), (0, 0)])
        self.assertEqual(slice_segment(triangle, 5), [])

    def test_upward_and_ceiling_normals_are_distinct(self):
        triangle = ((0, 0, 0), (0, 0, 1), (1, 0, 0))
        self.assertEqual(normal(triangle), ((0, 1, 0), 1))
        self.assertEqual(normal(tuple(reversed(triangle)))[0][1], -1)

    def test_glb_scene_hierarchy_and_indexed_vertices(self):
        vertices = struct.pack("<9f", 0, 0, 0, 0, 0, 1, 1, 0, 0)
        indices = struct.pack("<3H", 0, 1, 2)
        blob = vertices + indices + b"\0\0"
        model = dict(
            asset={"version": "2.0"},
            scene=0,
            scenes=[{"nodes": [0]}],
            nodes=[
                {"translation": [3, 4, 5], "children": [1]},
                {"mesh": 0, "scale": [2, 2, 2]},
            ],
            meshes=[{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
            accessors=[
                {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
                {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
            ],
            bufferViews=[
                {"buffer": 0, "byteLength": len(vertices)},
                {"buffer": 0, "byteOffset": len(vertices), "byteLength": len(indices)},
            ],
            buffers=[{"byteLength": len(blob)}],
        )
        encoded = json.dumps(model).encode()
        encoded += b" " * (-len(encoded) % 4)
        data = (
            struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(encoded) + 8 + len(blob))
            + struct.pack("<II", len(encoded), 0x4E4F534A)
            + encoded
            + struct.pack("<II", len(blob), 0x004E4942)
            + blob
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.glb"
            path.write_bytes(data)
            self.assertEqual(read_triangles(path), [((3, 4, 5), (3, 4, 7), (5, 4, 5))])
            path.write_bytes(b"not-a-glb-file")
            with self.assertRaises(ValueError):
                read_triangles(path)


if __name__ == "__main__":
    unittest.main()
