"""Describe observed recovery intervals without inferring physical reachability."""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path


def vector(value):
    return tuple(float(part.strip()) for part in value.strip("()").split(","))


def distance(first, second):
    return math.dist(vector(first), vector(second))


def dropped_runs(rows):
    runs, current = [], []
    for row in rows:
        eligible = (
            row["round_state"] == "Live"
            and row["c4_state"] == "dropped"
            and any(a["team"] == "T" and not a["dead"] for a in row["actors"])
        )
        contiguous = not current or (
            row["serial"] == current[-1]["serial"]
            and row["frame"] == current[-1]["frame"] + 60
        )
        if eligible and contiguous:
            current.append(row)
        else:
            if current:
                runs.append(current)
            current = [row] if eligible else []
    if current:
        runs.append(current)
    return runs


def analyze(rows):
    run = max(dropped_runs(rows), key=len, default=[])
    samples, groups = [], []
    for row in run:
        owner = next((a for a in row["actors"] if a["lease_owner"]), None)
        if owner is None:
            samples.append(dict(frame=row["frame"], owner=None))
            continue
        state = owner["snapshot"]
        sample = dict(
            frame=row["frame"],
            remaining=row["remaining"],
            owner=owner["name"],
            team=owner["team"],
            state=state["state"],
            position=owner["position"],
            distance_m=distance(owner["position"], row["c4_position"]),
            enemy=owner["enemy"],
            visible_seconds=state["target_visible_seconds"],
            path_nodes=state["navigation_path_nodes"],
            path_index=owner["path_index"],
            blocked=state["route_blocked"],
            unreachable=owner["unreachable"],
            stalled_seconds=state["route_stalled_seconds"],
            reason=state["tactical_reason"],
        )
        samples.append(sample)
    for sample in samples:
        if not groups or groups[-1][-1]["owner"] != sample["owner"]:
            groups.append([])
        groups[-1].append(sample)
    segments = []
    for group in groups:
        if group[0]["owner"] is None:
            segments.append(dict(owner=None, samples=len(group)))
            continue
        steps = [
            distance(a["position"], b["position"]) for a, b in zip(group, group[1:])
        ]
        segments.append(
            dict(
                owner=group[0]["owner"],
                frame_start=group[0]["frame"],
                frame_end=group[-1]["frame"],
                samples=len(group),
                sampled_span_seconds=(group[-1]["frame"] - group[0]["frame"]) / 60,
                states=dict(Counter(s["state"] for s in group)),
                visible_samples=sum(s["visible_seconds"] > 0 for s in group),
                sampled_travel_m=sum(steps),
                stationary_pairs_under_005m=sum(step < 0.05 for step in steps),
                distance_start_m=group[0]["distance_m"],
                distance_end_m=group[-1]["distance_m"],
                path_nodes_start=group[0]["path_nodes"],
                path_nodes_end=group[-1]["path_nodes"],
                blocked_samples=sum(s["blocked"] for s in group),
                unreachable_samples=sum(s["unreachable"] for s in group),
                stalled_peak_seconds=max(s["stalled_seconds"] for s in group),
            )
        )
    following = next(
        (r for r in rows if run and r["frame"] == run[-1]["frame"] + 60), None
    )
    return dict(
        serial=run[0]["serial"] if run else None,
        sample_count=len(run),
        segments=segments,
        samples=samples,
        following=dict(
            frame=following["frame"],
            c4_state=following["c4_state"],
            carriers=[
                a["name"] for a in following["actors"] if a["snapshot"]["bomb_carrier"]
            ],
        )
        if following
        else None,
        limits="One-second sampled displacement is a lower bound; enemy label is not visibility; graph progress is not proof of necessary/physical route; no exact lease-transfer cause or pickup time inferred.",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = args.source.read_bytes()
    result = analyze([json.loads(line) for line in raw.decode("utf8").splitlines()])
    result["source_sha256"] = hashlib.sha256(raw).hexdigest()
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )
    print(
        json.dumps(
            {k: result[k] for k in ("serial", "sample_count", "segments", "following")},
            ensure_ascii=True,
        )
    )
