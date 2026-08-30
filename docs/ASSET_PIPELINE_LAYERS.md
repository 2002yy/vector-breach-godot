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

As of Step 15, the required CI pipeline proves both rebuildability and runtime structural/budget compliance before Godot consumes Blender-owned GLBs:

```text
assets-source/
  -> metadata producer + runtime contracts
  -> Blender 5.2.1 source validation
  -> existing deterministic builder
  -> fresh declared runtime outputs
  -> undeclared-side-effect check
  -> GLB runtime contract validation
  -> assets/
  -> Godot import
  -> GdUnit4
  -> native suites
```

The tracked runtime file already present in the checkout is never sufficient proof of rebuildability or runtime acceptance. The publish/rebuild gate removes each producer's declared outputs before invoking its builder and requires the files to be recreated; the runtime gate then validates that fresh output set before Godot is installed.

## Source-layer rules

- Editable masters such as `.blend`, `.kra`, and `.psd` must live under `assets-source/`; CI rejects competing canonical source roots elsewhere in the repository.
- Generated/intermediate content belongs in `assets-generated/`, and reviewed runtime content belongs in `assets/`.
- For v1, flattened delivery/preview formats such as `.png`, `.jpg`, `.jpeg`, `.webp`, `.ktx`, `.ktx2`, and `.dds`, plus GLTF/Godot import-cache outputs, are rejected from `assets-source/`.
- If a future workflow genuinely requires a flattened file as a canonical source input, metadata must introduce an explicit source-role exception with provenance rather than weakening the path boundary globally.

## Canonical producer contract

Each tracked canonical Blender master has an adjacent `*.asset.json` sidecar. For Blender masters the sidecar defines:

- a unique asset identity;
- the canonical source path;
- one tracked `build_script`;
- a non-empty set of tracked runtime outputs under `assets/`;
- Step 15 `runtime_contracts` for every Blender-owned GLB output.

One runtime artifact may have only one canonical Blender producer. The current baseline contains **6 Blender producers owning 13 runtime outputs**, of which **7 are GLBs governed by Step 15 runtime contracts**.

`tools/blender/run_publish_rebuild_validation.py` executes those existing builders in isolation. It rejects missing fresh outputs, invalid/empty outputs, and asset-side paths modified outside the producer's declared contract. Between producers it restores the tracked working tree and stages the fresh declared outputs so downstream runtime/Godot checks consume the rebuilt set rather than the repository's old binaries.

The Tactical Actor legacy builder is wrapped by a thin portable adapter rather than duplicated. The adapter maps its old local Windows roots to the current checkout and suppresses Blender `.blend1`/`.blend2` backup rotation while the delegated build runs. The Foundry map likewise uses a thin publish adapter so its canonical producer no longer depends on or republishes the independent weapon producer.

## Acceptance evidence through Step 14

Positive acceptance at Step 14 head `72196969d5f81a6fe05b1d2b6c148c5ad1a04b0d` passed required `Tests` and the legacy `Godot Tests`: fresh Blender outputs were rebuilt first, then consumed by Godot import, GdUnit4, and native suites. PR #20 was merged as `bcb24be4a71b6863d558a73511e00d89e612a9fe`, and both main-branch push workflows completed successfully after the merge.

The do-not-merge negative acceptance PR #22 intentionally created the undeclared path:

```text
assets-source/blender/characters/NEGATIVE_ACCEPTANCE_UNDECLARED.txt
```

The publish gate rejected it with `BLENDER_PUBLISH_REBUILD=FAIL` and the exact producer/path report, while Godot install/import, GdUnit4, and native suites were skipped. The PR was closed unmerged and the negative branch was reset back to the positive head.

## Step 15 runtime gate

Step 15 validates **freshly rebuilt** Blender-owned GLBs after publish/rebuild and before Godot import. Contract shape is checked cheaply before Blender installation by `tools/check_runtime_asset_contracts.py`; actual artifacts are inspected by `tools/validate_runtime_assets.py` after the fresh rebuild.

The runtime validator checks GLB/glTF container structure and references, embedded resource/buffer/accessor bounds, finite transform metadata, triangle-mode primitives, asset metrics, extension allowlists, and per-output min/max requirements. Budgets are asset-specific and were selected from a measurement-only baseline rather than one invented global threshold.

Positive PR #25 head `5f525aeaca53e71f5914a3367db1c784ff4b1265` passed required `Tests` run **33308981479** and legacy `Godot Tests` run **33308981476**. The seven fresh GLBs passed runtime validation, then Godot import, GdUnit4, and native suites all passed.

The single-variable do-not-merge negative PR #26 reduced only Gatehouse `max.triangles` from `5000` to `3000`; the fresh output measured `3356`. Required `Tests` run **33310639857** failed exactly with:

```text
ASSET_RUNTIME_VALIDATION=FAIL
- assets/models/gatehouse/gatehouse.glb: budget exceeded for triangles: actual=3356 max=3000
```

Every later Godot/GdUnit/native stage was skipped. PR #26 was closed unmerged and its branch was reset to the positive #25 head.

## Blender source migration

The six tracked Blender masters have been migrated from `tools/blender/source/` into domain-specific locations under `assets-source/blender/`, and the deterministic Blender builders now point at those canonical paths.

`tools/blender/source/` is retired. CI rejects any tracked file that recreates the legacy root. There must never be two independently editable canonical copies of the same asset.

## Boundary after Step 15

Step 15 proves source ownership, rebuildability, side-effect containment, fresh GLB structural integrity, and explicit runtime budgets. It deliberately does **not** prove visual equivalence, screenshot quality, UV/art quality, texture-memory residency, final LOD/collision quality, player readability, input feel, audio quality, or real GPU performance.

Those remain separate visual/performance/manual evidence. The next engineering work should therefore add higher-level visual/performance regression where it is stable and useful, then push a real new feature or asset through the entire established pipeline instead of adding another overlapping asset-management or test framework.
