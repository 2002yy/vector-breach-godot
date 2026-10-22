import math
import unittest

from source_normal_frame import cases, mapped_normal


class NormalFrameTests(unittest.TestCase):
    def test_depth_blends_vectors_before_normalizing(self):
        actual = mapped_normal(
            [0.8, 0.5, 0], 0.5, [0.5, 0, 0], [0, 1.2, 0], [0, 0, 0.8]
        )
        length = math.hypot(0.15, 0.72)
        self.assertAlmostEqual(actual[0], 0.15 / length)
        self.assertAlmostEqual(actual[2], 0.72 / length)
        self.assertGreater(abs(actual[0] - 0.3), 0.09)

    def test_zero_depth_and_encoded_z_ignored(self):
        args = ([0.8, 0.3, 0.1], 0, [1, 0, 0], [0, 1, 0], [0, 0, 0.8])
        self.assertEqual(mapped_normal(*args), [0, 0, 1])
        self.assertEqual(
            mapped_normal([0.8, 0.3, 0], 0.5, *args[2:]),
            mapped_normal([0.8, 0.3, 1], 0.5, *args[2:]),
        )

    def test_handedness_and_degenerate_guard(self):
        a = mapped_normal([0.5, 0.8, 0], 1, [1, 0, 0], [0, 1, 0], [0, 0, 1])
        b = mapped_normal([0.5, 0.8, 0], 1, [1, 0, 0], [0, -1, 0], [0, 0, 1])
        self.assertAlmostEqual(a[1], -b[1])
        self.assertEqual(
            mapped_normal([0.5, 0.5, 0], 1, [0] * 3, [0] * 3, [0] * 3), [0, 0, 1]
        )

    def test_blended_frames_remain_finite_unit_vectors(self):
        tests = cases()
        self.assertEqual(len(tests), 216)
        for test in tests:
            value = [v * 2 - 1 for v in test["expected"]]
            self.assertTrue(all(math.isfinite(v) for v in value))
            self.assertAlmostEqual(sum(v * v for v in value), 1)


if __name__ == "__main__":
    unittest.main()
