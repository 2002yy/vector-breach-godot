"""Cross incident horizontal/vertical position independently without changing maps."""

from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from crouch_motion_factorial import payload as original_payload, validate
from native_jump_candidates import freeze
from validate_native_route_study import require


def payload(source, project):
    parent: dict[str, Any] = original_payload(source, project)
    states = parent["states"]
    cases = []
    for horizontal in ("60", "120"):
        for vertical in ("60", "120"):
            for velocity in ("60", "120"):
                position = list(states[horizontal]["position"])
                position[1] = states[vertical]["position"][1]
                cases.append(
                    dict(
                        id=f"h{horizontal}_y{vertical}_v{velocity}",
                        position=position,
                        velocity=states[velocity]["velocity"],
                        steps=[1 / 60],
                    )
                )
    return dict(
        parent,
        cases=cases,
        scope="frozen_horizontal_vertical_position_components_not_route_acceptance",
    )


def verify(source, directory, project):
    expected = payload(source, project)
    matrix = directory / "matrix-v1.json"
    require(read(matrix) == expected, "position factors changed")
    result = validate(
        dict(expected, file_sha256=sha(matrix)), read(directory / "motion.json")
    )
    freeze(directory / "validated-summary.json", result)
    return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(args.directory / "matrix-v1.json", payload(args.source, args.project))
    else:
        result = verify(args.source, args.directory, args.project)
        print(
            "POSITION_COMPONENTS_VERIFIED",
            [(r["id"], r["hit"]) for r in result["results"]],
        )
