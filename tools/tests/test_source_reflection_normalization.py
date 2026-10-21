import math
import struct
import unittest

from source_reflection_normalization import (
    brdf_lookup,
    env_brdf,
    hair_secondary_ray,
    normalization,
    normalization_sh,
)


class EnvironmentTests(unittest.TestCase):
    def test_native_secondary_shift_at_full_roughness(self):
        ray = hair_secondary_ray(
            [0, 0, 1], [0, 0, 1], [1, 0, 0], [0, 1, 0], [1, 1], 0.3, 1
        )
        self.assertAlmostEqual(ray[0], -0.3 / math.sqrt(1.09))
        self.assertAlmostEqual(ray[1], 0)
        self.assertAlmostEqual(ray[2], 1 / math.sqrt(1.09))

    def test_planar_rgb_luminance_and_source_yzx_order(self):
        values = [0.0] * 27
        values[0], values[1], values[2], values[3] = 1, 2, 3, 4
        values[9] = 5
        actual = normalization_sh(values)
        expected = [
            4 * 0.2125 * 0.325735,
            2 * 0.2125 * 0.325735,
            3 * 0.2125 * 0.325735,
            (0.2125 + 5 * 0.7154) * 0.282095,
        ]
        for a, b in zip(actual, expected):
            self.assertAlmostEqual(a, b)
        for bad in [values[:-1], [math.nan] * 27]:
            with self.assertRaises(ValueError):
                normalization_sh(bad)

    def test_normalization_darkening_ceiling_and_missing_sh(self):
        self.assertEqual(normalization(0.5, [0, 0, 1], [0.25] * 3, [0, 0, 0, 1]), 0.25)
        self.assertEqual(normalization(0.5, [0, 0, 1], [10] * 3, [0, 0, 0, 1]), 2)
        self.assertEqual(normalization(0.5, [0, 0, 1], [0] * 3, [0, 0, 0, 0]), 1)
        self.assertEqual(normalization(0.5, [0, 0, 1], [0] * 3, [0, 0, 0, -1]), 1)

    def test_brdf_half_texel_endpoints_layer_and_sqrt_view_remap(self):
        raw = bytearray(64 * 64 * 3 * 16)
        for y in range(64):
            for x in range(64):
                struct.pack_into("<4f", raw, ((64 + y) * 64 + x) * 16, x, y, 1, 0)
        self.assertEqual(brdf_lookup(raw, 0, 1), [0, 0, 1, 0])
        self.assertEqual(brdf_lookup(raw, 1, 0), [63, 63, 1, 0])
        values = brdf_lookup(raw, 0.5, 0.75)
        self.assertEqual(values, [31.5, 31.5, 1, 0])
        with self.assertRaises(ValueError):
            brdf_lookup(raw[:-1], 0, 1)

    def test_split_sum_and_energy_compensation(self):
        single, multi = env_brdf([0.1, 0.8], [0, 0.04, 1])
        self.assertAlmostEqual(single[0], 0.1)
        self.assertAlmostEqual(single[1], 0.128)
        self.assertAlmostEqual(single[2], 0.8)
        self.assertTrue(all(v > 0 for v in multi))
        self.assertAlmostEqual(single[2] + multi[2], 1)
