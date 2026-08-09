# Core Vault Design Record

Last updated: 2026-08-09
Data revision: `core-vault-visual-v1`
Gameplay revision: `core-vault-tactical-routes-v1`

Core Vault is a compact secured-storage arena built around a glowing central chamber. Runtime geometry and collision are defined in `data/levels/core-vault.json`; the deterministic visual recipe is `tools/blender/build_core_vault_assets.py`.

## Legacy collision migration

The original level stored fifteen gameplay blocks only in the legacy `obstacles` array. The current `ShapeBuilder` does not build that array, so those blocks had no runtime collision. This revision preserves every original `x`, `z`, `sx`, `sz`, and `h` value while mapping the entries into:

- 9 wall blocks, including the 6 x 6 m central vault core and the north/south lane dividers.
- 4 cover blocks for the inner-ring fighting positions.
- 2 climbable stair blocks on opposing inner-ring approaches.

The legacy array remains as traceability data. `GrayboxLevelTestRunner` verifies that every legacy block has one identical semantic collision proxy.

## Visual contract

- The 112 x 112 m floor and four 6 m-high arena boundaries match runtime floor and boundary collision.
- The central visual core remains inside the original 6 x 6 x 3.4 m collision envelope. Recessed panels, glass and sixteen light slats are surface details only.
- Fourteen floor joints and six broad wear zones reinforce the outer approach and inner combat ring without changing navigation.
- Eight maintenance cladding modules seat directly against authored walls with a measured maximum gap of 0 m.
- Route labels, boundary reinforcement, core corner trims, cover ribs and lighting remain visual-only.
- The generated GLB contains 177 objects, no shared mesh data and no imported `StaticBody3D`; collision continues to come from the JSON graybox.

`CoreVaultVisualProbe.tscn` captures Vulkan Forward+ first-person views at spawn, north side lane, the core, core flank, south approach and exit.

## Tactical navigation contract

- Three T and three CT spawn slots separate the north attack from the south inner-ring defense.
- Two outer-ring and two vault-side approaches feed objective zones on opposing sides of the core.
- A south rotation path connects both sites by clearing the inner wall and cover envelopes.
- Each main route carries authored danger, cover, and precision metadata consumed by the shared AI graph.
- Three enabled T attackers and three enabled CT defenders exercise the west, rotation, and east branches; the route probe validates 44 nodes and 54 attributed links.
- The rotation defender carries a defuse kit; when the player is CT, CombatSandbox designates one T bot as the C4 carrier and assigns CT bots defend-site roles.
- 2026-07-31 player-collider sweeps measured first contact at 8.23 s (west), 8.42 s (mid) and 8.23 s (east), with 10.16 s site-to-site rotation; all authored routes and the defender rotation clear the capsule sweep.

## Known design gaps

Core Vault has 3v3 bomb AI, utility purchasing/throws, persistent economy and loadouts, measured timing, and an explicit no-natural-ladder/water semantic-volume record. It still lacks calibrated utility lineups, human long-match verification, complete player-directed teammate tactics, and final competitive balance. The current route graph is a tested tactical foundation, not a claim of final competitive balance.

Core Vault is a regression and later-balance candidate during the Gatehouse phase. It must remain executable and keep its collision, tactical-route and bomb rules green, but it is not required to receive Gatehouse-level match tuning or portfolio polish in this phase.

Run all native regression suites from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1
```

Expected marker: `RUN_ALL_OK`.
