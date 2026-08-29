# Blender source validation gate

Step 13 adds a deterministic headless quality gate for canonical Blender masters under `assets-source/blender/`.

The validator deliberately reuses the repository's existing Blender builders and `blender_build_utils.py` conventions. It does not create a second export pipeline and does not treat MCP success or a rendered screenshot as proof that an asset source is production-safe.

## Pinned validation runtime

CI uses Blender 4.4.1 for this gate. The version is pinned so the same canonical `.blend` files are inspected by a repeatable Blender/Python runtime instead of whichever interactive Blender version happens to be installed on a developer machine.

## Command

Linux / CI:

```bash
bash ./tools/blender/run_asset_validation.sh /path/to/blender
```

The runner discovers every tracked-style canonical `.blend` / `.blend1` master under `assets-source/blender/`, opens each one in background mode, loads its adjacent `*.asset.json` sidecar, and runs `tools/blender/validate_asset_source.py`.

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

Every unpacked Blender image whose source is an external file must resolve to an existing file. Packed images and generated Blender images are not reported as missing external textures.

### Geometry scale

Mesh and armature objects must use finite, positive, applied unit scale `(1, 1, 1)` within a small floating-point tolerance. Zero, near-zero, negative/mirrored, or unapplied geometry scale fails the gate.

### Transform integrity

Object location, rotation, and scale values must be finite. Mesh and armature world transforms must also remain non-singular. Location and rotation are not required to be zero because authored placement and orientation are legitimate source-scene data.

### Metadata/source identity

The opened `.blend` must live under `assets-source/blender/`, its adjacent sidecar must parse as a JSON object, and `metadata.source_path` must identify the file actually being validated.

## Deliberate Step 13 exclusions

This first gate does **not** yet claim to validate topology quality, UV coverage, material count budgets, rig hierarchy, animation clips, collision authoring, LODs, triangle budgets, or GLB visual equivalence. Those checks require asset-type-specific contracts and evidence and will be added only after this baseline proves stable on the real masters.

## CI order

The required `Tests` workflow is ordered to fail cheaply:

```text
Asset layer policy
  -> Asset metadata policy
  -> Install pinned Blender
  -> Blender source validation
  -> Install Godot
  -> Godot import
  -> GdUnit4
  -> native suites
```

A source-art violation therefore blocks the expensive Godot stages instead of surfacing later as an import or runtime accident.
