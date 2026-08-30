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

As of Step 14, the CI pipeline also proves the publish direction by rebuilding runtime assets from canonical Blender sources before Godot consumes them:

```text
assets-source/
  -> metadata producer contract
  -> Blender 5.2.1 source validation
  -> existing deterministic builder
  -> fresh declared runtime outputs
  -> undeclared-side-effect check
  -> assets/
  -> Godot import
  -> GdUnit4
  -> native suites
```

The tracked runtime file already present in the checkout is never sufficient proof of rebuildability. The publish/rebuild gate removes each producer's declared outputs before invoking its builder and requires the files to be recreated.

## Source-layer rules

- Editable masters such as `.blend`, `.kra`, and `.psd` must live under `assets-source/`; CI rejects competing canonical source roots elsewhere in the repository.
- Generated/intermediate content belongs in `assets-generated/`, and reviewed runtime content belongs in `assets/`.
- For v1, flattened delivery/preview formats such as `.png`, `.jpg`, `.jpeg`, `.webp`, `.ktx`, `.ktx2`, and `.dds`, plus GLTF/Godot import-cache outputs, are rejected from `assets-source/`.
- If a future workflow genuinely requires a flattened file as a canonical source input, metadata must introduce an explicit source-role exception with provenance rather than weakening the path boundary globally.

## Canonical producer contract

Each tracked canonical Blender master has an adjacent `*.asset.json` sidecar. For Blender masters the sidecar now defines:

- a unique asset identity;
- the canonical source path;
- one tracked `build_script`;
- a non-empty set of tracked runtime outputs under `assets/`.

One runtime artifact may have only one canonical Blender producer. The current baseline contains **6 Blender producers owning 13 runtime outputs**.

`tools/blender/run_publish_rebuild_validation.py` executes those existing builders in isolation. It rejects missing fresh outputs, invalid/empty outputs, and asset-side paths modified outside the producer's declared contract. Between producers it restores the tracked working tree and stages the fresh declared outputs so the downstream Godot checks consume the rebuilt set rather than the repository's old binaries.

The Tactical Actor legacy builder is wrapped by a thin portable adapter rather than duplicated. The adapter maps its old local Windows roots to the current checkout and suppresses Blender `.blend1`/`.blend2` backup rotation while the delegated build runs. The Foundry map likewise uses a thin publish adapter so its canonical producer no longer depends on or republishes the independent weapon producer.

## Acceptance evidence through Step 14

Positive acceptance at Step 14 head `72196969d5f81a6fe05b1d2b6c148c5ad1a04b0d` passed required `Tests` and the legacy `Godot Tests`: fresh Blender outputs were rebuilt first, then consumed by Godot import, GdUnit4, and native suites. PR #20 was merged as `bcb24be4a71b6863d558a73511e00d89e612a9fe`, and both main-branch push workflows completed successfully after the merge.

The do-not-merge negative acceptance PR #22 intentionally created the undeclared path:

```text
assets-source/blender/characters/NEGATIVE_ACCEPTANCE_UNDECLARED.txt
```

The publish gate rejected it with `BLENDER_PUBLISH_REBUILD=FAIL` and the exact producer/path report, while Godot install/import, GdUnit4, and native suites were skipped. The PR was closed unmerged and the negative branch was reset back to the positive head.

## Blender source migration

The six tracked Blender masters have been migrated from `tools/blender/source/` into domain-specific locations under `assets-source/blender/`, and the deterministic Blender builders now point at those canonical paths.

`tools/blender/source/` is retired. CI rejects any tracked file that recreates the legacy root. There must never be two independently editable canonical copies of the same asset.

## Next gate: runtime asset quality

Step 14 proves ownership, rebuildability, declared outputs, side-effect containment, and downstream Godot consumability. It deliberately does **not** prove that a rebuilt GLB meets production budgets or structural expectations.

Step 15 therefore adds an **Asset Runtime Gate** between fresh publish/rebuild and Godot import. The first version will audit the real current runtime assets before setting budgets, then validate GLB/container integrity, node/mesh/material/skin/animation structure, accessor/buffer bounds, finite transforms, file-size and observed geometry/material metrics, and asset-type-specific contracts declared in metadata. Triangle/material/animation limits will be based on measured baselines and explicit contracts rather than invented global numbers.

Visual equivalence, screenshot review, player-visible quality, input feel, and audio/graphics acceptance remain separate manual or later visual-regression evidence; a structural runtime gate must not be presented as proof of final art quality.
