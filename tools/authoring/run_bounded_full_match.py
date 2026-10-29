"""Run one real-rule match; wall timeout is incomplete, never a passing match."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def fingerprint(root: Path) -> dict[str, str]:
    names = subprocess.check_output(
        [
            "git",
            "ls-files",
            "scripts",
            "data",
            "scenes",
            "project.godot",
            "tools/run_match_acceptance.gd",
        ],
        cwd=root,
        text=True,
    ).splitlines()
    return {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        for name in names
        if Path(name).suffix in {".gd", ".json", ".tscn", ".godot", ".gdshader"}
    }


def qualify(
    directory: Path,
    code: int | None,
    changed: bool,
    expected: tuple[str, str, int] | None = None,
) -> tuple[bool, str]:
    log = (directory / "process.log").read_text(encoding="utf8", errors="replace")
    result_path = directory / "result.json"
    if code is None:
        return False, "wall_timeout_incomplete"
    if code != 0 or "SCRIPT ERROR:" in log or "ERROR:" in log:
        return False, "process_or_engine_error"
    if changed:
        return False, "source_changed_during_sample"
    if not result_path.exists() or "FULL_MATCH_COMPLETE " not in log:
        return False, "completion_evidence_missing"
    result = json.loads(result_path.read_text(encoding="utf8"))
    if (
        expected is not None
        and (
            result.get("level_id"),
            result.get("initial_player_team"),
            result.get("seed"),
        )
        != expected
    ):
        return False, "requested_match_identity_mismatch"
    if (
        not all(
            result.get(key) is True
            for key in (
                "pause_resume_checked",
                "summary_menu_checked",
                "main_scene_context_checked",
            )
        )
        or result.get("physics_hz") != 60
        or not result.get("round_records")
        or result.get("phase") != "complete"
        or result.get("team_size") != 5
        or len(result.get("round_records", []))
        != result.get("regulation_rounds", 0) + result.get("overtime_rounds", 0)
    ):
        return False, "required_rule_evidence_missing"
    return True, "complete_sample_not_manual_acceptance"


def run(
    root: Path,
    godot: Path,
    directory: Path,
    map_id: str,
    side: str,
    seed: int,
    wall_seconds: int,
) -> None:
    directory.mkdir(parents=True, exist_ok=False)
    before = fingerprint(root)
    head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True
    ).strip()
    settings = Path.home() / "AppData/Roaming/Godot/app_userdata/矢量突袭/settings.cfg"
    settings_before = (
        hashlib.sha256(settings.read_bytes()).hexdigest() if settings.exists() else None
    )
    args = [
        str(godot),
        "--headless",
        "--fixed-fps",
        "60",
        "--path",
        str(root),
        "--script",
        "tools/run_match_acceptance.gd",
        "--",
        map_id,
        side,
        str(seed),
        str(directory),
    ]
    receipt: dict[str, object] = dict(
        head=head,
        source_before=before,
        args=args,
        map=map_id,
        side=side,
        seed=seed,
        wall_budget_seconds=wall_seconds,
        status="running",
        limitation="stationary human; nine AI; not manual or FPS acceptance",
    )
    receipt_path = directory / "run.json"
    receipt_path.write_text(json.dumps(receipt, indent=2), encoding="utf8")
    started = time.monotonic()
    with (directory / "process.log").open("w", encoding="utf8") as log:
        process = subprocess.Popen(args, cwd=root, stdout=log, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=wall_seconds)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=30)
            code = None
    after = fingerprint(root)
    passed, status = qualify(directory, code, before != after, (map_id, side, seed))
    settings_after = (
        hashlib.sha256(settings.read_bytes()).hexdigest() if settings.exists() else None
    )
    receipt.update(
        status=status,
        qualified_complete=passed,
        exit_code=code,
        wall_seconds=time.monotonic() - started,
        source_after=after,
        settings_unchanged=settings_before == settings_after,
        settings_before=settings_before,
        settings_after=settings_after,
    )
    if settings_before != settings_after:
        receipt.update(
            status="settings_changed_requires_investigation", qualified_complete=False
        )
    receipt_path.write_text(json.dumps(receipt, indent=2), encoding="utf8")
    print(
        json.dumps(
            {
                k: receipt[k]
                for k in (
                    "status",
                    "qualified_complete",
                    "wall_seconds",
                    "settings_unchanged",
                )
            }
        )
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--map", default="dustline-depths-original-local")
    parser.add_argument("--side", choices=["T", "CT"], default="T")
    parser.add_argument("--seed", type=int, default=1701)
    parser.add_argument("--wall-seconds", type=int, default=120)
    options = parser.parse_args()
    if not 1 <= options.wall_seconds <= 4800:
        parser.error("wall-seconds must be 1..4800")
    run(
        Path(__file__).resolve().parents[2],
        options.godot.resolve(),
        options.directory.resolve(),
        options.map,
        options.side,
        options.seed,
        options.wall_seconds,
    )
