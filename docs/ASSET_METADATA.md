# Asset metadata contract

Step 12 adds a dependency-free JSON sidecar for canonical asset sources.

## Sidecar naming

A source file owns one adjacent sidecar by appending `.asset.json` to the full source filename.

Example:

```text
assets-source/blender/weapons/weapon_asset_source.blend
assets-source/blender/weapons/weapon_asset_source.blend.asset.json
```

Every tracked editable master (`.blend`, `.blend1`, `.kra`, `.psd`) and source-audio master (`.wav`, `.flac`, `.aif`, `.aiff`) under `assets-source/` must have a sidecar. Asset IDs must be repository-unique.

## Required v1 fields

```json
{
  "schema_version": 1,
  "asset_id": "VB-WEAPON-SET",
  "display_name": "Weapon Asset Set",
  "category": "weapon",
  "source_role": "canonical_master",
  "source_path": "assets-source/blender/weapons/weapon_asset_source.blend",
  "authoring_tool": "Blender",
  "provenance": {
    "origin": "unknown",
    "license_status": "unknown",
    "ai_usage": "unknown"
  },
  "runtime_outputs": [],
  "scale": {
    "unit": "meter"
  },
  "review": {
    "status": "legacy-imported"
  }
}
```

## Controlled values

- `category`: `map`, `character`, `weapon`, `prop`, `environment`, `ui`, `audio`, `vfx`, `texture`, `material`, `other`
- `source_role`: `canonical_master`, `canonical_input`
- `provenance.origin`: `project-authored`, `acquired`, `ai-generated`, `mixed`, `unknown`
- `provenance.license_status`: `project-owned`, `permitted`, `restricted`, `unknown`
- `provenance.ai_usage`: `none`, `assisted`, `generated`, `unknown`
- `scale.unit`: `meter`, `centimeter`, `none`, `unknown`
- `review.status`: `draft`, `approved`, `legacy-imported`, `blocked`

Historical information must use `unknown` when it cannot be established. Do not invent provenance to make metadata appear complete. A future release gate may be stricter than the repository-ingest gate and reject unresolved `unknown` license/provenance values.

## Runtime outputs

`runtime_outputs` contains reviewed published paths under `assets/`. It may be empty while a legacy asset's publish mapping is being reconstructed. Every non-empty entry must be a normalized POSIX-style repository path, must remain under `assets/`, and must name a file currently tracked by Git. Duplicate paths are rejected. Generated/intermediate files under `assets-generated/` are not runtime outputs.

This means a sidecar cannot silently keep a stale mapping after a published asset is renamed or deleted; the metadata gate fails until the mapping is updated.

## Flattened canonical inputs

By default, flattened delivery/preview formats such as PNG/JPG/WebP/KTX/DDS are rejected from `assets-source/`.

A future workflow may intentionally keep one as a canonical input only when its adjacent sidecar declares:

```json
{
  "source_role": "canonical_input",
  "allow_flattened_source": true,
  "provenance": {
    "origin": "acquired",
    "license_status": "permitted",
    "ai_usage": "none"
  }
}
```

For this exception, provenance origin must be known and `license_status` must be `project-owned` or `permitted`. This keeps the exception explicit and auditable instead of weakening the directory rule globally.

## CI

`tools/check_asset_metadata.py` validates metadata coverage, schema semantics, and live source-to-runtime mappings. `tools/check_asset_layers.py` consumes the same shared policy for flattened-source exceptions. Both run before Godot installation so metadata/path failures fail fast.
