"""Build an author-only real-weapon movement observation pack; never rate feel."""

import argparse
import copy
import math
import subprocess
from pathlib import Path

from build_native_route_study import read, sha
from movement_current_observation import (
    ADAPTER as CURRENT_ADAPTER,
    verify as verify_current,
)
from movement_observation_session_audit import audit_receipt
from movement_evidence_bank import LEVELS
from build_native_route_study import SCHEMES
from native_jump_candidates import freeze
from validate_native_route_study import require

ADAPTER = "tools/authoring/WeaponMovementObservationSession.gd"
ENTRY = "tools/authoring/open_weapon_movement_observation.gd"
DEPENDENCIES = (
    "tools/movement_weapon_observation.py",
    "tools/movement_observation_session_audit.py",
    CURRENT_ADAPTER,
    ADAPTER,
    ENTRY,
    "scripts/combat/WeaponSystem.gd",
    "scripts/combat/WeaponCatalog.gd",
    "scripts/combat/WeaponProfile.gd",
    "scripts/combat/TacticalEquipment.gd",
    "scenes/combat/WeaponSystem.tscn",
    "data/weapons/rifle.tres",
    "data/weapons/pistol.tres",
)


def payloads(source_pack, project):
    result = {}
    for name in LEVELS:
        for scheme in SCHEMES:
            filename = f"{name}-{scheme}.json"
            manifest = copy.deepcopy(read(source_pack / filename))
            manifest.update(
                stage="real_weapon_movement_observation", human_review="pending"
            )
            manifest["runtime_sha256"].update(
                {"res://" + path: sha(project / path) for path in DEPENDENCIES}
            )
            result[filename] = manifest
    return result


def build(directory, source_pack, project):
    require(not directory.exists(), "weapon observation pack exists")
    require(
        not directory.resolve().is_relative_to(project.resolve()),
        "pack must be external",
    )
    verify_current(source_pack, project)
    manifests = payloads(source_pack, project)
    directory.mkdir(parents=True)
    for name, manifest in manifests.items():
        freeze(directory / name, manifest)
    lock = dict(
        schema=1,
        stage="real_weapon_movement_observation",
        source_pack=str(source_pack.resolve()),
        source_pack_sha256=sha(source_pack / "pack.json"),
        manifests={name: sha(directory / name) for name in manifests},
        human_review="pending",
        formal_release_ready=False,
    )
    freeze(directory / "pack.json", lock)
    return lock


def verify(directory, project):
    lock = read(directory / "pack.json")
    require(
        lock["schema"] == 1
        and lock["stage"] == "real_weapon_movement_observation"
        and lock["human_review"] == "pending"
        and lock["formal_release_ready"] is False,
        "invalid weapon observation lock",
    )
    source = Path(lock["source_pack"])
    require(
        sha(source / "pack.json") == lock["source_pack_sha256"], "source pack drift"
    )
    verify_current(source, project)
    expected = payloads(source, project)
    require(set(lock["manifests"]) == set(expected), "incomplete weapon manifests")
    for name, manifest in expected.items():
        require(
            sha(directory / name) == lock["manifests"][name]
            and read(directory / name) == manifest,
            "weapon manifest or dependency drift",
        )
    return lock


def validate_context(context, sample):
    require(context["weapon_id"] in ("sniper", "rifle", "knife"), "unexpected weapon")
    for key in ("scoped", "walking", "crouching"):
        require(type(context[key]) is bool, "invalid weapon posture")
    for key in ("speed_limit", "horizontal_speed", "camera_fov", "camera_base_fov"):
        value = context[key]
        require(
            type(value) in (int, float) and math.isfinite(value) and value >= 0,
            "invalid weapon metric",
        )
    require(
        context["speed_limit"] > 0 and 28 < context["camera_base_fov"] < 180,
        "nonpositive limit or invalid base FOV",
    )
    require(context["walking"] == sample["walk_requested"], "walking context mismatch")
    require(
        math.isclose(
            context["horizontal_speed"],
            math.hypot(sample["velocity"][0], sample["velocity"][2]),
            abs_tol=1e-5,
        ),
        "actual velocity mismatch",
    )
    if context["scoped"]:
        require(
            context["weapon_id"] == "sniper"
            and math.isclose(context["camera_fov"], 28.0, abs_tol=1e-4),
            "invalid real scope/FOV",
        )
    else:
        require(
            math.isclose(
                context["camera_fov"], context["camera_base_fov"], abs_tol=1e-4
            ),
            "scope FOV not restored",
        )
    require(
        type(context["slot"]) is int
        and context["slot"] == (2 if context["weapon_id"] == "knife" else 0),
        "weapon slot mismatch",
    )
    require(
        context["equipped"]
        == ("knife" if context["weapon_id"] == "knife" else "firearm"),
        "equipment context mismatch",
    )


