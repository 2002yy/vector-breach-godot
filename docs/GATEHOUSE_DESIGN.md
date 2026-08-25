# Gatehouse Design Record

Last updated: 2026-08-24
Data revision: `gatehouse-visual-v1.2`
Gameplay revision: `gatehouse-tactical-routes-v1`

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
- Booth panels, cover ribs, inspection-deck edging and route labels remain visual-only surface details. The former four floating overhead fixtures and emitters were removed from the generated asset, and legacy map point lights are disabled.
- Twenty-eight measured perimeter rhythm posts break up the 112 m boundary texture repeat. Every post has a validated 0 m ground gap and 0 m boundary-contact gap.
- Gatehouse inherits the project-wide architecture-free CC0 overcast sky, a warm shadowed directional key, restrained cool ambient light, ACES tonemapping, lightweight distance fog and SSAO.
- The generated GLB contains 121 objects, no shared mesh data, no overhead-light geometry, and no imported `StaticBody3D`; collision continues to come from the JSON graybox.

`GatehouseVisualProbe.tscn` captures Vulkan Forward+ first-person views at spawn, security approach, checkpoint, inspection deck, gate, and exit.

## Tactical navigation contract

- Three T and three CT spawn slots keep the teams separated before first contact.
- West, two mid branches, and east approaches feed two objective zones behind the checkpoint.
- The defender rotation joins both sites without crossing the attacker spawn.
- Each main route carries authored danger, cover, and precision metadata consumed by the shared AI graph.
- Three enabled T attackers and three enabled CT defenders exercise the west, rotation, and east branches; the route probe validates 39 nodes and 48 attributed links.
- The rotation defender carries a defuse kit; when the player is CT, CombatSandbox designates one T bot as the C4 carrier and assigns CT bots defend-site roles.
- 2026-07-31 player-collider sweeps measured first contact at 7.83 s (west), 8.39 s (mid) and 8.27 s (east), with 4.49 s site-to-site rotation; the west approach was rerouted around the inspection-deck stair to clear the collision envelope.

## Known design gaps

Gatehouse has 3v3 bomb AI, utility purchasing/throws, persistent economy and loadouts, measured timing, an automated halftime/overtime lifecycle, and an explicit no-natural-ladder/water semantic-volume record. It still lacks the G2 ten-match human verification, calibrated utility lineups, complete player-directed teammate tactics, final competitive balance, and G5 portfolio acceptance. The current route graph and visual foundation are tested foundations, not claims of final competitive or presentation quality.

Gatehouse is the sole primary map for the next phase defined in `docs/PROJECT_STATUS.md`. Local cover, doorway, stuck-point and rotation-distance edits are allowed only when evidence-backed; the three-route, two-site structure remains fixed, and every gameplay geometry change must rerun collision and timing gates.

Run all native regression suites from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1
```

Expected marker: `RUN_ALL_OK`.
