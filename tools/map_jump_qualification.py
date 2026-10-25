"""Per-point qualification policy. Receipts bind frozen inputs and raw evidence."""

import hashlib
import math
from copy import deepcopy
from pathlib import Path

STATUSES = {"qualified_jump", "walk_only", "blocked_direct_route", "route_unproven"}
KINDS = {"ordinary", "critical_landing", "edge", "run_up", "crouch_jump"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def close_vector(left, right, tolerance=0.0001):
    return (len(left) == len(right) == 3 and
            all(isinstance(x, (int, float)) and math.isfinite(x) for x in left + right) and
            math.dist(left, right) <= tolerance)


def clear_corridor(point, proof):
    height = 1.2 if point["kind"] == "crouch_jump" else 1.8
    require(math.isclose(proof.get("capsule_radius", 0), 0.4, abs_tol=1e-6) and
            math.isclose(proof.get("capsule_height", 0), height, abs_tol=1e-6),
            "wrong body shape")
    require(proof.get("foot_clearance") == 0.04, "wrong body clearance")
    arcs = proof.get("arcs", [])
    require(len(arcs) == 4 and {a["lift"] for a in arcs} == {0.0, 0.8, 1.2, 1.7},
            "incomplete body corridor envelope")
    clear = False
    blocked = True
    for arc in arcs:
        segments = arc.get("segments", [])
        steps = arc.get("steps", 0)
        require(isinstance(steps, int) and steps >= 32 and 0 < len(segments) <= steps,
                "missing body sweep segments")
        expected_start = list(point["start"])
        expected_start[1] += height / 2 + 0.04 - 0.9
        expected_goal = list(point["target_feet"])
        expected_goal[1] += height / 2 + 0.04
        require(close_vector(segments[0]["from"], expected_start), "corridor start mismatch")
        previous = segments[0]["from"]
        for index, segment in enumerate(segments):
            require(close_vector(segment["from"], previous), "discontinuous body sweep")
            require(math.dist(segment["from"], segment["to"]) <= 0.3,
                    "body sweep skipped intermediate space")
            for value, tick in ((segment["from"], index), (segment["to"], index + 1)):
                t = tick / steps
                expected = [a + (b - a) * t for a, b in zip(expected_start, expected_goal)]
                expected[1] += 4 * arc["lift"] * t * (1 - t)
                require(close_vector(value, expected), "body sweep does not match frozen corridor")
            require(0 <= segment["free_fraction"] <= 1, "bad sweep fraction")
            previous = segment["to"]
        observed_clear = (len(segments) == steps and
                          all(s["initial_clear"] is True and s["free_fraction"] >= 0.999
                              for s in segments))
        require(arc["clear"] is observed_clear, "forged clear corridor summary")
        if observed_clear:
            require(close_vector(previous, expected_goal), "corridor goal mismatch")
            clear = True
        normal = segments[-1].get("normal", [0, 0, 0])
        if arc["lift"] > 0:
            delta = [b - a for a, b in zip(expected_start, expected_goal)]
            length = math.sqrt(sum(v * v for v in delta))
            opposing = (length > 0 and len(normal) == 3 and
                        sum(n * d for n, d in zip(normal, delta)) / length < -0.1)
            blocked &= (not observed_clear and len(normal) == 3 and abs(normal[1]) < 0.3
                        and math.hypot(normal[0], normal[2]) > 0.9 and opposing)
    return clear, blocked


def success(row, jumping):
    if not row.get("target_reached", False):
        return False
    require(row.get("start_valid") is True and row.get("support") and
            row.get("supported_by_frozen_collision") is True, "unbacked target success")
    require(row.get("trace"), "missing physical trace")
    if jumping:
        require(row.get("jumped") is True and row.get("airborne") is True and
                row.get("landed") is True and any(s["jumped"] for s in row["trace"]),
                "jump success without actual takeoff")
    else:
        require(row.get("jumped") is False and not any(s["jumped"] for s in row["trace"]),
                "no-jump control actually jumped")
        require(row.get("target_entry", {}).get("grounded_after") is True,
                "control lacks grounded target entry")
    return True


def assess(point, channel_reports, jump_reports):
    require(set(channel_reports) == set(jump_reports) == {60, 120},
            "both physical rates required")
    corridors, walls, walking, jumping = [], [], [], []
    for rate in (60, 120):
        evidence = channel_reports[rate]
        clear, wall = clear_corridor(point, evidence["corridor"])
        corridors.append(clear)
        walls.append(wall)
        controls = evidence.get("controls", [])
        outcomes = []
        for mode in ("no_jump", "walk"):
            rows = [r for r in controls if r.get("scheme") == "current" and r.get("mode") == mode]
            require(len(rows) == 1, "missing or duplicate no-jump/walk control")
            row = rows[0]
            require(row.get("id") == point["id"] and row.get("applied_timeline"),
                    "wrong control point or missing inputs")
            expected_timeline = deepcopy(point["timeline"])
            for event in expected_timeline:
                event["jump"] = False
                event["walk"] = mode == "walk"
            require(row["applied_timeline"] == expected_timeline, "wrong control input policy")
            trace = row.get("trace", [])
            require(row.get("start_valid") is True and row.get("jumped") is False and trace
                    and not any(s["jumped"] for s in trace), "invalid no-jump control execution")
            require(abs(trace[0]["time"]) < 1e-6 and
                    trace[-1]["time"] >= point["duration"] - 2 / rate - 1e-6 and
                    all(abs(b["time"] - a["time"] - 1 / rate) < 1e-6
                        for a, b in zip(trace, trace[1:])), "incomplete control timeline")
            outcomes.append(success(row, False))
        walking.append(any(outcomes))
        rows = [r for r in jump_reports[rate] if r.get("id") == point["id"]
                and r.get("scheme") == "current"]
        require(len(rows) == 1, "missing reference jump")
        jumping.append(success(rows[0], True))
    if all(walking) and all(corridors):
        return "walk_only", "Reference Current reaches the target without jump at both rates."
    if not any(walking) and all(corridors) and all(jumping):
        return "qualified_jump", "Body corridor and actual reference jump verified; no-jump controls fail."
    if all(walls) and not any(walking) and not any(jumping):
        return "blocked_direct_route", "All bounded body corridors stop at lateral collision; controls fail."
    return "route_unproven", "Corridor, reference jump and control evidence do not establish qualification."


def validate_review(review, directory, manifests, digests, load):
    require(isinstance(review, dict) and review.get("schema") == 2,
            "qualification schema 2 required")
    require("complete" not in review, "aggregate complete is not qualification evidence")
    points = review.get("points", [])
    require(set(manifests) == {"dust2", "mirage", "inferno"}, "three-map coverage required")
    for manifest in manifests.values():
        require(manifest.get("schema") == 1 and len(manifest["cases"]) == 5 and
                {p["id"] for p in manifest["cases"]} == KINDS and
                all(p["kind"] == p["id"] for p in manifest["cases"]),
                "five-role coverage required for each map")
    expected = {(name, p["id"]) for name, m in manifests.items() for p in m["cases"]}
    require(len(points) == len(expected) and
            {(p.get("map"), p.get("case")) for p in points} == expected,
            "qualification point coverage incomplete or duplicated")
    archive = directory.parent.resolve()
    cache = {}
    validated = []
    for record in points:
        name, case = record["map"], record["case"]
        manifest = manifests[name]
        point = next(p for p in manifest["cases"] if p["id"] == case)
        require(record.get("manifest_sha256") == digests[name] and
                record.get("level") == manifest["level"], "point identity mismatch")
        require(record.get("status") in STATUSES and isinstance(record.get("reason"), str)
                and record["reason"].strip(), "missing status or reason")
        refs = record.get("evidence", [])
        require(len(refs) == 4, "two corridor/control and two jump receipts required")
        channels, jumps = {}, {}
        for ref in refs:
            relative = Path(ref["file"])
            require(not relative.is_absolute(), "absolute evidence reference forbidden")
            path = (archive / relative).resolve()
            require(path.is_relative_to(archive) and path.is_file(), "missing/outside evidence")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            require(digest == ref.get("sha256"), "evidence hash mismatch")
            if path not in cache:
                cache[path] = load(path)
            data = cache[path]
            require(data.get("manifest_sha256") == digests[name] and
                    data.get("level") == manifest["level"] and
                    data.get("identity") == manifest["identity"], "evidence scope mismatch")
            rate = data.get("physics_hz")
            require(rate in (60, 120), "unsupported evidence rate")
            if data.get("kind") == "map_jump_qualification_evidence_v1":
                require(rate not in channels, "duplicate channel evidence")
                rows = [p for p in data.get("points", []) if p.get("case") == case]
                require(len(rows) == 1, "missing point body evidence")
                channels[rate] = rows[0]
            else:
                require(rate not in jumps and data.get("schema") == 1,
                        "duplicate or unknown jump evidence")
                require(path == (directory / f"{name}-{rate}.json").resolve(),
                        "jump receipt is not the audited matrix artifact")
                jumps[rate] = data.get("results", [])
        derived, reason = assess(point, channels, jumps)
        require(record["status"] == derived, "claimed qualification contradicts evidence")
        validated.append({"map": name, "case": case, "status": derived, "reason": reason})
    eligible = all(p["status"] in {"qualified_jump", "walk_only"} for p in validated)
    # Walking alone cannot certify a jumping corpus.
    eligible &= all(any(p["map"] == name and p["status"] == "qualified_jump"
                        for p in validated) for name in manifests)
    return {"schema": 2, "validated_points": validated, "eligible": eligible}


def validate_revision(child_directory, review_path, manifests, digests, qualified, load):
    freeze = load(child_directory / "freeze.json")
    require(freeze.get("schema") == 2 and set(freeze.get("maps", {})) == set(manifests),
            "new revision freeze requires all maps")
    certificate = hashlib.sha256(review_path.read_bytes()).hexdigest()
    result = {"schema": 2, "trials": 0, "reached": 0, "cases_per_map": {}, "failures": []}
    for name, parent in manifests.items():
        path = child_directory / f"{name}-manifest.json"
        child = load(path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        expected = [point for point in parent["cases"] if any(
            p["map"] == name and p["case"] == point["id"] and p["status"] == "qualified_jump"
            for p in qualified["validated_points"])]
        require(expected and child.get("cases") == expected,
                "qualified revision changed/dropped inputs or added unqualified points")
        require(child.get("schema") == 2 and child.get("revision") == "movement4-r1-qualified-v2" and
                child.get("parent_manifest_sha256") == digests[name] and
                child.get("qualification_sha256") == certificate and
                child.get("identity") == parent["identity"] and
                child.get("level") == parent["level"], "qualified revision lineage mismatch")
        require(freeze["maps"][name]["sha256"] == digest, "qualified revision hash mismatch")
        result["cases_per_map"][name] = len(expected)
        for rate in (60, 120):
            report = load(child_directory / f"{name}-{rate}.json")
            require(report.get("manifest_sha256") == digest and
                    report.get("identity") == child["identity"] and
                    report.get("level") == child["level"] and report.get("physics_hz") == rate,
                    "new manifest requires its own new matrix")
            rows = report.get("results", [])
            combinations = {(p["id"], s) for p in expected
                            for s in ("current", "legacy_16", "modern_cs")}
            require(len(rows) == len(combinations) and
                    {(r["id"], r["scheme"]) for r in rows} == combinations,
                    "qualified matrix coverage incomplete")
            for row in rows:
                require(row.get("start_valid") is True and row.get("jumped") is True and
                        row.get("airborne") is True, "invalid qualified replay")
                require(row["target_reached"] == (row["reason"] == "reached"),
                        "replay score contradicts reason")
                result["trials"] += 1
                if success(row, True):
                    result["reached"] += 1
                else:
                    result["failures"].append({"map": name, "case": row["id"],
                        "scheme": row["scheme"], "rate": rate, "reason": row["reason"]})
    result["all_variants_reached"] = result["trials"] == result["reached"]
    return result
