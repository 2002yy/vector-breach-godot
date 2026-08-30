# Blender asset validation and publish gates

The repository now has three distinct Blender/runtime gates before Godot. They must not be conflated:

1. **Step 13 — Blender Source Validation:** prove that canonical `.blend` masters themselves are structurally safe to open and author from.
2. **Step 14 — Blender Publish/Rebuild:** prove that canonical masters can reproduce their declared runtime artifacts through the repository's existing deterministic builders without undeclared asset-side effects.
3. **Step 15 — Asset Runtime Gate:** inspect the freshly rebuilt GLB runtime artifacts for structural integrity and measured production budgets before Godot imports them.

MCP success, a rendered screenshot, an old tracked GLB, or a successful Godot import alone is not proof of any of these gates.

## Pinned validation runtime

CI uses **Blender 5.2.1 LTS** for the Blender gates. The version is pinned so the same canonical `.blend` files are inspected and rebuilt by a repeatable Blender/Python runtime instead of whichever interactive Blender version happens to be installed on a developer machine.

The current canonical masters were written by the Blender 5.2 generation. Blender 4.4 cannot read the 5.x blendfile format. Blender 4.5 LTS can act as a compatibility bridge, but the real masters produce newer-writer/data-loss warnings there, so the production gate is intentionally aligned with Blender 5.2.1 LTS instead of using the compatibility bridge.

The tracked masters are Blender-compressed Zstandard files. The source runner recognizes both ordinary `BLENDER` headers and the Zstandard frame header used by compressed `.blend` files, then asks Blender to open the **canonical repository file directly**. It does not externally decompress a source into `/tmp`: doing so changes the base path used by Blender `//` relative resources and can create false missing-texture failures.

## Step 13 command

Linux / CI:

```bash
bash ./tools/blender/run_asset_validation.sh /path/to/blender
```

The runner discovers canonical masters with `git ls-files` and then filters tracked `.blend` / `.blend1` files under `assets-source/blender/`. Ignored local Blender backup files therefore cannot silently expand the validation set. Each tracked master is opened in background mode, paired with its adjacent `*.asset.json` sidecar, and inspected by `tools/blender/validate_asset_source.py`.

Success markers:

```text
BLENDER_ASSET_VALIDATION=PASS
BLENDER_ASSET_VALIDATION_ALL=PASS
```

Any source failure makes the runner exit non-zero.

## Step 13 v1 checks

### Naming safety

Objects, collections, and materials must have non-empty trimmed names and cannot contain path separators or control characters. Step 13 intentionally does not impose a repository-wide artistic prefix taxonomy yet; existing deterministic builders already use domain conventions such as `GEO-*`, while a premature global regex would create false failures across legacy masters.

### External texture integrity

Every unpacked externally backed Blender image must resolve to existing source files. The gate covers `FILE`, `SEQUENCE`, `MOVIE`, and `TILED` image sources. Tiled images resolve declared `<UDIM>` and `<UVTILE>` tokens per Blender tile number. Packed images and generated/viewer sources are not reported as missing external textures.

Relative Blender paths beginning with `//` are resolved from the canonical source master's directory, not from a temporary validation path.

### Geometry scale

Mesh and armature objects must use finite, positive, applied unit scale `(1, 1, 1)` within a small floating-point tolerance. Zero, near-zero, negative/mirrored, or unapplied geometry scale fails the gate.

### Transform integrity

Object location, rotation, and scale values must be finite. Mesh and armature world transforms must also remain non-singular. Location and rotation are not required to be zero because authored placement and orientation are legitimate source-scene data.

### Metadata/source identity

The logical source must live under `assets-source/blender/`, its adjacent sidecar must parse as a JSON object, and `metadata.source_path` must identify the canonical file actually being validated.

### Source binary preflight

Before launching Blender, each master is checked for a real Blender/Zstandard binary header. An unresolved Git LFS pointer or an unrelated/invalid binary fails before Blender starts.

## Step 13 acceptance evidence

The positive Step 13 PR baseline validates all six tracked canonical Blender masters on Blender 5.2.1 LTS with zero source violations, then continues through Godot import, GdUnit4, and native suites.

