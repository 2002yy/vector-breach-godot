"""Normal Windows export with before/after source identity; never activates a pack."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

from verify_playtest_candidate import manifest_hash, source_manifest

ARTIFACTS = ("VectorBreach.exe", "VectorBreach.pck", "VectorBreach-radar.pck")


def run_step(args: list[str], cwd: Path, log: Path) -> int:
    """Godot assertions can leave SceneTree running; stop only this process tree."""
    with log.open("w", encoding="utf8") as stream:
        process = subprocess.Popen(
            args, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT
        )
        started = time.monotonic()
        while process.poll() is None:
            text = log.read_text(encoding="utf8", errors="replace")
            if (
                "SCRIPT ERROR:" in text
                or "\nERROR:" in text
                or time.monotonic() - started > 1800
            ):
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                        capture_output=True,
                    )
                else:
                    process.terminate()
                process.wait(timeout=30)
                return 1
            try:
                process.wait(timeout=0.25)
            except subprocess.TimeoutExpired:
                pass
        return process.returncode


def snapshot(repo: Path) -> dict:
    head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True
    ).strip()
    source = source_manifest(repo)
    return {
        "runtime_source_head": head,
        "runtime_sources": source,
        "runtime_source_sha256": manifest_hash(source),
    }


def collect(candidate: Path, before: dict, after: dict, steps: list) -> dict:
    if before != after:
        raise ValueError("Source changed during export")
    if len(steps) != 4 or any(row["exit_code"] != 0 for row in steps):
        raise ValueError("Incomplete export commands")
    artifacts = {}
    for name in ARTIFACTS:
        path = candidate / name
        if path.is_symlink() or path.is_junction() or not path.is_file():
            raise ValueError(f"Missing or reparse artifact: {name}")
        size = path.stat().st_size
        if size == 0:
            raise ValueError(f"Empty artifact: {name}")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        artifacts[name] = {"bytes": size, "sha256": digest}
    return dict(
        before,
        artifacts=artifacts,
        export_steps=steps,
        activation_allowed=False,
        limits="Export receipt only; complete support, metadata and actual EXE acceptance still required",
    )


def export(repo: Path, godot: Path, destination: Path, dry_run: bool = False) -> dict:
    repo, destination = repo.resolve(), destination.resolve()
    if destination.exists() or destination.is_relative_to(repo):
        raise ValueError("Export requires a fresh directory outside repository")
    before = snapshot(repo)
    candidate = destination / "candidate"
    raw_radar = destination / "radar-only.pck"
    descriptor = destination / "layout-source.json"
    authoring = repo / "tools/authoring"
    commands = [
        [
            str(godot),
            "--headless",
            "--path",
            str(repo),
            "--export-release",
            "Windows Desktop",
            str(candidate / "VectorBreach.exe"),
        ],
        [
            str(godot),
            "--headless",
            "--path",
            str(repo),
            "--script",
            str(authoring / "build_radar_export_pack.gd"),
            "--",
            "build",
            str(raw_radar),
        ],
        [
            str(godot),
            "--headless",
            "--path",
            str(repo),
            "--script",
            str(authoring / "build_layout_export_receipts.gd"),
            "--",
            "prepare",
            str(descriptor),
            "unused",
        ],
        [
            str(godot),
            "--headless",
            "--main-pack",
            str(candidate / "VectorBreach.pck"),
            "--script",
            str(authoring / "build_layout_export_receipts.gd"),
            "--",
            "build",
            str(descriptor),
            str(candidate / "VectorBreach-radar.pck"),
            str(raw_radar),
        ],
    ]
    if dry_run:
        return dict(before, commands=commands, executed=False, activation_allowed=False)
    candidate.mkdir(parents=True, exist_ok=False)
    host = destination / "pack-host"
    host.mkdir()
    (destination / "export-start.json").write_text(
        json.dumps(dict(before, commands=commands), indent=2) + "\n", encoding="utf8"
    )
    steps = []
    for index, args in enumerate(commands):
        log = destination / f"step-{index}.log"
        code = run_step(args, host if index == 3 else repo, log)
        text = log.read_text(encoding="utf8", errors="replace")
        steps.append(dict(args=args, exit_code=code, log=log.name))
        if code or "SCRIPT ERROR:" in text or "\nERROR:" in text:
            raise RuntimeError(f"Export step failed; preserved {log}")
    receipt = collect(candidate, before, snapshot(repo), steps)
    (destination / "export-receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf8"
    )
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "godot", "destination"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(
        json.dumps(
            export(args.repo, args.godot, args.destination, args.dry_run), indent=2
        )
    )
