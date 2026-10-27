"""Freeze common prelanding factors for bounded original-map capsule queries."""

import argparse
import math
from pathlib import Path

from build_native_route_study import read, sha
from crouch_motion_factorial import build_cases, validate_faces
from edge_drop_revision import checked
from native_jump_candidates import freeze
from validate_native_route_study import require

PROBE = "tools/authoring/probe_mirage_landing_motion.gd"
PARENT = "tools/authoring/probe_crouch_motion.gd"
END = 11 / 12
GRAVITY = 800 * 0.0254


def state(row, rate):
    samples = [s for s in row["trace"] if abs(s["time"] + 1 / rate - END) < 1e-6]
    require(len(samples) == 1, "common precontact state missing")
    s = samples[0]
    require(
        not s["grounded_after"]
        and s["crouching"]
        and abs(s["capsule_height"] - 1.2) < 1e-5,
        "airborne crouch required",
    )
    require(s["velocity"][1] < 0, "descending pre-snap state required")
    return dict(position=s["position"], velocity=s["velocity"], state_end_seconds=END)


def payload(directory, project):
    source = directory / "mirage-matrix-v1.json"
    data = read(source)
    require(
        data["level"] == "mirage-classic-local"
        and data["schema"] == 4
        and data["formal_qualification"] is False,
        "wrong physical map",
    )
    states, reports = {}, {}
    contact = None
    for rate in (60, 120):
        report = directory / f"mirage-{rate}.json"
        points, rows = checked(source, report, rate, project)
        point = points["vertical__jump"]
        require(
            point["vertical_enabled"] is True
            and point["quadrature_enabled"] is True
            and point["scheme"] == "modern_cs",
            "vertical Modern source required",
        )
        row = rows[point["id"]]
        states[rate] = state(row, rate)
        reports[str(rate)] = sha(report)
        if rate == 120:
            contact = row["landing"]["contacts"][0]
    return dict(
        schema=1,
        level=data["level"],
        identity=data["identity"],
        source_sha256=sha(source),
        reports_sha256=reports,
        probe_sha256=sha(project / PROBE),
        parent_probe_sha256=sha(project / PARENT),
        gravity=GRAVITY,
        common_state_end_seconds=END,
        horizon_seconds=1 / 60,
        capsule=dict(radius=0.4, height=1.2, local_y=-0.3),
        states={str(r): s for r, s in states.items()},
        original_contact=contact,
        cases=build_cases(states),
        formal_release_ready=False,
        scope="midpoint_gravity_body_test_motion_first_contact_not_move_and_slide",
    )


def validate(matrix, report):
    require(
        report["schema"] == 1
        and report["matrix_sha256"] == matrix["file_sha256"]
        and report["probe_sha256"] == matrix["probe_sha256"]
        and report["identity"] == matrix["identity"],
        "query identity changed",
    )
    require(abs(report["safe_margin"] - 0.001) < 1e-8, "query margin changed")
    points = {p["id"]: p for p in matrix["cases"]}
    rows = report["results"]
    require(
        len(rows) == len(points) == 8 and {r["id"] for r in rows} == set(points),
        "factor coverage incomplete",
    )
    summaries = []
    for row in rows:
        point = points[row["id"]]
        require(
            not row["initial_overlaps"] and row["body_origin_unchanged"] is True,
            "query overlap or body mutation",
        )
        position, velocity = list(point["position"]), list(point["velocity"])
        steps = row["steps"]
        require(0 < len(steps) <= len(point["steps"]), "query step count differs")
        elapsed = 0.0
        hit = False
        for index, step in enumerate(steps):
            dt = point["steps"][index]
            velocity[1] -= matrix["gravity"] * dt / 2
            motion = [v * dt for v in velocity]
            require(
                abs(step["delta"] - dt) < 1e-10
                and math.dist(step["from"], position) < 1e-5
                and math.dist(step["motion"], motion) < 1e-5,
                "midpoint query path changed",
            )
            require(
                0 <= step["safe_fraction"] <= step["unsafe_fraction"] <= 1,
                "invalid motion fraction",
            )
            hit = bool(step["contacts"])
            require(step["hit"] is hit, "forged query hit")
            if hit:
                require(index == len(steps) - 1, "query continued after first hit")
            else:
                require(
                    step["safe_fraction"] == step["unsafe_fraction"] == 1,
                    "clear query truncated",
                )
            elapsed += dt
            position = [a + b for a, b in zip(position, motion)]
            velocity[1] -= matrix["gravity"] * dt / 2
        require(hit or len(steps) == len(point["steps"]), "clear horizon incomplete")
        for step in steps:
            snap = step["snap_query"]
            if snap["ray_hit"]:
                require(
                    math.isfinite(snap["gap_m"])
                    and len(snap["normal"]) == 3
                    and abs(math.sqrt(sum(v * v for v in snap["normal"])) - 1) < 1e-4,
                    "invalid snap ray geometry",
                )
                require(
                    snap["body"].startswith("player_collision/"), "unbound snap body"
                )
                require(
                    snap["eligible"]
                    is (
                        0 <= snap["gap_m"] <= 0.45
                        and snap["normal"][1] >= math.cos(math.pi / 4)
                    ),
                    "forged snap eligibility",
                )
            else:
                require(snap["eligible"] is False, "empty snap ray accepted")
        contacts = steps[-1]["contacts"] if hit else []
        for c in contacts:
            require(
                c["shape_index"] >= 0
                and c["body"].startswith("player_collision/")
                and c["body"].endswith("/RuntimeCollision"),
                "unbound body contact",
            )
            validate_faces(c["face_ray"])
        summaries.append(
            dict(
                id=row["id"],
                hit=hit,
                steps=len(steps),
                hit_step_end_seconds=END + elapsed if hit else None,
                safe_fraction=steps[-1]["safe_fraction"],
                contact_groups=[c["body"] for c in contacts],
                contact_normals=[c["normal"] for c in contacts],
                snap_eligible_steps=[
                    i for i, s in enumerate(steps) if s["snap_query"]["eligible"]
                ],
                snap_gaps_m=[s["snap_query"].get("gap_m") for s in steps],
            )
        )
    validate_faces(report["original_contact_face"])
    return dict(
        schema=1,
        queries=8,
        results=summaries,
        formal_release_ready=False,
        scope=matrix["scope"],
        gameplay_replays=0,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    expected = payload(args.source, args.project)
    path = args.directory / "matrix-v1.json"
    if args.mode == "freeze":
        freeze(path, expected)
    else:
        require(read(path) == expected, "frozen precontact factors changed")
        result = validate(
            dict(expected, file_sha256=sha(path)), read(args.directory / "motion.json")
        )
        freeze(args.directory / "validated-summary.json", result)
        print("MIRAGE_LANDING_MOTION_VERIFIED", result["queries"])
