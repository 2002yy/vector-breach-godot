"""Compare physical timelines, retaining measured discretization differences."""

import argparse
import json
from pathlib import Path


def key(row):
    return row["scheme"], row["release"], row["native_input"]


def without_clock(value):
    if isinstance(value, dict):
        return {
            name: without_clock(item)
            for name, item in value.items()
            if name not in {"frame", "input_event_usec", "consumed_usec"}
        }
    if isinstance(value, list):
        return [without_clock(item) for item in value]
    return value


def validate(slow, fast, repeat=None):
    assert len(slow["timelines"]) == len(fast["timelines"]) == 7
    result = {"timelines": [], "responses": [], "repeat_exact": repeat is not None}
    if repeat is not None:
        assert without_clock(slow) == without_clock(repeat), "same-rate simulation drift"
    for left, right in zip(slow["timelines"], fast["timelines"]):
        assert key(left) == key(right)
        apex_difference = abs(left["apex_y"] - right["apex_y"])
        land_difference = abs(left["land_time"] - right["land_time"])
        assert apex_difference <= 0.04, (key(left), "apex", apex_difference)
        assert land_difference <= 1 / 60 + 1e-6, (key(left), "landing", land_difference)
        for row in (left, right):
            jumps = [step for step in row["trace"] if step["jumped"]]
            assert len(jumps) == 1
            jump = jumps[0]
            allowed_delay = 1 / row["rate"] if row["native_input"] else 0
            assert 0.5 - 1e-6 <= jump["time"] <= 0.5 + allowed_delay + 1e-6
            assert not jump["ground_solver"] and not jump["grounded_after"]
            if row["release"]:
                previous = row["trace"][row["trace"].index(jump) - 1]
                assert abs(previous["velocity"][2] - jump["velocity"][2]) < 1e-4
        result["timelines"].append({
            "scheme": left["scheme"], "release": left["release"],
            "native_input": left["native_input"],
            "apex_difference_m": apex_difference, "land_difference_s": land_difference,
        })
    assert len(slow["responses"]) == len(fast["responses"]) == 9
    for left, right in zip(slow["responses"], fast["responses"]):
        assert (left["scheme"], left["kind"]) == (right["scheme"], right["kind"])
        for name in ("zero_time", "reverse_95_time"):
            assert abs(left[name] - right[name]) <= 2 / 60 + 1e-6
        position_difference = sum(
            (a - b) ** 2 for a, b in zip(
                left["points"][-1]["position"], right["points"][-1]["position"]
            )
        ) ** 0.5
        # Two coarse steps at the test's 6.2 m/s; report the actual error as well.
        assert position_difference <= 2 / 60 * 6.2 + 1e-6
        result["responses"].append({
            "scheme": left["scheme"], "kind": left["kind"],
            "stop_delta_s": abs(left["zero_time"] - right["zero_time"]),
            "reverse_95_delta_s": abs(left["reverse_95_time"] - right["reverse_95_time"]),
            "endpoint_difference_m": position_difference,
        })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rate60", type=Path)
    parser.add_argument("rate120", type=Path)
    parser.add_argument("--repeat60", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    load = lambda path: json.loads(path.read_text(encoding="utf-8"))
    result = validate(load(args.rate60), load(args.rate120),
                      load(args.repeat60) if args.repeat60 else None)
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("MOVEMENT_TIMELINES_OK 7 timeline pairs / 9 response pairs")


if __name__ == "__main__":
    main()
