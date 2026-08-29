# Authoritative asset sources

`assets-source/` is the canonical repository layer for editable source art and audio masters that are not consumed directly by Godot at runtime.

## Contract

- Put editable masters here: `.blend`, `.kra`, `.psd`, source audio, and similar authoring files.
- Every tracked editable master must have an adjacent `*.asset.json` sidecar following `docs/ASSET_METADATA.md`.
- Unknown historical provenance, license, or AI-use information must be recorded as `unknown`; do not invent missing facts.
- Large binary source files are tracked through Git LFS according to `.gitattributes`.
- This directory contains `.gdignore`; Godot must not import source-authoring files.
- Do not place generated GLB, converted textures, previews, caches, or build outputs here.
- Flattened delivery/preview formats such as `.png`, `.jpg`, `.jpeg`, `.webp`, `.ktx`, `.ktx2`, and `.dds` are rejected by default. A true canonical flattened input requires an explicit metadata exception with known origin and a `project-owned` or `permitted` license status.
- Runtime-ready, reviewed assets continue to live under `assets/` because existing `res://assets/...` references are part of the game contract.
- Reproducible intermediate outputs belong under `assets-generated/` and are not committed by default.

## Migration state

The six tracked Blender masters have been migrated from `tools/blender/source/` into domain-specific paths under `assets-source/blender/`, and the deterministic Blender builders now point at those canonical locations. All six have v1 metadata sidecars.

`tools/blender/source/` is retired. CI rejects editable source masters outside `assets-source/`, rejects generated/runtime or unapproved flattened artifacts from the source layer, validates metadata coverage and semantics, and rejects any tracked file that recreates the retired legacy source root.
