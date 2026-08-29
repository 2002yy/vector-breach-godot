from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOTS = ("assets", "assets-source/blender")


def _git(*args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *args],
        cwd=PROJECT_ROOT,
        check=check,
        capture_output=True,
    )


def _decode_z(data: bytes) -> list[str]:
    return [item.decode("utf-8").replace("\\", "/") for item in data.split(b"\0") if item]


def tracked_files() -> set[str]:
    return set(_decode_z(_git("ls-files", "-z").stdout))


def changed_asset_paths() -> set[str]:
    modified = _decode_z(
        _git("diff", "--name-only", "-z", "--", *ASSET_ROOTS).stdout
    )
    untracked = _decode_z(
        _git(
            "ls-files",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            *ASSET_ROOTS,
        ).stdout
    )
    return set(modified) | set(untracked)


def restore_paths(paths: set[str]) -> None:
    if not paths:
        return
    _git("restore", "--source=HEAD", "--worktree", "--", *sorted(paths))


def validate_runtime_output(relative_path: str) -> tuple[int, str]:
    path = PROJECT_ROOT / relative_path
    if not path.is_file():
        raise RuntimeError(f"declared runtime output was not produced: {relative_path}")
    size = path.stat().st_size
    if size <= 0:
        raise RuntimeError(f"declared runtime output is empty: {relative_path}")

    suffix = path.suffix.lower()
    head = path.read_bytes()[:16]
    if suffix == ".glb" and not head.startswith(b"glTF"):
        raise RuntimeError(f"invalid GLB header: {relative_path}")
    if suffix == ".png" and not head.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError(f"invalid PNG header: {relative_path}")
    if suffix in {".jpg", ".jpeg"} and not head.startswith(b"\xff\xd8\xff"):
        raise RuntimeError(f"invalid JPEG header: {relative_path}")
    return size, head.hex()


def discover_publish_jobs(tracked: set[str]) -> list[dict]:
    jobs: list[dict] = []
    for metadata_path in sorted(
        path
        for path in tracked
        if path.startswith("assets-source/blender/") and path.endswith(".asset.json")
    ):
        metadata = json.loads((PROJECT_ROOT / metadata_path).read_text(encoding="utf-8"))
        if metadata.get("source_role") != "canonical_master":
            continue
        build_script = metadata.get("build_script")
        runtime_outputs = metadata.get("runtime_outputs")
        if not isinstance(build_script, str) or not build_script:
            raise RuntimeError(f"{metadata_path}: missing build_script")
        if build_script not in tracked:
            raise RuntimeError(f"{metadata_path}: untracked build_script {build_script!r}")
        if not isinstance(runtime_outputs, list) or not runtime_outputs:
            raise RuntimeError(f"{metadata_path}: runtime_outputs must be non-empty")
        jobs.append(
            {
                "metadata_path": metadata_path,
                "asset_id": metadata.get("asset_id", metadata_path),
                "source_path": metadata["source_path"],
                "build_script": build_script,
                "runtime_outputs": list(runtime_outputs),
            }
        )
    if not jobs:
        raise RuntimeError("no Blender publish jobs were discovered")
    return jobs


def run_builder(blender_bin: Path, job: dict) -> None:
    command = [
        str(blender_bin),
        "--background",
        "--factory-startup",
        "--python-exit-code",
        "1",
        "--python",
        job["build_script"],
    ]
    print(
        f"==> Rebuilding {job['asset_id']} via {job['build_script']}",
        flush=True,
    )
    completed = subprocess.run(command, cwd=PROJECT_ROOT, check=False, timeout=300)
    if completed.returncode != 0:
        raise RuntimeError(
            f"builder failed for {job['asset_id']} with exit code {completed.returncode}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("blender", help="Path to the pinned Blender executable")
    args = parser.parse_args()

    blender_bin = Path(args.blender)
    if not blender_bin.is_absolute():
        blender_bin = (PROJECT_ROOT / blender_bin).resolve()
    if not blender_bin.is_file():
        print("BLENDER_PUBLISH_REBUILD=FAIL")
        print(f"- Blender executable does not exist: {blender_bin}")
        return 1

    try:
        tracked = tracked_files()
        jobs = discover_publish_jobs(tracked)

        initial_changes = changed_asset_paths()
        if initial_changes:
            raise RuntimeError(
                "asset working tree must be clean before publish validation: "
                + ", ".join(sorted(initial_changes))
            )

        declared_owner: dict[str, str] = {}
        for job in jobs:
            for output in job["runtime_outputs"]:
                previous = declared_owner.get(output)
                if previous is not None:
                    raise RuntimeError(
                        f"runtime output has multiple producers: {output} ({previous}, {job['asset_id']})"
                    )
                declared_owner[output] = str(job["asset_id"])

        total_bytes = 0
        with tempfile.TemporaryDirectory(prefix="vb-publish-rebuild-") as temp_dir:
            staging_root = Path(temp_dir)

            for job in jobs:
                if changed_asset_paths():
                    raise RuntimeError("asset working tree was not restored before the next builder")

                run_builder(blender_bin, job)

                source_path = str(job["source_path"])
                outputs = {str(item) for item in job["runtime_outputs"]}
                allowed_changes = outputs | {source_path}
                changes = changed_asset_paths()
                disallowed = changes - allowed_changes
                if disallowed:
                    raise RuntimeError(
                        f"{job['asset_id']} modified undeclared asset paths: {sorted(disallowed)}"
                    )

                for output in sorted(outputs):
                    size, head = validate_runtime_output(output)
                    total_bytes += size
                    staged = staging_root / output
                    staged.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(PROJECT_ROOT / output, staged)
                    print(
                        f"PUBLISH_OUTPUT asset={job['asset_id']} path={output} bytes={size} head16={head}",
                        flush=True,
                    )

                restore_paths(allowed_changes & tracked)
                residual = changed_asset_paths()
                if residual:
                    raise RuntimeError(
                        f"asset working tree did not restore cleanly after {job['asset_id']}: {sorted(residual)}"
                    )

            for output in sorted(declared_owner):
                staged = staging_root / output
                if not staged.is_file():
                    raise RuntimeError(f"staged runtime output is missing: {output}")
                destination = PROJECT_ROOT / output
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(staged, destination)
                validate_runtime_output(output)

        final_changes = changed_asset_paths()
        unexpected_final = final_changes - set(declared_owner)
        if unexpected_final:
            raise RuntimeError(
                f"final publish staging modified undeclared asset paths: {sorted(unexpected_final)}"
            )

        print("BLENDER_PUBLISH_REBUILD=PASS")
        print(f"publish_jobs={len(jobs)}")
        print(f"runtime_outputs={len(declared_owner)}")
        print(f"staged_bytes={total_bytes}")
        print("fresh_outputs_ready_for_godot=1")
        return 0
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, json.JSONDecodeError, RuntimeError) as exc:
        print("BLENDER_PUBLISH_REBUILD=FAIL")
        print(f"- {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
