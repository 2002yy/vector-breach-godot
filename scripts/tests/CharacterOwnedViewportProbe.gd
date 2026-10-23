extends Node


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(preload("res://scenes/tests/CharacterBodyProbe.tscn").instantiate())
