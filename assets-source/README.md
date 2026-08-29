# Authoritative asset sources

`assets-source/` is the canonical repository layer for editable source art and audio masters that are not consumed directly by Godot at runtime.

## Contract

- Put editable masters here: `.blend`, `.kra`, `.psd`, source audio, and similar authoring files.
- Large binary source files are tracked through Git LFS according to `.gitattributes`.
- This directory contains `.gdignore`; Godot must not import source-authoring files.
- Do not place generated GLB, converted textures, previews, caches, or build outputs here.
- Runtime-ready, reviewed assets continue to live under `assets/` because existing `res://assets/...` references are part of the game contract.
- Reproducible intermediate outputs belong under `assets-generated/` and are not committed by default.

## Current migration state

Six existing Blender masters are still under `tools/blender/source/` because the current deterministic Blender build scripts write there directly. They are a temporary legacy allowlist, not a second place for new masters.

No new source master may be added to `tools/blender/source/`. A later migration will move those six masters and update the Blender build scripts in one tested change so that the repository never has two competing canonical copies.
