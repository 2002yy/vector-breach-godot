# Blender source validation gate

Step 13 adds a deterministic headless quality gate for canonical Blender masters under `assets-source/blender/`.

The validator deliberately reuses the repository's existing Blender builders and `blender_build_utils.py` conventions. It does not create a second export pipeline and does not treat MCP success, a rendered screenshot, or a successful GLB import as proof that an asset source is production-safe.

## Pinned validation runtime

CI uses **Blender 5.2.1 LTS** for this gate. The version is pinned so the same canonical `.blend` files are inspected by a repeatable Blender/Python runtime instead of whichever interactive Blender version happens to be installed on a developer machine.

The current canonical masters were written by the Blender 5.2 generation. Blender 4.4 cannot read the 5.x blendfile format. Blender 4.5 LTS can act as a compatibility bridge, but the real masters produce newer-writer/data-loss warnings there, so the production gate is intentionally aligned with Blender 5.2.1 LTS instead of using the compatibility bridge.

The tracked masters are Blender-compressed Zstandard files. The runner recognizes both ordinary `BLENDER` headers and the Zstandard frame header used by compressed `.blend` files, then asks Blender to open the **canonical repository file directly**. It does not externally decompress a source into `/tmp`: doing so changes the base path used by Blender `//` relative resources and can create false missing-texture failures.

## Command

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

## v1 checks

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

## Acceptance evidence

The positive Step 13 PR baseline validates all six tracked canonical Blender masters on Blender 5.2.1 LTS with zero source violations, then continues through Godot import, GdUnit4, and native suites.

A dedicated **do-not-merge** negative acceptance PR (#19) mutated one checked-out weapon mesh at CI runtime from unit scale to `(2, 1, 1)` after the Asset Layer and Asset Metadata checks. The Blender gate reported exactly:

```text
geometry object has unapplied scale: 'GEO-pistol-barrel' (2.0, 1.0, 1.0)
```

The Blender job failed and every later Godot/GdUnit/native stage was skipped. The negative branch changed only the ephemeral CI working tree; no intentionally broken `.blend` was merged or retained as a canonical source asset.

## Deliberate Step 13 exclusions

This first gate does **not** yet claim to validate topology quality, UV coverage, material-count budgets, rig hierarchy, animation clips, collision authoring, LODs, triangle budgets, or GLB visual equivalence. Those checks require asset-type-specific contracts and evidence and will be added only after this baseline remains stable on the real masters.

## CI order

The required `Tests` workflow is ordered to fail cheaply:

```text
Asset layer policy
  -> Asset metadata policy
  -> Install Blender 5.2.1 LTS
  -> Blender source validation
  -> Install Godot
  -> Godot import
  -> GdUnit4
  -> native suites
```

A source-art violation therefore blocks the expensive Godot stages instead of surfacing later as an import or runtime accident.
