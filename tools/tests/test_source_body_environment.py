import unittest

from source_body_environment import body_brdf, body_energy, primary_ray, specular_color
from source_indirect_light import indirect_energy
from source_reflection_normalization import env_brdf


class BodyTests(unittest.TestCase):
    def test_partial_cloth_primary_retains_native_length(self):
        primary, ray = primary_ray([0.8, 0, 0.6], [0, 0, 1], [0, 0, 1], 0.5, 1)
        self.assertEqual(primary, [0.4, 0, 0.8])
        self.assertAlmostEqual(sum(v * v for v in primary), 0.8)
        self.assertAlmostEqual(ray[0], 0.5 + 0.4 / (0.8**0.5) * 0.5)

    def test_no_cloth_preserves_ggx(self):
        expected = env_brdf([0.2, 0.7], [0.04, 0.1, 0.6])
        actual = body_brdf([0.2, 0.7], [0.04, 0.1, 0.6], 0.5, 0.3, 0)
        for row, reference in zip(actual, expected):
            for a, b in zip(row, reference):
                self.assertAlmostEqual(a, b)
        args = ([0.3] * 3, [0.5] * 3, *actual, [0.7] * 3, 0.2, 0.35)
        self.assertEqual(body_energy(*args, 0), indirect_energy(*args))

    def test_full_cloth_preserves_diffuse_and_suppresses_specular_multi(self):
        diffuse, specular = body_energy(
            [2] * 3, [3] * 3, [0.2] * 3, [0.4] * 3, [0.5] * 3, 0, 0.5, 1
        )
        self.assertEqual(diffuse, [0.5] * 3)
        for value in specular:
            self.assertAlmostEqual(value, 0.3)

    def test_partial_cloth_uses_native_unscaled_multi_in_diffuse(self):
        diffuse, specular = body_energy(
            [1] * 3, [1] * 3, [0.2] * 3, [0.4] * 3, [1] * 3, 0, 1, 0.5
        )
        for value in diffuse:
            self.assertAlmostEqual(value, 0.7)
        for value in specular:
            self.assertAlmostEqual(value, 0.4)

    def test_metal_sheen_and_ao_boundaries(self):
        albedo = [0.2, 0.4, 0.8]
        self.assertEqual(specular_color(albedo, 1, 0, 1, [1] * 3, 100), albedo)
        self.assertEqual(specular_color(albedo, 0, 1, 0, [1] * 3, 1), [0.046] * 3)
        self.assertEqual(specular_color(albedo, 0, 0, 1, [1] * 3, 100), [1] * 3)
        self.assertEqual(
            body_energy([1] * 3, [1] * 3, [0.2] * 3, [0.1] * 3, albedo, 0, 0, 0.5),
            ([0] * 3, [0] * 3),
        )


if __name__ == "__main__":
    unittest.main()
