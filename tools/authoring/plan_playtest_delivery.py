"""Verify two immutable package receipts and emit a copy-free delivery plan."""

import argparse
import hashlib
import json
from pathlib import Path


def payload(root: Path, name: str, expected: dict) -> dict:
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or ":" in name:
        raise ValueError(f"Unsafe payload path: {name}")
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Escaping payload: {name}")
    for part in [path, *path.parents]:
        if part.is_symlink() or part.is_junction():
            raise ValueError(f"Reparse payload path: {part}")
        if part == root:
            break
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    size = path.stat().st_size
    if digest != expected["sha256"] or size != expected["bytes"]:
        raise ValueError(f"Payload identity mismatch: {name}")
    return {"source": str(path.resolve()), "bytes": size, "sha256": digest}


def plan(old: Path, standard: Path, receipt: Path, output: Path) -> dict:
    if output.exists():
        raise FileExistsError(output)
    old_info = json.loads((old / "build-info.json").read_text(encoding="utf8"))
    current = json.loads(receipt.read_text(encoding="utf8"))
    if current.get("graphical", {}).get("three_maps_start_ready_verified") is not True:
        raise ValueError("Standard package requires observed normal three-map starts")
    required = {"VectorBreach.exe", "VectorBreach.pck", "VectorBreach-radar.pck"}
    if not required.issubset(current.get("artifacts", {})):
        raise ValueError("Standard receipt requires EXE, main PCK and radar PCK")
    entries = {}
    for name, expected in old_info["files"].items():
        verified = payload(old, name, expected)
        entries[name] = dict(verified, action="retain_optional_or_support")
    for name, expected in current["artifacts"].items():
        entries[name] = dict(payload(standard, name, expected), action="use_standard")
    launcher = "角色环境候选.cmd"
    if launcher not in entries:
        raise ValueError("Missing optional environment launcher")
    for map_id in ("dust2", "mirage", "inferno"):
        name = f"candidate-inputs/{map_id}/bundle.json"
        if name not in entries:
            raise ValueError(f"Missing environment bundle: {name}")
    result = {
        "schema": 1,
        "kind": "verified_copy_free_delivery_plan",
        "runtime_production_baseline": current["base"],
        "runtime_acceptance_receipt_head": current["head"],
        "runtime_provenance_note": "R42 normal export from unchanged production tree; later commits do not update these bytes",
        "previous_runtime": old_info["runtime_source_head"],
        "files": entries,
        "stale_metadata_not_for_copy": ["build-info.json"],
        "stage_allowed": False,
        "pending": [
            "Verify optional environment entry against new standard PCK",
            "Regenerate build-info, launcher guidance and current-pointer only after acceptance",
            "Re-export if production changes after R42",
            "Private original assets: no public redistribution authorization inferred",
        ],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf8") as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("old", "standard", "receipt", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    data = plan(
        args.old.resolve(),
        args.standard.resolve(),
        args.receipt.resolve(),
        args.output.resolve(),
    )
    print("DELIVERY_PLAN_VERIFIED", len(data["files"]), "files; no copy, no activation")
