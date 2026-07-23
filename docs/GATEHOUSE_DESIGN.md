# Gatehouse Design Record

Last updated: 2026-07-23
Data revision: `gatehouse-visual-v1`

Gatehouse is a broad security-checkpoint arena. Runtime geometry and collision are defined in `data/levels/gatehouse.json`; the deterministic visual recipe is `tools/blender/build_gatehouse_assets.py`.

## Legacy collision migration

The original level stored thirteen gameplay blocks only in the legacy `obstacles` array. The current `ShapeBuilder` does not build that array, so those blocks had no runtime collision. This revision preserves every original `x`, `z`, `sx`, `sz`, and `h` value while mapping the entries into:

- 4 wall blocks for the north security walls and south gate structures.
- 5 cover blocks for checkpoint booths and traffic barriers.
- 1 raised inspection floor.
- 3 climbable stair/speed-table blocks.

The legacy array remains as traceability data. `GrayboxLevelTestRunner` verifies that every legacy block has one identical semantic collision proxy.

## Visual contract

- The 112 x 112 m floor and four arena boundaries match the existing runtime floor and boundary collision.
- Fourteen floor joints and six broad traffic-wear zones establish the north-south checkpoint flow without changing navigation.
- Six maintenance cladding modules seat directly against authored walls with a measured maximum gap of 0 m.
- Booth panels, cover ribs, inspection-deck edging, route labels, and light fixtures remain visual-only surface details.
- The generated GLB contains 101 objects, no shared mesh data, and no imported `StaticBody3D`; collision continues to come from the JSON graybox.

`GatehouseVisualProbe.tscn` captures Vulkan Forward+ first-person views at spawn, security approach, checkpoint, inspection deck, gate, and exit.

## Known design gaps

Gatehouse still has no authored route graph, spawn-point groups, landmarks, objective zone, or semantic ladder/water volumes. Those should be designed as a separate gameplay pass rather than inferred from this visual treatment.

Run all native regression suites from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1 -GodotExe "E:\Godot\Godot_\Godot_console.exe"
```

Expected marker: `RUN_ALL_OK`.
