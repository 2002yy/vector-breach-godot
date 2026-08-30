from __future__ import annotations

from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
LEGACY_BUILDER = PROJECT_ROOT / "tools" / "blender" / "build_tactical_actor.py"


def _portable_source() -> str:
    source = LEGACY_BUILDER.read_text(encoding="utf-8")
    replacements = {
        r'r"C:\Users\Zhang\Desktop\3Dgame\godot\assets\models\characters"': repr(
            str(PROJECT_ROOT / "assets" / "models" / "characters")
        ),
        r'r"C:\Users\Zhang\Desktop\3Dgame\godot\assets-source\blender\characters"': repr(
            str(PROJECT_ROOT / "assets-source" / "blender" / "characters")
        ),
    }
    for old, new in replacements.items():
        count = source.count(old)
        if count != 1:
            raise RuntimeError(
                f"Expected exactly one legacy tactical-actor path marker {old!r}, found {count}"
            )
        source = source.replace(old, new)
    return source


def main() -> None:
    namespace = {
        "__file__": str(LEGACY_BUILDER),
        "__name__": "__main__",
        "__package__": None,
    }
    previous_save_versions = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    try:
        exec(compile(_portable_source(), str(LEGACY_BUILDER), "exec"), namespace)
    finally:
        bpy.context.preferences.filepaths.save_version = previous_save_versions

    # Negative acceptance injection: this path is intentionally NOT declared in
    # the asset metadata. The publish/rebuild gate must reject it before Godot.
    undeclared = PROJECT_ROOT / "assets-source" / "blender" / "characters" / "NEGATIVE_ACCEPTANCE_UNDECLARED.txt"
    undeclared.write_text("intentional undeclared publish side effect\n", encoding="utf-8")

    print("TACTICAL_ACTOR_PORTABLE_PUBLISH=PASS")


if __name__ == "__main__":
    main()
