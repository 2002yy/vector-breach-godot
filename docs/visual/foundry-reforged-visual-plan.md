# Foundry Reforged Visual Plan

## Goal

Bring Foundry Reforged from a readable combat graybox to a publishable industrial FPS environment without changing its audited collision topology, route timing, doorway widths, cover dimensions, or local B-site high route.

The visual target is a restrained tactical foundry rather than a cinematic furnace interior. Enemy silhouettes and route readability take priority over fog, bloom, clutter, and dramatic darkness.

## Reference Direction

- Warm furnace focal lighting: https://newsroom.ubisoft-press.com/tom-clancys-the-divisionr-2-zweiter-8-spieler-raid-operation-stahlross-ab-dem-30-juni-spielbar
- Compact tactical foundry language: https://wraith-ops.com/
- Architecture-free overcast sky: https://polyhaven.com/a/overcast_soil_puresky
- Weathered painted metal: https://polyhaven.com/a/green_metal_rust
- Corrugated rusted metal: https://polyhaven.com/a/rusty_metal
- Damaged concrete hero surface: https://polyhaven.com/a/rebar_reinforced_concrete

These references define lighting ratios, material breakup, and industrial anatomy only. No third-party game geometry, textures, logos, or layout data is included.

## Zone Language

| Zone | Navigation color | Dominant material | Lighting role |
| --- | --- | --- | --- |
| A long and A site | Amber/orange | concrete, rusted steel, hazard paint | Warm furnace landmark and long-range silhouette separation |
| Mid | Neutral warm gray | worn concrete, dark structural steel | Highest gameplay readability and least visual noise |
| B service and B site | Desaturated teal/green | painted metal, corrugated shutters, concrete | Cool utility lighting and close-range room identification |
| Defender rotation | Low-saturation steel | concrete and blue metal | Visually quiet rotation corridor |

## Material Budget

- Use 1K PBR texture sets only.
- Target 256 to 512 pixels per meter for first-person surfaces.
- Keep broad walls and floors tileable; reserve damaged concrete for local hero panels.
- Use route paint, hazard bands, and authored geometry instead of copyrighted signage.
- Keep total exported GLB plus external environment assets below 64 MiB for this pass.

## Lighting Budget

- One shadowed directional key light.
- Architecture-free CC0 cloud HDRI for sky color and diffuse reflections; no photographed structures in the visible sky.
- Godot PhysicalSky remains the resource-free fallback for maps without a sky asset.
- Low-saturation 3D industrial skyline outside the playable boundary for real perspective and parallax.
- Ambient energy near 0.30 instead of the prototype default 0.70.
- Warm A-site and cool B-site local accents, but no permanent light directly behind common enemy positions.
- Lightweight distance fog only; volumetric fog remains disabled for the MX330 baseline.
- ACES tonemapping and restrained exposure. Bloom is optional and must not soften the crosshair or target silhouettes.

## Geometry Priorities

1. Correct UV scale and material assignment on existing route walls, floor, cover, stairs, and catwalk.
2. Door frames, wall bases, overhead beams, drains, and service panels to establish human scale.
3. One validated modular prop per family before duplication: cable spool, pump, valve unit, barrel/pallet cluster, and utility cabinet.
4. Route paint and site markings that do not alter collision.
5. Optional non-colliding decals after first-person route review.

## Validation Views

- Attacker spawn toward route split.
- A-long first contact and A-site entry.
- Mid west-to-east rotation sightline.
- B service first clearing chamber.
- B-site local catwalk and drop.

Every view must be checked for material scale, shadow continuity, enemy contrast, clutter intrusion, and visual/collision alignment before the asset is accepted.

## Delivery Status

The playable visual pass is implemented: the independent environment, architecture-free cloud sky, non-colliding 3D skyline, material zoning, box-projected UVs, doorway and drain details, route markings, hazard bands, localized props, and all five first-person acceptance views are generated and validated without changing collision. The rejected industrial courtyard HDRI was removed because its photographed structures had no gameplay-scale parallax.

The material and scale pass adds exported glTF base-color factors instead of Blender-only viewport tinting, 25 grounded wall bases, 16 grounded doorway kick sleeves, and 16 two-sided route accents across eight doorways. Blender interface validation reports `0.0m` maximum ground gap for both wall bases and kick sleeves, while Godot continues to build collision exclusively from the audited level JSON.

The structural rhythm pass adds 19 joined modules to long interior walls, four joined modules to the arena boundaries, and four wall-contact louver vents that distinguish A, Mid, and B without becoming cover. Each assembly is joined before export to limit object and draw-call growth; the completed map GLB contains 398 objects. Blender interface validation reports `0.0m` maximum ground gap for both module families and `0.0m` maximum wall-contact gap for the vents. These additions remain visual-only and do not change collision, route widths, or measured encounter timing.

Optional polish remains intentionally separate from this gameplay-safe pass: non-colliding oil, rust-run, and weld decals plus additional pallet and barrel dressing. These must be reviewed for silhouette noise and cover readability before entering the shipped GLB.
