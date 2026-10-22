"""Independent CPU oracle for the pinned Godot Forward+ normal-map contract."""

import argparse
import itertools
import json
import math
from pathlib import Path


def unit(value, fallback):
    length = math.sqrt(sum(v * v for v in value))
    return [v / length for v in value] if length > 1e-6 else fallback


def mapped_normal(encoded, depth, tangent, bitangent, normal):
    x, y = [v * 2 - 1 for v in encoded[:2]]
    z = math.sqrt(max(1 - x * x - y * y, 0))
    mapped = [t * x + b * y + n * z for t, b, n in zip(tangent, bitangent, normal)]
    value = [n * (1 - depth) + m * depth for n, m in zip(normal, mapped)]
    return unit(value, unit(normal, [0, 0, 1]))


def cases():
    result = []
    for degrees, blend, sign, depth, encoded in itertools.product(
        [0, 35, 80],
        [0.25, 0.6, 1],
        [-1, 1],
        [0, 0.5, 1, 2],
        [[0.5, 0.5, 1], [0.8, 0.3, 0.1], [1, 1, 0]],
    ):
        c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
        # Linear two-bone blend plus unequal TBN lengths, before normalization.
        t = [(1 - blend + blend * c) * 0.5, 0, -blend * s * 0.5]
        b = [0, sign * 1.2, 0]
        n = [blend * s * 0.8, 0, (1 - blend + blend * c) * 0.8]
        value = mapped_normal(encoded, depth, t, b, n)
        result.append(
            {
                "encoded": encoded,
                "depth": depth,
                "tangent": t,
                "bitangent": b,
                "normal": n,
                "expected": [v * 0.5 + 0.5 for v in value],
            }
        )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(cases(), stream, allow_nan=False)
