"""Copy verified diagnostic inputs into a self-contained, private per-map bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path, PurePosixPath


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def relative(value: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise ValueError("invalid bundle path")
    parts = value.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError("noncanonical bundle path")
    return str(PurePosixPath(value))


def prepare(
    output: Path,
    reflection: Path,
    lighting: Path,
    normalization: Path,
    indirect: Path,
    alignment: Path | None = None,
) -> dict:
    inputs = {
        "reflection": reflection,
        "lighting": lighting,
        "normalization": normalization,
        "indirect": indirect,
    }
    documents = {
        key: json.loads(path.read_text(encoding="utf-8-sig"))
        for key, path in inputs.items()
    }
    level = documents["reflection"]["level"]
    trace = documents["reflection"]["source_trace"]["vpkSha256"]
    if not isinstance(level, str) or not isinstance(trace, str) or len(trace) != 64:
        raise ValueError("missing map identity")
    int(trace, 16)
    for document in documents.values():
        if (
            document.get("level") != level
            or document.get("source_trace", {}).get("vpkSha256") != trace
        ):
            raise ValueError("mixed map inputs")
    sources = {f"{key}/{path.name}": path for key, path in inputs.items()}
    roles = {key: f"{key}/{path.name}" for key, path in inputs.items()}

    def dependency(role: str, filename: str, sha256: str) -> None:
        name = relative(filename)
        source = inputs[role].parent / name
        if digest(source) != sha256:
            raise ValueError(f"dependency hash mismatch: {role}/{name}")
        target = str(PurePosixPath(roles[role]).parent / name)
        if target in sources:
            raise ValueError("dependency collides with input")
        sources[target] = source

    dependency(
        "reflection", documents["reflection"]["file"], documents["reflection"]["sha256"]
    )
    dependency(
        "normalization",
        documents["normalization"]["brdf"]["file"],
        documents["normalization"]["brdf"]["sha256"],
    )
    for source in documents["lighting"]["sources"].values():
        decoded = source.get("decoded")
        if decoded:
            dependency("lighting", decoded["file"], decoded["sha256"])
    if documents["indirect"]["lighting_sha256"] != digest(lighting):
        raise ValueError("indirect lighting hash mismatch")
    if alignment is not None:
        receipt = json.loads(alignment.read_text(encoding="utf-8-sig"))
        if receipt.get("level") != level or receipt.get("source_vpk_sha256") != trace:
            raise ValueError("mixed alignment receipt")
        sources["alignment.json"] = alignment
        roles["alignment"] = "alignment.json"
    if len({relative(name).casefold() for name in sources}) != len(sources):
        raise ValueError("duplicate bundle path")
    files = [
        {"path": name, "bytes": path.stat().st_size, "sha256": digest(path)}
        for name, path in sorted(sources.items())
    ]
    manifest = {
        "schema": 1,
        "contract": "source-character-runtime-bundle-v1",
        "purpose": "controlled-candidate",
        "level": level,
        "vpk_sha256": trace,
        "inputs": roles,
        "files": files,
    }
    # All source validation happens first; a failed copy never publishes a manifest.
    if output.exists() and any(output.iterdir()):
        raise FileExistsError("refusing to overwrite a nonempty bundle directory")
    output.mkdir(parents=True, exist_ok=True)
    for row in files:
        target = output / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(sources[row["path"]], target)
        if digest(target) != row["sha256"]:
            raise ValueError("copied bytes changed")
    (output / "bundle.json").write_text(
        json.dumps(manifest, indent=2, allow_nan=False) + "\n", encoding="utf-8"
    )
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ["output", "reflection", "lighting", "normalization", "indirect"]:
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--alignment", type=Path)
    args = parser.parse_args()
    result = prepare(**vars(args))
    print("CHARACTER_RUNTIME_BUNDLE_OK", result["level"], len(result["files"]))
