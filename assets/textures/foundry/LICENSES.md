# Foundry Texture Sources

The PBR texture sets in this directory are from [Poly Haven](https://polyhaven.com/) and are published under CC0.

- `concrete_floor_worn_001`: https://polyhaven.com/a/concrete_floor_worn_001
- `rusty_metal_02`: https://polyhaven.com/a/rusty_metal_02
- `blue_metal_plate`: https://polyhaven.com/a/blue_metal_plate
- `green_metal_rust`: https://polyhaven.com/a/green_metal_rust
- `corrugated_rusty_metal` (source asset `rusty_metal`): https://polyhaven.com/a/rusty_metal
- `rebar_reinforced_concrete`: https://polyhaven.com/a/rebar_reinforced_concrete

Only the 1K diffuse, roughness, and OpenGL normal channels are included. The Blender build script embeds them into the exported GLB assets.

## Integrity

The new source downloads were checked against the MD5 values published by the Poly Haven API:

```text
f69d8c507961f0629019652162090917  green_metal_rust_diffuse.jpg
a6cefc436aa41f73f15347dcf7a791d0  green_metal_rust_nor_gl.jpg
22cb8ebbd84cd90667a2734114fc4732  green_metal_rust_rough.jpg
ba829f953270d3ad87d8e86d840f71d6  corrugated_rusty_metal_diffuse.jpg
6133cf0df6fd63d0c484ca1669f90935  corrugated_rusty_metal_nor_gl.jpg
ec93adbfb6e4d8562a0272be937719dc  corrugated_rusty_metal_rough.jpg
26872652418ff6b6864be465ab4b396c  rebar_reinforced_concrete_diffuse.jpg
c644b423c0f51d69fbab9725fc2a18d8  rebar_reinforced_concrete_nor_gl.jpg
91beffb19a6e1537d74eb2ea735620c8  rebar_reinforced_concrete_rough.jpg
```
