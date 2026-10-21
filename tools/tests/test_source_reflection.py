import copy
import hashlib
import math
import unittest

from source_reflection import (
    box_direction,
    cube_direction,
    reflection_record,
    reflection_weights,
    validate_blocks,
)


class ReflectionTests(unittest.TestCase):
    def test_reflection_priority_array_order_residual_and_edge_rule(self):
        high = dict(self.probe, cube_index=3, priority=2, edge_fade=[1, 1, 1])
        low = dict(high, cube_index=1, priority=1)
        # Native grown box [-2.02,2.02], fade width 1.02. At x=-1.51 edge=.5.
        rows = reflection_weights([low, high], [8.49, 20, 30], [1, 0, 0])
        self.assertEqual([r["cube"] for r in rows], [3, 1])
        self.assertAlmostEqual(rows[0]["weight"], 0.495)
        self.assertAlmostEqual(rows[1]["weight"], 0.2475)
        # Stable tie uses native array index, never default entity enumeration.
        low["priority"] = 2
        self.assertEqual(
            reflection_weights([high, low], [10, 20, 30], [1, 0, 0])[0]["cube"], 1
        )
        self.assertAlmostEqual(
            sum(
                r["weight"] for r in reflection_weights([high], [10, 20, 30], [1, 0, 0])
            ),
            0.99,
        )
        self.assertEqual(reflection_weights([high], [100, 20, 30], [1, 0, 0]), [])

    def setUp(self):
        self.payload = bytes(96)
        self.data = {
            "schema": 1,
            "contract": "source-reflection-blocks-v1",
            "format": "BC6H-UFLOAT",
            "layout": "mip-ascending/cube/face/BC6H-blocks",
            "width": 4,
            "cubes": 1,
            "mip_count": 1,
            "face_order": ["+X", "-X", "+Y", "-Y", "+Z", "-Z"],
            "mips": [
                {
                    "level": 0,
                    "size": 4,
                    "offset": 0,
                    "face_bytes": 16,
                    "bytes": 96,
                    "sha256": hashlib.sha256(self.payload).hexdigest(),
                }
            ],
        }
        self.probe = {
            "enabled": True,
            "sample_supported": True,
            "origin": [10, 20, 30],
            "yaw_degrees": 0,
            "bounds_min": [-2, -2, -2],
            "bounds_size": [4, 4, 4],
        }

    def test_native_truncated_chain_is_valid_without_synthesizing_mips(self):
        validate_blocks(self.data, self.payload)

    def test_corrupt_block_and_size_rejected(self):
        for payload in [
            self.payload[:-1],
            self.payload + b"0",
            b"1" + self.payload[1:],
        ]:
            with self.subTest(payload=len(payload)), self.assertRaises(ValueError):
                validate_blocks(self.data, payload)

    def test_layout_dimensions_face_order_and_offsets_rejected(self):
        invalid = copy.deepcopy(self.data)
        invalid["mips"][0] = "invalid"
        with self.assertRaises(TypeError):
            validate_blocks(invalid, self.payload)
        for key, value in [
            ("width", 3),
            ("cubes", 0),
            ("cubes", 129),
            ("width", True),
            ("mip_count", 4),
            ("layout", "lpv"),
            ("face_order", []),
        ]:
            data = copy.deepcopy(self.data)
            data[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_blocks(data, self.payload)
        for key in ["offset", "face_bytes", "level", "bytes", "sha256"]:
            data = copy.deepcopy(self.data)
            data["mips"][0][key] = "invalid"
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_blocks(data, self.payload)

    def test_six_cube_faces_and_off_center_orientation(self):
        self.assertEqual(
            [cube_direction(i, 0.5, 0.5) for i in range(6)],
            [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)],
        )
        self.assertEqual(cube_direction(0, 0.25, 0.75), (1, -0.5, 0.5))
        self.assertEqual(cube_direction(4, 0.25, 0.75), (-0.5, -0.5, 1))

    def test_box_uses_native_origin_not_box_center(self):
        self.probe.update(bounds_min=[0, 0, 0], bounds_size=[4, 6, 8])
        expected = [4, 3, 4]
        result = box_direction(self.probe, [12, 23, 34], [1, 0, 0])
        for actual, value in zip(result, expected):
            self.assertAlmostEqual(actual, value / math.sqrt(41))

    def test_yaw_and_parallel_axes(self):
        self.probe["yaw_degrees"] = 90
        result = box_direction(self.probe, [10, 20, 30], [0, 1, 0])
        self.assertAlmostEqual(result[0], 1)
        self.assertAlmostEqual(result[1], 0)

    def test_bounds_unsupported_and_zero_ray(self):
        self.assertIsNone(box_direction(self.probe, [99, 20, 30], [1, 0, 0]))
        with self.assertRaises(ValueError):
            box_direction(self.probe, [10, 20, 30], [0, 0, 0])
        self.probe["sample_supported"] = False
        self.assertIsNone(box_direction(self.probe, [10, 20, 30], [1, 0, 0]))

    def test_probe_indices_validate_without_inventing_array_layers(self):
        entity = {
            "origin": [0, 0, 0],
            "box_mins": [-1, -1, -1],
            "box_maxs": [1, 1, 1],
            "edge_fade_dists": [1, 1, 1],
            "cubemaptexture": "cube",
            "lightprobetexture": "lpv",
            "array_index": 1,
        }
        entity.update({"light_probe_size_" + a: 1 for a in "xyz"})
        entity.update({"light_probe_atlas_" + a: 0 for a in "xyz"})
        self.assertEqual(reflection_record(entity, 2)["cube_index"], 1)
        for index in [-1, 2, True, 1.5]:
            entity["array_index"] = index
            with self.assertRaises(ValueError):
                reflection_record(entity, 2)


if __name__ == "__main__":
    unittest.main()
