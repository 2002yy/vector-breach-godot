# Blender source masters

Canonical Blender masters live under this directory, grouped by asset domain when useful (for example `maps/`, `characters/`, and `weapons/`).

The previous `tools/blender/source/` location is retired. Existing deterministic build scripts have been updated to use the canonical `assets-source/blender/` paths, and CI rejects any tracked file that recreates the legacy source root.
