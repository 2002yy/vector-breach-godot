# Vector Breach Agent Guide

## Start here

- Read `docs/PROJECT_STATUS.md` before planning work. It is the sole authoritative status and priority document.
- Inspect the current checkout, tests, level JSON and Git state before treating an older roadmap item as a real gap.
- The active game is the Godot 4.6 project in this repository. Do not reintroduce the legacy Babylon/WebGL implementation.

## Architecture

- `data/levels/*.json` is authoritative for collision topology, routes, objectives and semantic ladder/water volumes.
- `scripts/level/ShapeBuilder.gd` builds gameplay collision. Visual GLB assets must not silently change audited collision or route timing.
- Shared player rules belong in `scripts/player/PlayerController.gd`; map-specific movement forks are not allowed.
- Tactical actors and bots use `scripts/combat/TacticalActor.gd`, `scripts/combat/CombatSandbox.gd` and `scripts/ai/`.
- User-facing runtime text is Chinese-first. Preserve UTF-8.

## Validation

- Run all native tests after gameplay, map-data or UI changes:
  - Windows: `powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1`
  - Linux/cloud: `bash ./tools/run_godot_tests.sh`
- The success marker is `RUN_ALL_OK`.
- For rendering, HUD, materials or map-layout changes, also run the relevant Vulkan probe and inspect its screenshots.
- Foundry geometry changes must keep the route/contact audits green.

## Change discipline

- Preserve unrelated user work and stage explicit files.
- Update `docs/PROJECT_STATUS.md` in the same change when a listed capability or gap changes.
- Keep test-only fixtures out of shipped-level enumeration.
- Do not claim full navigation, multiplayer authority, production models or complete bomb AI until executable evidence exists.
