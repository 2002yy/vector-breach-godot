import math
import unittest

from source_indirect_light import (
    ambient_sh,
    complete_probe,
    indirect_energy,
    soft_diffuse,
)


class IndirectTests(unittest.TestCase):
    def test_probe_axis_fallback_and_threshold(self):
        sh = [[1, 2, 3, 4]] * 3
        cube = [[0, 0, 0]] * 6
        normal = [0.6, 0, 0.8]
        expected = 4 + 0.36 + 3 * 0.64
        self.assertAlmostEqual(complete_probe(cube, 0, sh, normal)[0], expected)
        self.assertNotAlmostEqual(expected, 4 + 0.6 + 3 * 0.8)
        self.assertAlmostEqual(
            complete_probe(cube, 0.989, sh, normal)[0], expected * 0.011
        )
        self.assertEqual(complete_probe(cube, 0.99, sh, normal), [0, 0, 0])

    def test_rgb_softness_and_skin_gate(self):
        cube = [[1, 1, 1], [0, 0, 0], [4, 4, 4], [2, 2, 2], [3, 3, 3], [5, 5, 5]]
        sh = [[0] * 4] * 3
        self.assertEqual(
            soft_diffuse(cube, 1, sh, [1, 0, 0], [0, 0, 1], [1, 0.5, 0], 0), [1, 1, 1]
        )
        result = soft_diffuse(cube, 1, sh, [1, 0, 0], [0, 0, 1], [1, 0.5, 0], 1)
        for a, b in zip(result, [4, 2.5, 1]):
            self.assertAlmostEqual(a, b)
        self.assertEqual(
            soft_diffuse(cube, 1, sh, [0, 0, -1], [0, 0, 1], [0.5] * 3, 1), [4] * 3
        )

    def test_energy_conservation_ao_once_and_metal(self):
        args = ([1] * 3, [1] * 3, [0.2] * 3, [0.1] * 3, [1] * 3)
        diffuse, specular = indirect_energy(*args, 0, 0.4)
        for d, s in zip(diffuse, specular):
            self.assertAlmostEqual(d + s, 0.4)
            self.assertAlmostEqual(s, 0.12)
        self.assertEqual(indirect_energy(*args, 1, 1)[0], [0] * 3)
        self.assertEqual(indirect_energy(*args, 0, 0), ([0] * 3, [0] * 3))

    def test_viewer_sh_sky_and_source_pitch(self):
        sun = {
            "classname": "light_environment",
            "enabled": True,
            "parentname": "",
            "scales": [1, 1, 1],
            "angles": [90, 0, 0],
            "color": [255] * 3,
            "brightness": 2,
            "brightnessscale": 1,
            "skycolor": [255] * 3,
            "skyintensity": 1,
            "skyambientbounce": [0] * 3,
        }
        self.assertEqual(ambient_sh(sun), [[0, 0, 0.5, 0.5]] * 3)
        sun["skyambientbounce"] = [255] * 3
        self.assertEqual(ambient_sh(sun), [[0, 0, -1, 2]] * 3)
        sun["angles"][0] = -90
        self.assertEqual(ambient_sh(sun), [[0, 0, 1, 2]] * 3)
        sun["brightness"] = math.nan
        with self.assertRaises(ValueError):
            ambient_sh(sun)


if __name__ == "__main__":
    unittest.main()
