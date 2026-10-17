extends "res://scripts/level/GrayboxLevel.gd"


# Offline authoring keeps authoritative level data and real collision, while
# avoiding the original map's render meshes/textures during navigation baking.
func _apply_visual_scene(level_data: Dictionary, emit_errors: bool) -> void:
	var collision_only := level_data.duplicate()
	collision_only["visual_scene"] = ""
	collision_only["overlay_visual_scene"] = ""
	collision_only["retain_collision_meshes"] = true
	super._apply_visual_scene(collision_only, emit_errors)
