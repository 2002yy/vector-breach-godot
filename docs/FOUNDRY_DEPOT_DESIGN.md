# Foundry Depot Design Record

Last updated: 2026-07-15
Data revision: `foundry-cs-scale-v2`

This document records the design constraints behind the `depot` level. It is a traceability note, not a second source of runtime state.

## Sources of truth

- Runtime geometry and gameplay markers: `data/levels/depot.json`
- Godot collision and graybox assembly: `scripts/level/ShapeBuilder.gd`
- Blender visual generation: `tools/blender/build_foundry_assets.py`
- Generated visual asset: `assets/models/foundry/foundry_depot.glb`
- Editable Blender source: `tools/blender/source/foundry_asset_source.blend`

If this document and the JSON disagree, the JSON is authoritative. Update this record in the same commit whenever the dimensions or route responsibilities change.

## Scale contract

| Constraint | Authored value | Purpose |
|---|---:|---|
| Active combat footprint | 96 x 84 m | Supports separate long, mid, and service timings |
| Boundary height | 9 m | Contains the 4 m upper route without a miniature-room silhouette |
| Player collision height | 1.8 m | Human-scale FPS collision reference |
| Player eye height | 1.62 m | Player-eye composition and sightline validation |
| Player radius | 0.4 m | Route and spawn-point clearance margin |
| Standard corridor width | 4.0 m | Allows strafing, crossing, and two-player combat reads |
| Minimum door width | 1.4 m | Prevents decorative, non-playable openings |
| Indoor standing clearance | 3.4 m | Keeps low routes readable without crouch dependency |
| Upper combat floor | 4.0 m | Creates meaningful high/low fights and pass-under space |
| Full-height stair riser | 0.2 m | 20 steps over a 4 m rise |
| Maximum player step | 0.42 m | Player controller traversal safety limit |
| Spawn yaw | -90 degrees | Faces the first long-route anchor instead of the north boundary wall |

The player and architectural reference values were calibrated against Valve's Source/Counter-Strike dimension guidance, then rounded into metric values suitable for this original layout.

Reference: https://developer.valvesoftware.com/wiki/Dimensions_%28Half-Life_2_and_Counter-Strike%3A_Source%29

## Route responsibilities

| Route | Intended combat role | Key spaces |
|---|---|---|
| North long | Long-range lane with interrupting cover and a late turn into the objective side | Spawn court, long lane, east yard |
| Mid | Fastest contest route with close/medium fights and access to the main vertical landmark | Warehouse, furnace underpass, central platform |
| South service | Lower-ceiling flank with compressed sightlines and delayed exits | West drop, service tunnel, south approach |
| Upper loop | Four-meter high cross-map pressure route with sightlines into multiple ground spaces | Warehouse upper, central platform, control bridge |

The ground routes must remain spatially distinct. The upper route may connect combat zones, but it must not replace all ground-route decisions with one dominant sightline.

## Vertical contract

- Three independent full-height stairs connect ground level to the 4 m loop: warehouse, central platform, and control bridge.
- Each full-height stair is at least 2.6 m wide and uses approximately 0.2 m risers.
- Stair high edges must meet the declared `targetId` and `targetEdge` without a gap or overlap.
- Catwalks marked `passUnder` must keep traversable ground space below them.
- Any roof overlapping an upper platform must leave at least player height plus 0.4 m of headroom.
- Rail openings must align with their stair approaches; rails cannot cross the playable stair mouth.

## Collision and spawn invariants

- Every authored ground-route anchor must clear walls and covers by at least the 0.4 m player radius.
- Enemy spawn points must use the same clearance rule.
- Cover height stays between 1.0 and 1.85 m, and its longest horizontal dimension stays at or below 3.2 m.
- Generated Blender meshes are visual assets. Runtime collision continues to come from the same JSON through `ShapeBuilder.gd` so visuals and gameplay dimensions share one data source.

These invariants are enforced in `scripts/tests/GrayboxLevelTestRunner.gd`.

## Asset generation and validation

The Blender generator reads `depot.json`, builds the map and PBR materials, exports the GLB, renders the preview, and saves the editable `.blend`. Player-eye validation uses a 1.62 m camera height rather than the aerial presentation camera.

Run all regression suites from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1
```

Expected terminal marker: `RUN_ALL_OK`.
