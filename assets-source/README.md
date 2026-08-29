# Authoritative asset sources

`assets-source/` is the canonical repository layer for editable source art and audio masters that are not consumed directly by Godot at runtime.

## Contract

- Put editable masters here: `.blend`, `.kra`, `.psd`, source audio, and similar authoring files.
- Large binary source files are tracked through Git LFS according to `.gitattributes`.
- This directory contains `.gdignore`; Godot must not import source-authoring files.
- Do not place generated GLB, converted textures, previews, caches, or build outputs here.
- Runtime-ready, reviewed assets continue to live under `assets/` because existing `res://assets/...` references are part of the game contract.
- Reproducible intermediate outputs belong under `assets-generated/` and are not committed by default.

## Migration state

The six tracked Blender masters have been migrated from `tools/blender/source/` into domain-specific paths under `assets-source/blender/`, and the deterministic Blender builders now point at those canonical locations.

`tools/blender/source/` is retired. CI rejects editable source masters outside `assets-source/`, rejects generated/runtime artifacts from the source layer, and rejects any tracked file that recreates the retired legacy source root.
