# Asset pipeline layers

The repository uses three distinct asset layers.

| Layer | Purpose | Git policy | Godot import |
| --- | --- | --- | --- |
| `assets-source/` | Editable canonical authoring masters | Tracked; large binaries use Git LFS | Disabled with `.gdignore` |
| `assets-generated/` | Reproducible intermediate/staging outputs | Ignored by default | Disabled with `.gdignore` |
| `assets/` | Reviewed runtime assets shipped to Godot | Tracked | Enabled |

## Publish direction

`assets-source/` → authoring/pipeline tools → `assets-generated/` → validation/review → `assets/`

Generation alone does not publish an asset. Promotion into `assets/` is an explicit reviewed step because existing `res://assets/...` paths form part of the game runtime contract.

## Source-layer rules

- Editable masters such as `.blend`, `.kra`, and `.psd` must live under `assets-source/`; CI rejects competing canonical source roots elsewhere in the repository.
- Generated/intermediate content belongs in `assets-generated/`, and reviewed runtime content belongs in `assets/`.
- For v1, flattened delivery/preview formats such as `.png`, `.jpg`, `.jpeg`, `.webp`, `.ktx`, `.ktx2`, and `.dds`, plus GLTF/Godot import-cache outputs, are rejected from `assets-source/`.
- If a future workflow genuinely requires a flattened file as a canonical source input, Step 12 metadata must introduce an explicit source-role exception with provenance rather than weakening the path boundary globally.

## Blender source migration

The six tracked Blender masters have been migrated from `tools/blender/source/` into domain-specific locations under `assets-source/blender/`, and the deterministic Blender builders now point at those canonical paths.

`tools/blender/source/` is retired. CI rejects any tracked file that recreates the legacy root. There must never be two independently editable canonical copies of the same asset.
