#!/usr/bin/env python3
"""Validate Step 15 runtime contracts declared next to canonical Blender masters."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets-source" / "blender"
BUDGET_KEYS = {
    "file_size_bytes",
    "nodes",
    "meshes",
    "primitives",
    "vertices_by_primitive",
    "triangles",
    "materials",
    "textures",
    "images",
    "skins",
    "skin_joints_total",
    "animations",
    "animation_channels",
}


def tracked_files() -> set[str]:
    result = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True)
    return {
        item.decode("utf-8").replace("\\", "/")
        for item in result.stdout.split(b"\0")
        if item
    }


def normalized_repo_path(value: str) -> bool:
    if not value or "\\" in value or value.startswith("/"):
        return False
    pure = PurePosixPath(value)
    return not pure.is_absolute() and pure.as_posix() == value and all(part not in {"", ".", ".."} for part in pure.parts)


def nonnegative_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def main() -> int:
    tracked = tracked_files()
    violations: list[str] = []
    contracts_seen: dict[str, str] = {}
    glb_outputs = 0

    for sidecar in sorted(SOURCE_ROOT.rglob("*.asset.json")):
        rel_sidecar = sidecar.relative_to(ROOT).as_posix()
        try:
            metadata = json.loads(sidecar.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            violations.append(f"{rel_sidecar}: cannot parse metadata: {exc}")
            continue
        if not isinstance(metadata, dict) or metadata.get("authoring_tool") != "Blender":
            continue
        outputs = metadata.get("runtime_outputs")
        if not isinstance(outputs, list):
            violations.append(f"{rel_sidecar}: runtime_outputs must be an array")
            continue
        expected = {
            output for output in outputs
            if isinstance(output, str) and output.lower().endswith(".glb")
        }
        glb_outputs += len(expected)
        contracts = metadata.get("runtime_contracts")
        if not isinstance(contracts, dict):
            violations.append(f"{rel_sidecar}: runtime_contracts must be an object covering every GLB output")
            continue
        if set(contracts) != expected:
            missing = sorted(expected - set(contracts))
            extra = sorted(set(contracts) - expected)
            if missing:
                violations.append(f"{rel_sidecar}: runtime_contracts missing GLB outputs: {missing}")
            if extra:
                violations.append(f"{rel_sidecar}: runtime_contracts has non-GLB/undeclared outputs: {extra}")

        for output, contract in contracts.items():
            if not isinstance(output, str) or not normalized_repo_path(output) or not output.startswith("assets/"):
                violations.append(f"{rel_sidecar}: invalid runtime contract path: {output!r}")
                continue
            if output not in tracked:
                violations.append(f"{rel_sidecar}: contracted runtime output is missing or untracked: {output}")
            owner = contracts_seen.get(output)
            if owner is not None:
                violations.append(f"{rel_sidecar}: runtime contract duplicates {output}; first declared by {owner}")
            else:
                contracts_seen[output] = rel_sidecar
            if not isinstance(contract, dict):
                violations.append(f"{rel_sidecar}: contract for {output} must be an object")
                continue
            if contract.get("format") != "glb2":
                violations.append(f"{rel_sidecar}: contract for {output} must use format='glb2'")

            maximums = contract.get("max")
            if not isinstance(maximums, dict) or set(maximums) != BUDGET_KEYS:
                violations.append(
                    f"{rel_sidecar}: contract max for {output} must define exactly {sorted(BUDGET_KEYS)}"
                )
                continue
            for key, value in maximums.items():
                if not nonnegative_int(value):
                    violations.append(f"{rel_sidecar}: contract max {output}:{key} must be a non-negative integer")

            minimums = contract.get("min", {})
            if not isinstance(minimums, dict) or not set(minimums).issubset(BUDGET_KEYS):
                violations.append(f"{rel_sidecar}: contract min for {output} contains unsupported keys")
            else:
                for key, value in minimums.items():
                    if not nonnegative_int(value):
                        violations.append(f"{rel_sidecar}: contract min {output}:{key} must be a non-negative integer")
                    elif nonnegative_int(maximums.get(key)) and value > maximums[key]:
                        violations.append(f"{rel_sidecar}: contract min {output}:{key} exceeds max")

            extensions = contract.get("allowed_extensions_used", [])
            if not isinstance(extensions, list) or any(not isinstance(item, str) or not item for item in extensions):
                violations.append(f"{rel_sidecar}: allowed_extensions_used for {output} must be an array of non-empty strings")
            elif len(extensions) != len(set(extensions)):
                violations.append(f"{rel_sidecar}: allowed_extensions_used for {output} contains duplicates")

    if violations:
        print("ASSET_RUNTIME_CONTRACT_POLICY=FAIL")
        for violation in violations:
            print(f"- {violation}")
        return 1

    print("ASSET_RUNTIME_CONTRACT_POLICY=PASS")
    print(f"contracted_glbs={len(contracts_seen)}")
    print(f"declared_glb_outputs={glb_outputs}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
