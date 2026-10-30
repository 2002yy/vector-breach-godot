"""Read-only staged-package gate; receipts must come from the actual export process.

This verifies receipt consistency and payload identity, not PCK contents, CI,
manual playability, or the truth of a caller-authored export attestation.
"""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from plan_playtest_delivery import payload


def source_manifest(repo: Path) -> dict:
    """Inventory committed runtime text/config, checking current working bytes.

    Assets are bound by package receipts instead. Untracked runtime files fail
    closed so a newly created production module cannot silently be omitted.
    Both index and working bytes must match HEAD; source WIP is not an export
    baseline even if a caller records its matching fingerprint.
    """
    roots = [
        "scripts",
        "scenes",
        "shaders",
        "data",
        "project.godot",
        "export_presets.cfg",
    ]
    names = (
        subprocess.check_output(["git", "ls-files", "-z", "--", *roots], cwd=repo)
        .decode()
        .split("\0")
    )
    untracked = (
        subprocess.check_output(
            ["git", "ls-files", "--others", "--exclude-standard", "-z", "--", *roots],
            cwd=repo,
        )
        .decode()
        .split("\0")
    )

    def included(name: str) -> bool:
        return bool(name) and not name.startswith("scripts/tests/")

    if any(included(name) for name in untracked):
        raise ValueError(
            "Untracked runtime source: commit production paths before export"
        )
    for options in ([], ["--cached"]):
        changed = (
            subprocess.check_output(
                ["git", "diff", *options, "--name-only", "-z", "HEAD", "--", *roots],
                cwd=repo,
            )
            .decode()
            .split("\0")
        )
        if any(included(name) for name in changed):
            raise ValueError("Runtime source differs from HEAD: commit before export")
    files = {}
    for name in sorted(filter(included, names)):
        path = repo / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Invalid runtime source: {name}")
        files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    if "project.godot" not in files:
        raise ValueError("Missing project source")
    return files


def manifest_hash(files: dict) -> str:
    return hashlib.sha256(
        json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def verify(
    root: Path, repo: Path, plan: dict, export: dict, expected_head: str
) -> dict:
    """Check a complete candidate against an external frozen delivery plan."""
    if root.is_symlink() or root.is_junction():
        raise ValueError("Reparse candidate root")
    source = source_manifest(repo)
    fingerprint = manifest_hash(source)
    head = (
        subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo).decode().strip()
    )
    if head != expected_head or export.get("runtime_source_head") != expected_head:
        raise ValueError("Export head is stale")
    if (
        export.get("runtime_sources") != source
        or export.get("runtime_source_sha256") != fingerprint
    ):
        raise ValueError("Export source fingerprint is stale")
    info = json.loads((root / "build-info.json").read_text(encoding="utf8"))
    if (
        info.get("runtime_source_head") != expected_head
        or info.get("runtime_source_sha256") != fingerprint
    ):
        raise ValueError("Candidate metadata is stale")
    required = {"VectorBreach.exe", "VectorBreach.pck", "VectorBreach-radar.pck"}
    required.add("角色环境候选.cmd")
    for map_id in ("dust2", "mirage", "inferno"):
        required.add(f"candidate-inputs/{map_id}/bundle.json")
    entries = plan.get("files", {})
    if not required.issubset(entries):
        raise ValueError("Incomplete delivery plan")
    # The export process must bind all three newly generated runtime artifacts.
    for name in ("VectorBreach.exe", "VectorBreach.pck", "VectorBreach-radar.pck"):
        if export.get("artifacts", {}).get(name) != {
            key: entries[name][key] for key in ("bytes", "sha256")
        }:
            raise ValueError(f"Export artifact mismatch: {name}")
    expected = {
        name: {key: row[key] for key in ("bytes", "sha256")}
        for name, row in entries.items()
    }
    if "build-info.json" in expected:
        raise ValueError("Plan must not inherit old build-info")
    if info.get("files") != expected:
        raise ValueError("Candidate file manifest differs from frozen plan")
    for name, row in expected.items():
        payload(root, name, row)
    actual = set()
    for item in root.rglob("*"):
        if item.is_symlink() or item.is_junction():
            raise ValueError("Reparse candidate member")
        if item.is_file():
            actual.add(item.relative_to(root).as_posix())
    if actual != set(expected) | {"build-info.json"}:
        raise ValueError("Unlisted or missing candidate payload")
    for map_id in ("dust2", "mirage", "inferno"):
        prefix = f"candidate-inputs/{map_id}/"
        bundle = json.loads((root / prefix / "bundle.json").read_text(encoding="utf8"))
        dependencies = set()
        for row in bundle["files"]:
            name = prefix + row["path"]
            if expected.get(name) != {key: row[key] for key in ("bytes", "sha256")}:
                raise ValueError(f"Unbound bundle dependency: {name}")
            dependencies.add(row["path"])
        if not set(bundle["inputs"].values()).issubset(dependencies):
            raise ValueError("Unbound bundle input")
    return {
        "kind": "verified_candidate_receipt_consistency",
        "runtime_source_head": head,
        "runtime_source_sha256": fingerprint,
        "file_count": len(expected),
        "activation_allowed": False,
        "limits": "Does not attest export provenance, PCK semantics, CI or actual EXE playability",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("candidate", "repo", "plan", "export_receipt"):
        parser.add_argument(argument, type=Path)
    parser.add_argument("expected_head")
    args = parser.parse_args()
    print(
        json.dumps(
            verify(
                args.candidate,
                args.repo,
                json.loads(args.plan.read_text(encoding="utf8")),
                json.loads(args.export_receipt.read_text(encoding="utf8")),
                args.expected_head,
            ),
            indent=2,
        )
    )
