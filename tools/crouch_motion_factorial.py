"""Freeze common-time position/velocity factors for read-only capsule motion queries."""

import argparse
import math
from pathlib import Path
from typing import Any

from build_native_route_study import read, sha
from edge_drop_revision import checked
from native_jump_candidates import freeze
from validate_native_route_study import require

PROBE = "tools/authoring/probe_crouch_motion.gd"
CASE = "crouch__modern_cs__jump"
END = 7 / 60
GRAVITY = 800 * 0.0254


def state(row, rate):
    samples = [s for s in row["trace"] if abs(s["time"] + 1 / rate - END) < 1e-6]
    require(len(samples) == 1, "common physics end state missing")
    s = samples[0]
    require(
        not s["grounded_after"]
        and s["crouching"]
        and abs(s["capsule_height"] - 1.2) < 1e-5,
        "airborne crouched state required",
    )
    return dict(
        position=s["position"],
        velocity=s["velocity"],
        sample_tick_start=s["time"],
        state_end_seconds=END,
    )


def build_cases(states):
    require(set(states) == {60, 120}, "both state factors required")
    return [
        dict(
            id=f"p{p}_v{v}__{schedule}",
            position_rate=p,
            velocity_rate=v,
            position=states[p]["position"],
            velocity=states[v]["velocity"],
            steps=steps,
        )
        for p in (60, 120)
        for v in (60, 120)
        for schedule, steps in (("single", [1 / 60]), ("split", [1 / 120, 1 / 120]))
    ]


def payload(source, project):
    data = read(source)
    require(
        data["level"] == "inferno-classic-local"
        and data["schema"] == 4
        and data["formal_qualification"] is False,
        "wrong frozen map",
    )
    states, reports = {}, {}
    contact = None
    for rate in (60, 120):
        report = source.parent / f"inferno-{rate}.json"
        points, rows = checked(source, report, rate, project)
        require(
            points[CASE]["scheme"] == "modern_cs"
            and points[CASE]["kind"] == "crouch_jump",
            "frozen Modern crouch required",
        )
        states[rate] = state(rows[CASE], rate)
        reports[str(rate)] = sha(report)
        if rate == 60:
            matches = [s for s in rows[CASE]["trace"] if abs(s["time"] - END) < 1e-6]
            require(
                len(matches) == 1 and matches[0]["contacts"], "original contact missing"
            )
            contact = matches[0]["contacts"][0]
    return dict(
        schema=1,
        level=data["level"],
        identity=data["identity"],
        parent_sha256=sha(source),
        reports_sha256=reports,
        probe_sha256=sha(project / PROBE),
        gravity=GRAVITY,
        common_state_end_seconds=END,
        horizon_seconds=1 / 60,
        capsule=dict(radius=0.4, height=1.2, local_y=-0.3),
        states={str(r): s for r, s in states.items()},
        original_contact=contact,
        cases=build_cases(states),
        formal_release_ready=False,
        scope="free_flight_body_test_motion_stop_at_first_hit_not_move_and_slide",
    )


