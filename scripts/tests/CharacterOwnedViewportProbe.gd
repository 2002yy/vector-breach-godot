extends Node


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var scene: PackedScene = load("res://scenes/tests/CharacterBodyProbe.tscn")
	if "--runtime-bundle" in OS.get_cmdline_user_args():
		scene = load("res://scenes/tests/CharacterRuntimeBundleProbe.tscn")
	viewport.add_child(scene.instantiate())
