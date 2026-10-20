"""Independent analytic goldens for native HDR volume coordinates and blending."""

import json
import math
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inspect_source_map_lighting import recover, resource_name
from build_source_lighting_bridge import build
from source_probe_volume import FloatVolume, probe_record, sample_blended, sample_probe


def entity():
    return {
        "origin": [10, 20, 30],
        "box_mins": [-1, -1, -1],
        "box_maxs": [1, 1, 1],
        "edge_fade_dists": [0.5, 0.5, 0.5],
        "light_probe_size_x": 1,
        "light_probe_size_y": 1,
        "light_probe_size_z": 1,
        "light_probe_atlas_x": 0,
        "light_probe_atlas_Y": 0,
        "light_probe_atlas_Z": 0,
        "lightprobetexture": "test.vtex",
    }


def cube(values):
    return FloatVolume(
        b"".join(struct.pack("<4f", v, v * 2, v * 3, 1) for v in values), [1, 1, 6]
    )


class SourceProbeTests(unittest.TestCase):
    def test_bridge_build_requires_existing_toolchain_and_preserves_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root / "bridge.dll"
            output.write_bytes(b"existing")
            with self.assertRaises(FileExistsError):
                build(root, root, root, output)
            with self.assertRaises(FileNotFoundError):
                build(root, root, root, root / "new.dll")
            self.assertEqual(output.read_bytes(), b"existing")

    def test_hdr_float_data_and_six_face_order(self):
        probe = probe_record(entity())
        volume = cube([1, 2, 4, 8, 16, 32])
        for direction, expected in [
            ([1, 0, 0], 1),
            ([0, 1, 0], 2),
            ([0, 0, 1], 4),
            ([-1, 0, 0], 8),
            ([0, -1, 0], 16),
            ([0, 0, -1], 32),
        ]:
            actual, weight = sample_probe(probe, volume, [10, 20, 30], direction)
            self.assertEqual(weight, 1)
            self.assertEqual(actual, [expected, expected * 2, expected * 3])

    def test_normal_squared_mix_and_normalization(self):
        rgb, _ = sample_probe(
            probe_record(entity()), cube([1, 3, 5, 7, 9, 11]), [10, 20, 30], [2, 2, 0]
        )
        self.assertAlmostEqual(rgb[0], 2)

    def test_gpu_texel_center_trilinear_and_clamp(self):
        data = b"".join(
            struct.pack("<4f", x + y * 2 + z * 4, 0, 0, 1)
            for z in range(2)
            for y in range(2)
            for x in range(2)
        )
        volume = FloatVolume(data, [2, 2, 2])
        self.assertEqual(volume.sample([0.25, 0.25, 0.25])[0], 0)
        self.assertEqual(volume.sample([0.75, 0.75, 0.75])[0], 7)
        self.assertEqual(volume.sample([0.5, 0.5, 0.5])[0], 3.5)
        self.assertEqual(volume.sample([-10, 10, 10])[0], 6)

    def test_translation_yaw_and_edge_fade(self):
        original = entity()
        original.update(angles=[0, 90, 0], box_mins=[-2, -1, -1], box_maxs=[2, 1, 1])
        probe = probe_record(original)
        _, weight = sample_probe(probe, cube([1] * 6), [10.75, 20, 30], [1, 0, 0])
        self.assertAlmostEqual(weight, 0.5)
        _, outside = sample_probe(probe, cube([1] * 6), [12, 20, 30], [1, 0, 0])
        self.assertEqual(outside, 0)

    def test_zero_edge_uses_native_minimum_point_zero_two(self):
        source = entity()
        source["edge_fade_dists"] = [0, 0, 0]
        _, weight = sample_probe(
            probe_record(source), cube([1] * 6), [10.99, 20, 30], [1, 0, 0]
        )
        self.assertAlmostEqual(weight, 0.5)

    def test_priority_consumes_only_remaining_coverage(self):
        low = probe_record(entity())
        high = dict(low, priority=10, texture="high")
        result = sample_blended(
            [low, high],
            {"test.vtex": cube([2] * 6), "high": cube([10] * 6)},
            [10.75, 20, 30],
            [1, 0, 0],
        )
        self.assertEqual(result["rgb"], [5.5, 11, 16.5])
        self.assertEqual(result["coverage"], 0.75)
        self.assertTrue(result["fallback_missing"])

    def test_four_probe_cap_and_disabled_filter(self):
        probe = probe_record(entity())
        probes = [dict(probe, enabled=False), *[dict(probe) for _ in range(8)]]
        result = sample_blended(
            probes, {"test.vtex": cube([2] * 6)}, [10.75, 20, 30], [1, 0, 0]
        )
        self.assertEqual(result["probe_count"], 4)
        self.assertEqual(result["coverage"], 0.9375)

    def test_missing_fallback_never_invents_ambient_light(self):
        result = sample_blended(
            [probe_record(entity())],
            {"test.vtex": cube([2] * 6)},
            [100, 100, 100],
            [0, 0, 1],
        )
        self.assertEqual(result["rgb"], [0, 0, 0])
        self.assertEqual(result["coverage"], 0)
        self.assertTrue(result["fallback_missing"])

    def test_bad_dimensions_directions_transforms_and_pixels_fail(self):
        with self.assertRaises(ValueError):
            FloatVolume(b"", [1, 1, 6])
        source = entity()
        source["angles"] = [1, 0, 0]
        with self.assertRaises(ValueError):
            sample_probe(probe_record(source), cube([1] * 6), [10, 20, 30], [1, 0, 0])
        for direction in ([0, 0, 0], [math.nan, 0, 1]):
            with self.assertRaises(ValueError):
                sample_probe(
                    probe_record(entity()), cube([1] * 6), [10, 20, 30], direction
                )
        with self.assertRaises(ValueError):
            cube([math.inf] * 6).sample([0.5, 0.5, 0.5])

    def test_native_paths_hash_guard_and_output_preservation(self):
        for name in ("../outside", "C:/outside", "/absolute", "maps\\bad"):
            with self.assertRaises(ValueError):
                resource_name(name)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root / "output"
            output.mkdir()
            with self.assertRaises(FileExistsError):
                recover(root, root, root, root, output)
            vpk = root / "map.vpk"
            vpk.write_bytes(b"original")
            level = root / "level.json"
            level.write_text(
                json.dumps(
                    {"sourceTrace": {"referenceMap": "map", "vpkSha256": "wrong"}}
                )
            )
            with self.assertRaises(ValueError):
                recover(root, root, level, vpk, root / "new")
            self.assertFalse((root / "new").exists())
            self.assertEqual(vpk.read_bytes(), b"original")


if __name__ == "__main__":
    unittest.main()
