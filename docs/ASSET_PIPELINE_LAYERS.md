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

## Legacy Blender source exception

The deterministic Blender builders currently save six master `.blend` files under `tools/blender/source/`. Those exact files are grandfathered temporarily so this layer change does not break established build scripts. CI forbids adding any new file to that legacy source root.

The legacy masters must be migrated together with their builder output paths; they must never be copied into two independently editable canonical locations.
