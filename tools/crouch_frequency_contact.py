"""Bound a frequency-sensitive wall contact before landing; never tune movement."""

import argparse
import copy
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from landing_stage_audit import stage_changes
from modern_brake_window import floor_contacts, relative_body
from movement_dimension_gates import action_gate
from native_jump_candidates import freeze, outcomes
from tactical_jump_coverage import require_unchanged_current
from validate_mirage_input_study import PHYSICS_FIELDS
from validate_native_route_study import require

VARIANTS = ("baseline", "no_pre", "no_try", "no_snap")
CASE = "crouch__modern_cs__jump"
GRAVITY = 800 * 0.0254
AIR_CAP = 30 * 0.0254


def payload(source, rejection) -> dict[str, Any]:
    data = read(source)
    require(
        data["level"] == "inferno-classic-local"
        and data["schema"] == 4
        and data["formal_qualification"] is False
        and not data.get("camera_only"),
        "wrong diagnostic parent",
    )
    parents = [p for p in data["cases"] if p["id"] == CASE]
    require(
        len(parents) == 1
        and parents[0]["scheme"] == "modern_cs"
        and parents[0]["trial_mode"] == "jump"
        and parents[0]["queued_input"]
        and parents[0]["kind"] == "crouch_jump"
        and parents[0]["ablation"] == "baseline",
        "one queued Modern jump required",
    )
    cases = []
    for variant in VARIANTS:
        point = copy.deepcopy(parents[0])
        point.update(
            id=variant,
            source_case=CASE,
            ablation=variant,
            rejection_path=str(rejection),
        )
        cases.append(point)
    return dict(
        data,
        cases=cases,
        stage="frozen_crouch_stage_ablation",
        parent_sha256=sha(source),
        diagnostic_only=True,
        native_acceptance=False,
    )


def aligned_end_states(left, right):
    """Samples name the tick start; compare states after equally long physics time."""
    require(len(right) == 2 * len(left) and left, "60/120 trace lengths differ")
    pairs = []
    for index, a in enumerate(left):
        b = right[2 * index + 1]
        end = (index + 1) / 60
        require(
            abs(a["time"] + 1 / 60 - end) < 1e-6
            and abs(b["time"] + 1 / 120 - end) < 1e-6,
            "unaligned physical endpoints",
        )
        pairs.append(
            dict(
                end_seconds=end,
                position_delta_m=math.dist(a["position"], b["position"]),
                horizontal_velocity_delta_mps=math.hypot(
                    a["velocity"][0] - b["velocity"][0],
                    a["velocity"][2] - b["velocity"][2],
                ),
            )
        )
    return pairs


def first_air_contact(row, rate, root_name) -> dict[str, Any]:
    trace = row["trace"]
    takeoffs = [i for i, s in enumerate(trace) if s["jumped"]]
    require(len(takeoffs) == 1, "single actual takeoff required")
    landing = row["landing"]
    require(landing, "first landing required for bounded contact analysis")
    for i in range(takeoffs[0] + 1, len(trace)):
        sample = trace[i]
        if sample["time"] > landing["time"]:
            break
        previous = trace[i - 1]
        for contact in sample["contacts"]:
            normal = contact["normal"]
            require(
                len(normal) == 3
                and all(math.isfinite(v) for v in normal)
                and abs(math.sqrt(sum(v * v for v in normal)) - 1) < 0.02,
                "invalid contact normal",
            )
            body = relative_body(contact["body"])
            require(
                body.split("/")[0] == root_name, "contact outside frozen collision root"
            )
            opposition = (
                normal[0] * previous["velocity"][0]
                + normal[2] * previous["velocity"][2]
            )
            if (
                not sample["grounded_before"]
                and abs(normal[1]) < 0.7
                and opposition < -0.1
            ):
                incoming = list(previous["velocity"])
                incoming[1] -= GRAVITY / rate
                dot = sum(a * b for a, b in zip(incoming, normal))
                projected = [v - n * min(dot, 0) for v, n in zip(incoming, normal)]
                changed = [
                    s["stage"]
                    for s in sample["stages"]
                    if s["before"]["position"] != s["after"]["position"]
                    or s["before"]["velocity"] != s["after"]["velocity"]
                    or s["before"]["grounded"] != s["after"]["grounded"]
                ]
                return dict(
                    observed=True,
                    tick=i,
                    tick_start_seconds=sample["time"],
                    physics_interval_end_seconds=sample["time"] + 1 / rate,
                    body=body,
                    normal=normal,
                    incoming_horizontal_mps=math.hypot(incoming[0], incoming[2]),
                    outgoing_horizontal_mps=math.hypot(
                        sample["velocity"][0], sample["velocity"][2]
                    ),
                    contact_projection_horizontal_error_mps=math.hypot(
                        projected[0] - sample["velocity"][0],
                        projected[2] - sample["velocity"][2],
                    ),
                    changed_auxiliary_stages=changed,
                    air_projection_cap_mps=AIR_CAP,
                    outgoing_above_air_projection_cap=math.hypot(
                        sample["velocity"][0], sample["velocity"][2]
                    )
                    > AIR_CAP,
                    scope="recorded_contact_plane_projection_not_complete_solver_reimplementation",
                )
    return dict(observed=False)


