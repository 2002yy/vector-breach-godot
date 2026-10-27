"""Audit recorded observation transitions and samples, without assigning human scores."""

import argparse
import math
from pathlib import Path

from build_native_route_study import read, sha
from movement_current_observation import validate_receipt
from validate_native_route_study import require


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def audit_samples(data, manifest, rate):
    """Check what the receipt records; this cannot prove physical human input."""
    require(rate in (60, 120), "unsupported observation physics rate")
    require(
        data["human_review"] == "pending" and data["formal_release_ready"] is False,
        "false human acceptance",
    )
    order = [point["parent_case"] for point in manifest["cases"]]
    require(
        bool(order) and len(set(order)) == len(order), "ambiguous observation points"
    )
    require(bool(data["attempts"]), "missing observation attempts")
    previous_frame, previous_usec = -1, -1
    current_index, samples, empty_attempts = 0, 0, 0
    crouch_samples, walk_samples = 0, 0
    max_speed, max_attempt_seconds = 0.0, 0.0
    observed_cases = set()
    reasons = {"session_start": 0, "retry": 0, "next_case": 0}
    for index, attempt in enumerate(data["attempts"]):
        reason = attempt["reason"]
        require(reason in reasons, "unknown observation reset reason")
        require(
            (index == 0 and reason == "session_start")
            or (index > 0 and reason in ("retry", "next_case")),
            "invalid session-start transition",
        )
        if reason == "next_case":
            current_index = (current_index + 1) % len(order)
        require(
            attempt["case"] == order[current_index], "retry/next-case binding drift"
        )
        require(
            attempt["scheme"] == manifest["observation_scheme"]
            and attempt["human_review"] == "pending",
            "frozen observation profile drift",
        )
        require(
            not attempt.get("trace_truncated", False), "truncated observation trace"
        )
        trace = attempt["trace"]
        require(
            isinstance(trace, list) and len(trace) <= 7200, "invalid trace capacity"
        )
        reasons[reason] += 1
        empty_attempts += not bool(trace)
        if trace:
            observed_cases.add(attempt["case"])
        duration = 0.0
        for sample in trace:
            frame, consumed, event = (
                sample["physics_frame"],
                sample["consumed_usec"],
                sample["input_event_usec"],
            )
            require(
                type(frame) is int and frame > previous_frame,
                "global observation physics frame rollback",
            )
            require(
                type(consumed) is int
                and consumed > previous_usec
                and type(event) is int
                and 0 <= event <= consumed,
                "invalid observation event/consumption clock",
            )
            previous_frame, previous_usec = frame, consumed
            delta = sample["delta"]
            require(
                finite_number(delta) and abs(delta - 1 / rate) <= 1e-8,
                "observation physics rate mismatch",
            )
            duration += delta
            direction = sample["direction"]
            require(
                isinstance(direction, list)
                and len(direction) == 2
                and all(finite_number(value) for value in direction)
                and math.hypot(*direction) <= 1.000001,
                "invalid observed movement direction",
            )
            for key in (
                "jump_requested",
                "jumped",
                "crouch_requested",
                "walk_requested",
                "grounded_before",
                "grounded",
            ):
                require(
                    type(sample[key]) is bool, "non-boolean observed movement state"
                )
            require(
                not sample["jumped"]
                or (sample["jump_requested"] and sample["grounded_before"]),
                "jump without request or ground support",
            )
            require(
                finite_number(sample["capsule_height"])
                and sample["capsule_height"] > 0,
                "invalid observed capsule height",
            )
            for key in ("position", "velocity"):
                require(
                    isinstance(sample[key], list)
                    and len(sample[key]) == 3
                    and all(finite_number(value) for value in sample[key]),
                    "invalid observed position/velocity",
                )
            max_speed = max(
                max_speed, math.hypot(sample["velocity"][0], sample["velocity"][2])
            )
            crouch_samples += sample["crouch_requested"]
            walk_samples += sample["walk_requested"]
            samples += 1
        max_attempt_seconds = max(max_attempt_seconds, duration)
    require(samples > 0, "empty observation trace")
    return dict(
        schema=1,
        technical_trace_audit="passed",
        human_review="pending",
        formal_release_ready=False,
        physical_human_input_verified=False,
        physics_rate=rate,
        samples=samples,
        attempts=len(data["attempts"]),
        empty_attempts=empty_attempts,
        reset_reasons=reasons,
        observed_cases=sorted(observed_cases),
        crouch_requested_samples=crouch_samples,
        walk_requested_samples=walk_samples,
        max_observed_horizontal_speed=max_speed,
        max_attempt_simulated_seconds=max_attempt_seconds,
        attempts_over_recommended_45_seconds=sum(
            sum(sample["delta"] for sample in attempt["trace"]) > 45 + 1e-8
            for attempt in data["attempts"]
        ),
    )


def audit_receipt(receipt, manifest_path, project, mode, rate):
    validation = validate_receipt(receipt, manifest_path, project, mode)
    result = audit_samples(read(receipt), read(manifest_path), rate)
    result.update(
        session_mode=mode,
        receipt_sha256=sha(receipt),
        manifest_sha256=sha(manifest_path),
        source_validation=validation,
    )
    return result


if __name__ == "__main__":
    import json

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--rate", type=int, choices=(60, 120), required=True)
    parser.add_argument(
        "--session-mode",
        choices=(
            "windowed_manual_unreviewed",
            "headless_collision_logic_smoke",
            "windowed_automated_render_smoke",
        ),
        required=True,
    )
    args = parser.parse_args()
    print(
        json.dumps(
            audit_receipt(
                args.receipt,
                args.manifest,
                args.project,
                args.session_mode,
                args.rate,
            ),
            indent=2,
        )
    )
