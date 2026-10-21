"""Build independent CPU reflection selection goldens from original map probes/spawns."""

import argparse
import json
import math
from pathlib import Path

from source_reflection import reflection_weights


def build(data, lighting):
    if (
        data["source_trace"] != lighting["source_trace"]
        or data["level"] != lighting["level"]
    ):
        raise ValueError("Reflection/spawn source identities differ")
    cases = []

    def append(position, ray, kind):
        contributors = reflection_weights(data["probes"], position, ray)
        signature = [0.0] * 4
        for row in contributors:
            values = [
                row["cube"] / 128,
                row["direction"][0] * 0.5 + 0.5,
                row["direction"][1] * 0.5 + 0.5,
                1,
            ]
            signature = [a + b * row["weight"] for a, b in zip(signature, values)]
        cases.append(
            {
                "position": position,
                "ray": ray,
                "signature": signature,
                "contributors": len(contributors),
                "kind": kind,
            }
        )

    for sample in lighting["spawn_samples"]:
        for ray in [
            [1, 0, 0],
            [-1, 0, 0],
            [0, 1, 0],
            [0, -1, 0],
            [0, 0, 1],
            [0, 0, -1],
        ]:
            append(sample["position_source"], ray, "original-spawn")
    for probe in data["probes"]:
        angle = math.radians(probe["yaw_degrees"])
        c, s = math.cos(angle), math.sin(angle)
        for fraction in [-0.01, 0, 0.01, 0.5, 0.99, 1, 1.01]:
            local = [
                a + b * (fraction if index == 0 else 0.5)
                for index, (a, b) in enumerate(
                    zip(probe["bounds_min"], probe["bounds_size"])
                )
            ]
            position = [
                c * local[0] - s * local[1],
                s * local[0] + c * local[1],
                local[2],
            ]
            append(
                [p + o for p, o in zip(position, probe["origin"])],
                [1, -2, 3],
                "probe-edge",
            )
    append([1e6, 1e6, 1e6], [1, 0, 0], "outside-all")
    return cases


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ["reflection", "lighting", "output"]:
        parser.add_argument("--" + key, type=Path, required=True)
    args = parser.parse_args()
    result = build(
        json.loads(args.reflection.read_text()), json.loads(args.lighting.read_text())
    )
    args.output.write_text(
        json.dumps(result, indent=2, allow_nan=False), encoding="utf-8"
    )
    print("REFLECTION_WORLD_CASES_OK", len(result))
