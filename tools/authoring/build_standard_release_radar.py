"""Build one standard Windows release and its identity-bound asset-only radar sidecar."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def build(project: Path, candidate: Path, godot: Path, existing_export: bool) -> None:
    candidate.mkdir(parents=True, exist_ok=True)
    exe = candidate / "VectorBreach.exe"
    product = candidate / "VectorBreach.pck"
    sidecar = candidate / "VectorBreach-radar.pck"
    if sidecar.exists():
        raise FileExistsError(sidecar)
    work = candidate.parent / "radar-build"
    work.mkdir(exist_ok=False)
    isolated = work / "isolated"
    isolated.mkdir()
    (isolated / "project.godot").write_text("config_version=5\n", encoding="utf8")

    def run(name: str, cwd: Path, args: list[str]) -> None:
        log = work / f"{name}.log"
        with log.open("w", encoding="utf8") as output:
            result = subprocess.run(
                [str(godot), *args],
                cwd=cwd,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=600,
                check=False,
            )
        text = log.read_text(encoding="utf8", errors="replace")
        if result.returncode or "SCRIPT ERROR:" in text or "\nERROR:" in text:
            raise RuntimeError(f"{name} failed; inspect {log}")

    if existing_export:
        if not exe.is_file() or not product.is_file():
            raise FileNotFoundError("existing standard EXE/PCK required")
    else:
        if exe.exists() or product.exists():
            raise FileExistsError("refusing to overwrite an export")
        run(
            "export",
            project,
            [
                "--headless",
                "--path",
                str(project),
                "--export-release",
                "Windows Desktop",
                str(exe),
            ],
        )
    radar_tool = project / "tools/authoring/build_final_radar_supplement.gd"
    layout_tool = project / "tools/authoring/build_layout_export_receipts.gd"
    radar_descriptor = work / "radar.json"
    layout_descriptor = work / "layout.json"
    for name, tool, descriptor in [
        ("radar-prepare", radar_tool, radar_descriptor),
        ("layout-prepare", layout_tool, layout_descriptor),
    ]:
        run(
            name,
            project,
            [
                "--headless",
                "--path",
                str(project),
                "--script",
                str(tool),
                "--",
                "prepare",
                str(descriptor),
                "reserved",
            ],
        )
    shutil.copyfile(radar_tool, isolated / "radar.gd")
    radar_pack = work / "radar-only.pck"
    run(
        "radar-build",
        isolated,
        [
            "--headless",
            "--path",
            str(isolated),
            "--script",
            "res://radar.gd",
            "--",
            "build",
            str(product),
            str(radar_descriptor),
            str(radar_pack),
        ],
    )
    host = 'extends "' + layout_tool.as_posix() + '"\n\nfunc _initialize() -> void:\n'
    host += "\tif not ProjectSettings.load_resource_pack(" + json.dumps(
        product.as_posix()
    )
    host += ", false):\n\t\tquit(1)\n\t\treturn\n\tsuper._initialize()\n"
    (isolated / "layout.gd").write_text(host, encoding="utf8")
    run(
        "layout-build",
        isolated,
        [
            "--headless",
            "--path",
            str(isolated),
            "--script",
            "res://layout.gd",
            "--",
            "build",
            str(layout_descriptor),
            str(sidecar),
            str(radar_pack),
        ],
    )
    run(
        "radar-check",
        isolated,
        [
            "--headless",
            "--path",
            str(isolated),
            "--script",
            "res://radar.gd",
            "--",
            "check",
            str(product),
            str(sidecar),
        ],
    )
    receipts = {}
    for path in [exe, product, sidecar]:
        with path.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        receipts[path.name] = {"bytes": path.stat().st_size, "sha256": digest}
    (work / "artifacts.json").write_text(
        json.dumps(receipts, indent=2) + "\n", encoding="utf8"
    )
    print("STANDARD_RADAR_RELEASE_BUILT", candidate)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument(
        "--project", type=Path, default=Path(__file__).resolve().parents[2]
    )
    parser.add_argument("--existing-export", action="store_true")
    options = parser.parse_args()
    build(
        options.project.resolve(),
        options.candidate.resolve(),
        options.godot.resolve(),
        options.existing_export,
    )