def validate_receipt(
    receipt, manifest_path, project, mode, require_smoke_coverage=False, rate=60
):
    manifest = read(manifest_path)
    require(
        manifest["stage"] == "real_weapon_movement_observation",
        "wrong observation stage",
    )
    for path in DEPENDENCIES:
        require(
            manifest["runtime_sha256"].get("res://" + path) == sha(project / path),
            "weapon dependency drift",
        )
    result = audit_receipt(receipt, manifest_path, project, mode, rate)
    states = set()
    sequence = []
    for attempt in read(receipt)["attempts"]:
        for sample in attempt["trace"]:
            context = sample["weapon_context"]
            validate_context(context, sample)
            states.add(
                (
                    context["weapon_id"],
                    context["scoped"],
                    context["walking"],
                    context["crouching"],
                )
            )
            if not sequence or sequence[-1] != context["weapon_id"]:
                sequence.append(context["weapon_id"])
    if require_smoke_coverage:
        require(
            mode != "windowed_manual_unreviewed", "manual cannot claim smoke coverage"
        )
        expected = {
            ("sniper", scoped, walking, crouching)
            for scoped in (False, True)
            for walking, crouching in ((False, False), (True, False), (False, True))
        }
        require(expected.issubset(states), "incomplete sniper posture/scope coverage")
        require(
            any(s[0] == "rifle" for s in states)
            and any(s[0] == "knife" for s in states),
            "missing weapon switches",
        )
        require(
            any(
                sequence[i : i + 4] == ["sniper", "rifle", "knife", "sniper"]
                for i in range(len(sequence))
            ),
            "missing return-to-sniper sequence",
        )
        samples = [
            sample
            for attempt in read(receipt)["attempts"]
            for sample in attempt["trace"]
        ]
        require(
            any(sample["weapon_context"]["horizontal_speed"] > 0 for sample in samples),
            "missing actual movement",
        )
        require(any(sample["jumped"] for sample in samples), "missing actual jump")
    result.update(
        weapon_states=[list(s) for s in sorted(states)],
        human_review="pending",
        formal_release_ready=False,
    )
    return result


def launch(directory, project, godot, name, scheme, rate, receipt, mode):
    require(
        name in LEVELS and scheme in SCHEMES and rate in (60, 120), "invalid selection"
    )
    require(mode in ("manual", "smoke", "render-smoke"), "invalid mode")
    require(
        not receipt.exists() and not Path(str(receipt) + ".png").exists(),
        "receipt exists",
    )
    require(
        not receipt.resolve().is_relative_to(project.resolve()),
        "receipt must be external",
    )
    verify(directory, project)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    args = [
        str(godot),
        "--path",
        str(project),
        "--single-threaded-scene",
        "--resolution",
        "960x540",
        "--max-fps",
        "60",
    ]
    if mode == "smoke":
        args += ["--headless", "--rendering-method", "gl_compatibility"]
    manifest = directory / f"{name}-{scheme}.json"
    args += [
        "--script",
        "res://" + ENTRY,
        "--",
        str(manifest.resolve()),
        str(receipt.resolve()),
        f"--rate={rate}",
    ]
    if mode != "manual":
        args += ["--" + mode]
    subprocess.run(args, check=True, timeout=None if mode == "manual" else 240)
    return validate_receipt(
        receipt,
        manifest,
        project,
        {
            "manual": "windowed_manual_unreviewed",
            "smoke": "headless_collision_logic_smoke",
            "render-smoke": "windowed_automated_render_smoke",
        }[mode],
        mode != "manual",
        rate,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "verify", "launch"))
    parser.add_argument("directory", type=Path)
    parser.add_argument("--source-pack", type=Path)
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
    if args.action == "build":
        require(args.source_pack is not None, "build requires source pack")
        build(args.directory, args.source_pack, args.project)
    elif args.action == "verify":
        verify(args.directory, args.project)
    else:
        require(
            args.godot is not None
            and args.map is not None
            and args.receipt is not None,
            "launch requires godot/map/receipt",
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
    print("WEAPON_MOVEMENT_OBSERVATION_OK", args.action)
