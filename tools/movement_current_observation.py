"""Freeze and launch latest-source manual observation; never assign human scores."""

import argparse
import copy
import json
import math
import subprocess
from pathlib import Path
from typing import Any

from build_native_route_study import SCHEMES, read, sha
from movement_current_registry import verify_registry
from movement_evidence_bank import LEVELS, validate_session_receipt
from validate_native_route_study import require

ADAPTER = "tools/authoring/CurrentMovementObservationSession.gd"
ENTRY = "tools/authoring/open_current_movement_observation.gd"
OBSERVER = "tools/authoring/JumpPlaytestSession.gd"


def selected_manifest(registry, map_name, scheme):
    require(map_name in LEVELS and scheme in SCHEMES, "unknown map/profile")
    selected = [s for s in registry["sites"] if s["map"] == map_name]
    require(bool(selected), "no selected sites")
    result, cases = None, []
    for site in selected:
        profile = site["profiles"][scheme]
        point = copy.deepcopy(profile["point"])
        require(
            point["scheme"] == scheme and point["trial_mode"] == "jump",
            "selection is not a formal profile jump reference",
        )
        metadata = profile["manifest"]
        require(metadata["level"] == LEVELS[map_name], "selected map mismatch")
        if result is None:
            result = copy.deepcopy(metadata)
        else:
            require(
                all(
                    result[k] == metadata[k]
                    for k in ("identity", "runtime_sha256", "input_map_sha256", "level")
                ),
                "mixed selected runtime identity",
            )
        point.update(
            id=site["site"],
            parent_case=site["site"],
            observation_status=profile["status"],
            reference_source=profile["source_provider"],
            reference_case=profile["source_case"],
        )
        cases.append(point)
    assert result is not None
    result.update(
        cases=cases,
        formal_qualification=False,
        observation_scheme=scheme,
        stage="latest_source_manual_observation",
        human_review="pending",
    )
    return result


def manifests(registry, project):
    output = {}
    for name in LEVELS:
        for scheme in SCHEMES:
            manifest = selected_manifest(registry, name, scheme)
            manifest["runtime_sha256"].update(
                {"res://" + p: sha(project / p) for p in (ADAPTER, ENTRY, OBSERVER)}
            )
            output[f"{name}-{scheme}.json"] = manifest
    return output


def build(directory, registry_path, project) -> dict[str, Any]:
    require(not directory.exists(), "observation pack exists; use a new version")
    require(
        not directory.resolve().is_relative_to(project.resolve()),
        "pack must be external",
    )
    registry = verify_registry(registry_path, project)
    payloads = manifests(registry, project)
    directory.mkdir(parents=True)
    for name, payload in payloads.items():
        (directory / name).write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )
    lock = dict(
        schema=1,
        registry=str(registry_path.resolve()),
        registry_sha256=sha(registry_path),
        human_review="pending",
        formal_release_ready=False,
        manifests={name: sha(directory / name) for name in payloads},
    )
    (directory / "pack.json").write_text(
        json.dumps(lock, indent=2) + "\n", encoding="utf-8"
    )
    return lock


def verify(directory, project):
    lock = read(directory / "pack.json")
    require(
        lock["schema"] == 1
        and lock["human_review"] == "pending"
        and lock["formal_release_ready"] is False,
        "false manual acceptance",
    )
    registry_path = Path(lock["registry"])
    require(sha(registry_path) == lock["registry_sha256"], "registry lock drift")
    registry = verify_registry(registry_path, project)
    expected = manifests(registry, project)
    require(set(lock["manifests"]) == set(expected), "incomplete nine-profile pack")
    for name, payload in expected.items():
        path = directory / name
        require(
            sha(path) == lock["manifests"][name] and read(path) == payload,
            "selected point/runtime/adapter drift",
        )
    return lock


def validate_receipt(receipt, manifest_path, project, mode):
    manifest = read(manifest_path)
    data = read(receipt)
    for path in (ADAPTER, ENTRY, OBSERVER):
        require(
            manifest["runtime_sha256"].get("res://" + path) == sha(project / path),
            "observation adapter source drift",
        )
    result = validate_session_receipt(receipt, manifest_path, project, mode)
    for attempt in data["attempts"]:
        require(
            attempt["scheme"] == manifest["observation_scheme"],
            "frozen scheme mismatch",
        )
        require(
            not attempt.get("trace_truncated", False), "observation trace truncated"
        )
        for sample in attempt["trace"]:
            require(
                all(
                    isinstance(sample.get(key), list)
                    and len(sample[key]) == 3
                    and all(
                        type(v) in (int, float) and math.isfinite(v)
                        for v in sample[key]
                    )
                    for key in ("position", "velocity")
                ),
                "invalid observed position/velocity",
            )
    return result


def launch(directory, project, godot, map_name, scheme, rate, receipt, mode="manual"):
    verify(directory, project)  # Recompute all three maps/profiles before any window.
    require(
        map_name in LEVELS and scheme in SCHEMES and rate in (60, 120), "bad selection"
    )
    require(mode in ("manual", "smoke", "render-smoke"), "bad session mode")
    require(
        not receipt.exists() and not Path(str(receipt) + ".png").exists(),
        "receipt exists",
    )
    require(
        not receipt.resolve().is_relative_to(project.resolve()),
        "receipt must be external",
    )
    receipt.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(godot),
        "--path",
        str(project),
        "--single-threaded-scene",
        "--max-fps",
        "60",
        "--resolution",
        "960x540",
    ]
    if mode == "smoke":
        command += ["--headless"]
    command += [
        "--script",
        "res://" + ENTRY,
        "--",
        str((directory / f"{map_name}-{scheme}.json").resolve()),
        str(receipt.resolve()),
        "--rate=" + str(rate),
    ]
    if mode != "manual":
        command += ["--" + mode]
    subprocess.run(command, check=True, timeout=None if mode == "manual" else 240)
    return validate_receipt(
        receipt,
        directory / f"{map_name}-{scheme}.json",
        project,
        {
            "manual": "windowed_manual_unreviewed",
            "smoke": "headless_collision_logic_smoke",
            "render-smoke": "windowed_automated_render_smoke",
        }[mode],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "verify", "launch"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--map", choices=LEVELS)
    parser.add_argument("--scheme", choices=SCHEMES, default="current")
    parser.add_argument("--rate", type=int, choices=(60, 120), default=60)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument(
        "--session", choices=("manual", "smoke", "render-smoke"), default="manual"
    )
    args = parser.parse_args()
    if args.mode == "build":
        require(args.registry is not None, "build needs --registry")
        build(args.directory, args.registry, args.project)
    elif args.mode == "verify":
        verify(args.directory, args.project)
    else:
        require(
            args.godot is not None
            and args.map is not None
            and args.receipt is not None,
            "launch needs --godot --map --receipt",
        )
        launch(
            args.directory,
            args.project,
            args.godot,
            args.map,
            args.scheme,
            args.rate,
            args.receipt,
            args.session,
        )
    print("MOVEMENT_CURRENT_OBSERVATION_OK", args.mode)