A dedicated **do-not-merge** negative acceptance PR (#19) mutated one checked-out weapon mesh at CI runtime from unit scale to `(2, 1, 1)` after the Asset Layer and Asset Metadata checks. The Blender gate reported exactly:

```text
geometry object has unapplied scale: 'GEO-pistol-barrel' (2.0, 1.0, 1.0)
```

The Blender job failed and every later Godot/GdUnit/native stage was skipped. The negative branch changed only the ephemeral CI working tree; no intentionally broken `.blend` was merged or retained as a canonical source asset.

## Step 14 — publish/rebuild contract

Every canonical Blender master now declares one tracked `build_script` and a non-empty list of tracked `runtime_outputs` in its adjacent sidecar. The current baseline is **6 canonical Blender producers owning 13 runtime outputs**. One runtime artifact may have only one canonical producer.

The gate is executed by:

```bash
python tools/blender/run_publish_rebuild_validation.py /path/to/blender
```

For each producer the runner:

1. removes that producer's declared runtime outputs from the CI working tree;
2. invokes the existing deterministic builder through Blender 5.2.1;
3. requires every declared output to be recreated, non-empty, and structurally recognizable at the file-signature level;
4. rejects asset-side paths changed outside that producer's declaration;
5. restores tracked source/runtime state between producers while preserving the newly rebuilt declared outputs in isolated staging;
6. places the full fresh output set back into the working tree for downstream runtime validation and Godot import.

This prevents a builder that silently failed to rewrite an existing tracked output from producing a stale-output false green.

The Tactical Actor keeps its legacy animation/export logic behind a thin portable adapter. The adapter remaps obsolete local Windows roots to the current checkout and temporarily sets Blender `preferences.filepaths.save_version = 0` so a CI/local rebuild cannot silently rotate ignored `.blend1`/`.blend2` files; the previous preference is restored afterward.

The Foundry map uses a thin publish adapter so map preview generation can remain compatible with the legacy builder without recreating weapon collections. Weapon runtime files are owned only by the independent Weapon producer.

## Step 14 acceptance evidence

Positive acceptance at feature head `72196969d5f81a6fe05b1d2b6c148c5ad1a04b0d` passed required `Tests` and the legacy `Godot Tests`: six real Blender producers rebuilt the declared runtime set, Godot imported the fresh assets, and GdUnit4/native suites passed. PR #20 was merged to `main` as `bcb24be4a71b6863d558a73511e00d89e612a9fe`; both main push workflows also completed successfully after merge.

The dedicated do-not-merge PR #22 injected one undeclared side effect:

```text
assets-source/blender/characters/NEGATIVE_ACCEPTANCE_UNDECLARED.txt
```

The gate failed exactly with:

```text
BLENDER_PUBLISH_REBUILD=FAIL
- VB-CHAR-TACTICAL-ACTOR modified undeclared asset paths: ['assets-source/blender/characters/NEGATIVE_ACCEPTANCE_UNDECLARED.txt']
```

Godot installation/import, GdUnit4, and native suites were skipped. The negative PR was closed unmerged and the negative branch was reset to the positive feature head.

A separate integration issue was also exposed during Step 14: a headless Eevee preview needed `libEGL.so.1` on the Ubuntu runner. CI now installs `libegl1`; preview generation was not removed or weakened to obtain a green build.

Foundry's historical freeze manifest was corrected to distinguish immutable gameplay/layout data from regenerable visual outputs. `depot.json` remains byte-frozen, while the deterministic Foundry GLB, preview PNG, and source `.blend` are declared regenerable outputs; a visual rebuild is not required to reproduce obsolete generated hashes byte-for-byte.

## Step 15 — Asset Runtime Gate

Step 15 runs **after fresh Blender publish/rebuild and before Godot import**. It covers the seven Blender-owned GLB outputs declared by the six canonical producers. Preview PNG pixel/visual quality remains outside this structural gate.

Each relevant sidecar declares a `runtime_contract` for every owned GLB. `tools/check_runtime_asset_contracts.py` validates the contract shape before Blender is installed, and `tools/validate_runtime_assets.py` validates the freshly rebuilt GLBs after Step 14.

V1 validates:

- GLB magic/version/declared length and chunk layout;
- parseable glTF JSON plus required scene graph references;
- embedded buffer/image resources and index ranges;
- bufferView/accessor offsets, component/type/count calculations, and bounds within declared buffers;
- finite node transforms and finite accessor min/max metadata;
- triangle-mode mesh primitives and measured triangle counts;
- measured file bytes, node/mesh/primitive/material/texture/image/skin/animation counts;
- required minimums and explicit maximum budgets from the per-output metadata contracts;
- allowlisted required/used extensions;
- asset-class expectations such as skins/animations only where the current runtime asset actually requires them.

Budgets were chosen from a measurement-only baseline before enforcement rather than from arbitrary global thresholds. Static maps, weapons, and the animated tactical actor therefore use different contracts.

## Step 15 acceptance evidence

Positive PR #25 head `5f525aeaca53e71f5914a3367db1c784ff4b1265` completed both PR workflows successfully:

- required `Tests` run **33308981479**: success;
- legacy `Godot Tests` run **33308981476**: success.

The required job rebuilt all six Blender producers first, then `Asset runtime validation` passed on the fresh seven-GLB set, and downstream Godot import, GdUnit4, and native suites also passed.

A dedicated **do-not-merge** negative acceptance PR #26 changed exactly one contract value relative to the positive head: Gatehouse `max.triangles` from `5000` to `3000`. The fresh rebuilt Gatehouse GLB measured `3356` triangles. Required `Tests` run **33310639857** failed exactly at the runtime gate with:

```text
ASSET_RUNTIME_VALIDATION=FAIL
- assets/models/gatehouse/gatehouse.glb: budget exceeded for triangles: actual=3356 max=3000
```

Godot installation/import, GdUnit4, and native suites were skipped. PR #26 was closed unmerged and the negative branch was force-reset to the positive #25 head, so no intentionally failing budget remains in repository history as an active branch tip.

This proves Step 15 is fail-closed on a freshly rebuilt over-budget runtime artifact rather than merely checking tracked files or relying on Godot import to catch the defect later.

## Deliberate exclusions after Step 15

Step 15 does **not** claim visual equivalence, UV/artistic quality, texture-memory residency, authored LOD/collision quality, final rig hierarchy semantics, screenshot readability, final character/art quality, input/audio feel, or GPU performance. Those require visual/performance/manual evidence or future asset-type-specific contracts.

The runtime gate currently governs Blender-owned GLBs only. Preview PNGs are rebuild evidence but are not pixel-diff or aesthetic-quality gates.

## Required CI order after Step 15

```text
Asset layer policy
  -> Asset metadata policy
  -> Asset runtime contract policy
  -> Install Blender 5.2.1 LTS
  -> Blender source validation
  -> Blender publish/rebuild validation
  -> Asset runtime validation
  -> Install Godot 4.7.1
  -> Godot import
  -> GdUnit4
  -> native suites
```

The goal is fail-closed evidence: source defects, producer/rebuild defects, and malformed or over-budget rebuilt runtime GLBs are rejected before the engine. The next engineering work should move upward into visual regression / performance evidence and then a real feature/asset change exercised end-to-end, rather than adding another overlapping DCC or test wrapper.