def inspect(point, row, rate, root_name) -> dict[str, Any]:
    action = action_gate(point, row, rate)
    result = outcomes(point, row)
    changes = stage_changes(row, point)
    takeoff = next(s for s in row["trace"] if s["jumped"])
    landing = row["landing"]
    return dict(
        action=action,
        first_landing=result["first_landing"],
        takeoff_seconds=takeoff["time"],
        landing_tick_start_seconds=landing["time"],
        first_air_lateral_contact=first_air_contact(row, rate, root_name),
        landing_contacts=floor_contacts(row),
        prelanding_stage_changes=[
            e for e in changes if takeoff["time"] <= e["time"] <= landing["time"]
        ],
    )


def identical_prefix(a, b, through):
    left = [s for s in a["trace"] if s["time"] <= through + 1e-6]
    right = [s for s in b["trace"] if s["time"] <= through + 1e-6]
    return [[s[k] for k in PHYSICS_FIELDS] for s in left] == [
        [s[k] for k in PHYSICS_FIELDS] for s in right
    ]


def source_lock(source, directory):
    return dict(
        schema=1,
        manifest_sha256=sha(source),
        reports={str(r): sha(source.parent / f"inferno-{r}.json") for r in (60, 120)},
        matrix_sha256=sha(directory / "matrix-v1.json"),
    )


def evaluate(source, directory, project) -> dict[str, Any]:
    require(
        read(directory / "source-lock.json") == source_lock(source, directory),
        "source or matrix changed",
    )
    matrix = directory / "matrix-v1.json"
    require(
        read(matrix) == payload(source, directory / "rejected.json"),
        "frozen ablation inputs changed",
    )
    root_name = Path(read(source)["identity"]["collision_path"]).stem
    observations, rows, sources = {}, {}, {}
    original = {}
    for rate in (60, 120):
        _, old = checked(source, source.parent / f"inferno-{rate}.json", rate, project)
        points, rows[rate] = checked(
            matrix, directory / f"inferno-{rate}.json", rate, project
        )
        original[rate] = old[CASE]
        require_unchanged_current(old[CASE], rows[rate]["baseline"])
        observations[str(rate)] = {}
        critical_end = first_air_contact(original[60], 60, root_name).get(
            "physics_interval_end_seconds"
        )
        if critical_end is None:
            raise ValueError("reference 60Hz contact interval missing")
        through = critical_end - 1 / rate
        for variant in VARIANTS:
            observation = inspect(points[variant], rows[rate][variant], rate, root_name)
            observation["prefix_through_shared_contact_interval_identical"] = (
                identical_prefix(old[CASE], rows[rate][variant], through)
            )
            observations[str(rate)][variant] = observation
        sources[str(rate)] = sha(directory / f"inferno-{rate}.json")
    pairs = aligned_end_states(original[60]["trace"], original[120]["trace"])
    comparisons = {}
    for variant in VARIANTS:
        a, b = (rows[r][variant]["landing"] for r in (60, 120))
        comparisons[variant] = dict(
            first_landing_delta_m=math.dist(a["position"], b["position"]),
            first_landing_time_delta_seconds=abs(a["time"] - b["time"]),
        )
    return dict(
        schema=1,
        observations=observations,
        comparisons=comparisons,
        aligned_end_states=pairs,
        source_reports_sha256=sources,
        baseline_physical_traces_identical=True,
        new_native_trials=8,
        formal_release_ready=False,
        human_acceptance=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        production_changed=False,
        scope="one_frozen_Modern_jump_not_triangle_identity_or_collision_repair",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.mode == "freeze":
        freeze(
            args.directory / "matrix-v1.json",
            payload(args.source, args.directory / "rejected.json"),
        )
        freeze(
            args.directory / "source-lock.json",
            source_lock(args.source, args.directory),
        )
    else:
        result = evaluate(args.source, args.directory, args.project)
        freeze(args.out or args.directory / "validated-summary.json", result)
        print(
            "CROUCH_CONTACT_VERIFIED",
            result["new_native_trials"],
            result["comparisons"],
        )


if __name__ == "__main__":
    main()
