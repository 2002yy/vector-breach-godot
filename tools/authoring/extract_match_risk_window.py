"""Extract sampled C4/death evidence without inferring recovery ownership."""

import argparse
import hashlib
import json
import math
from pathlib import Path


def compact(row):
    c4 = tuple(float(x) for x in row["c4_position"].strip("()").split(","))
    nearest = []
    for actor in row["actors"]:
        if actor["team"] != "T" or not actor["alive"]:
            continue
        position = [actor[axis] for axis in ("x", "y", "z")]
        ai = actor["ai"]
        nearest.append(
            dict(
                name=actor["name"],
                position=position,
                distance_m=math.dist(position, c4),
                state=ai["state"],
                reason=ai["tactical_reason"],
                navigation_nodes=ai["navigation_path_nodes"],
                stall_seconds=ai["route_stalled_seconds"],
                blocked=ai["route_blocked"],
                target_visible_seconds=ai["target_visible_seconds"],
                damage_seconds=ai["damage_seconds"],
            )
        )
    nearest.sort(key=lambda actor: (actor["distance_m"], actor["name"]))
    return dict(
        frame=row["frame"],
        serial=row["serial"],
        round_state=row["round_state"],
        round_seconds=row["round_seconds"],
        c4_state=row["c4_state"],
        c4_position=row["c4_position"],
        player_dead=row["player_dead"],
        spectator_active=row["spectator"]["active"],
        nearest_alive_t=nearest[:3],
        carriers=[a["name"] for a in row["actors"] if a["ai"]["bomb_carrier"]],
    )


def extract(source, serial, frame_start, frame_end):
    if serial < 0 or frame_start < 0 or frame_end < frame_start:
        raise ValueError("Invalid serial/frame range")
    digest = hashlib.sha256()
    samples = []
    following = None
    previous_frame = -1
    with Path(source).open("rb") as stream:
        for raw in stream:
            digest.update(raw)
            row = json.loads(raw)
            if "frame" not in row and row.get("event") == "round_ended":
                continue
            # Standard match frame is global; serial isolates a round after side swap.
            if row["frame"] <= previous_frame:
                raise ValueError("Trace frames must strictly increase")
            previous_frame = row["frame"]
            if row["serial"] == serial and frame_start <= row["frame"] <= frame_end:
                samples.append(compact(row))
            elif samples and following is None and row["frame"] > frame_end:
                following = compact(row)
    if not samples:
        raise ValueError("No matching samples; refusing empty evidence")
    return dict(
        source=str(Path(source).resolve()),
        source_sha256=digest.hexdigest(),
        parameters=dict(serial=serial, frame_start=frame_start, frame_end=frame_end),
        sample_count=len(samples),
        samples=samples,
        following=following,
        limits=(
            "Sampled evidence only; nearest actors are not lease owners. "
            "Visibility/damage ages do not prove continuous contact or inactivity. "
            "Following is next observed row after requested end, possibly next serial; "
            "carriers come from ai.bomb_carrier, not proximity."
        ),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--serial", type=int, required=True)
    parser.add_argument("--frame-start", type=int, required=True)
    parser.add_argument("--frame-end", type=int, required=True)
    args = parser.parse_args()
    result = extract(args.source, args.serial, args.frame_start, args.frame_end)
    with args.output.open("x", encoding="utf8") as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(
        f"RISK_WINDOW samples={result['sample_count']} sha256={result['source_sha256']}"
    )


if __name__ == "__main__":
    main()