def validate(matrix, report) -> dict[str, Any]:
    require(
        report["schema"] == 1
        and report["matrix_sha256"] == matrix["file_sha256"]
        and report["identity"] == matrix["identity"]
        and report["probe_sha256"] == matrix["probe_sha256"],
        "motion receipt scope mismatch",
    )
    require(
        math.isclose(report["safe_margin"], 0.001, abs_tol=1e-8), "changed query margin"
    )
    cases = {p["id"]: p for p in matrix["cases"]}
    rows = report["results"]
    require(
        len(rows) == len(cases) == 8 and {r["id"] for r in rows} == set(cases),
        "incomplete factorial coverage",
    )
    summaries = []
    for row in rows:
        point = cases[row["id"]]
        require(row["initial_overlaps"] == [], "query starts inside collision")
        require(row["body_origin_unchanged"] is True, "read-only query moved body")
        position = list(point["position"])
        velocity = list(point["velocity"])
        steps = row["steps"]
        require(0 < len(steps) <= len(point["steps"]), "missing query steps")
        hit = False
        for index, s in enumerate(steps):
            dt = point["steps"][index]
            velocity[1] -= matrix["gravity"] * dt
            motion = [v * dt for v in velocity]
            require(
                abs(s["delta"] - dt) < 1e-10
                and math.dist(s["from"], position) < 1e-5
                and math.dist(s["motion"], motion) < 1e-5,
                "query path differs from frozen integration",
            )
            require(
                0 <= s["safe_fraction"] <= s["unsafe_fraction"] <= 1,
                "invalid motion fractions",
            )
            hit = bool(s["contacts"])
            require(s["hit"] is hit, "forged motion hit")
            if hit:
                require(index == len(steps) - 1, "query continued after first hit")
            else:
                require(
                    s["safe_fraction"] == 1 and s["unsafe_fraction"] == 1,
                    "clear query truncated",
                )
            position = [a + b for a, b in zip(position, motion)]
        require(
            hit or len(steps) == len(point["steps"]), "clear query ended before horizon"
        )
        contacts = steps[-1]["contacts"] if hit else []
        for c in contacts:
            require(
                c["shape_index"] >= 0
                and c["body"].startswith("player_collision/")
                and c["body"].endswith("/RuntimeCollision"),
                "unbound collider shape",
            )
            ray = c["face_ray"]
            validate_faces(ray)
            if ray["matched"]:
                require(
                    ray["body"] == c["body"]
                    and ray["shape_index"] == c["shape_index"]
                    and ray["face_index"] >= 0
                    and ray["normal_dot"] > 0.99
                    and ray["position_error_m"] < 0.002,
                    "unbound corroborating face",
                )
        summaries.append(
            dict(
                id=row["id"],
                hit=hit,
                steps=len(steps),
                contacts=[
                    dict(
                        body=c["body"],
                        shape_index=c["shape_index"],
                        normal=c["normal"],
                        face_ray=c["face_ray"],
                    )
                    for c in contacts
                ],
            )
        )
    validate_faces(report["original_contact_face"])
    return dict(
        schema=1,
        results=summaries,
        original_contact_face=report["original_contact_face"],
        actual_safe_margin=report["safe_margin"],
        formal_release_ready=False,
        collision_fixed=False,
        precision_equivalence_accepted=False,
        movement5_frozen=True,
        scope=matrix["scope"],
    )


def validate_faces(ray):
    proof = ray.get("shape_triangles", {})
    if not proof.get("bound"):
        return
    candidates = proof["candidates"]
    digest = proof["shape_faces_sha256"]
    require(
        len(digest) == 64 and all(c in "0123456789abcdef" for c in digest),
        "invalid shape hash",
    )
    require(proof["unique"] is (len(candidates) == 1), "forged unique face")
    indices = [p["triangle_index"] for p in candidates]
    require(
        len(set(indices)) == len(indices)
        and all(
            type(i) in (int, float)
            and math.isfinite(i)
            and int(i) == i
            and 0 <= i < proof["triangle_count"]
            for i in indices
        ),
        "triangle index outside frozen shape",
    )
    for candidate in candidates:
        require(
            math.isfinite(candidate["distance_m"])
            and 0 <= candidate["distance_m"] <= 0.002
            and math.isfinite(candidate["edge_distance_m"])
            and candidate["edge_distance_m"] >= 0,
            "triangle candidate outside contact neighborhood",
        )
        normal = candidate["normal"]
        require(
            len(normal) == 3
            and all(math.isfinite(v) for v in normal)
            and abs(math.sqrt(sum(v * v for v in normal)) - 1) < 0.02,
            "invalid triangle normal",
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "verify"))
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    path = args.directory / "matrix-v1.json"
    expected = payload(args.source, args.project)
    if args.mode == "freeze":
        freeze(path, expected)
    else:
        require(read(path) == expected, "frozen factors or source changed")
        summary = validate(
            dict(expected, file_sha256=sha(path)), read(args.directory / "motion.json")
        )
        freeze(args.directory / "validated-summary.json", summary)
        print(
            "CROUCH_MOTION_VERIFIED", [(r["id"], r["hit"]) for r in summary["results"]]
        )


if __name__ == "__main__":
    main()
