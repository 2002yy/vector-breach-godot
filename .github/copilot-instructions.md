# Repository instructions

- Follow `AGENTS.md` and read `docs/PROJECT_STATUS.md` first; the status document is the sole progress and next-work entry.
- This is a Godot 4.6.2 GDScript FPS prototype. Keep gameplay collision and routes authoritative in `data/levels/*.json`.
- Keep runtime UI text Chinese-first and preserve UTF-8.
- Run `bash ./tools/run_godot_tests.sh` before finishing gameplay, map-data or UI work. Do not weaken existing tests to make a change pass.
- Visual GLB work must remain aligned with JSON collision and requires screenshot inspection; headless assertions alone are insufficient.
