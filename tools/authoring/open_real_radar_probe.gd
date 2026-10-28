extends SceneTree


func _initialize() -> void:
	_open.call_deferred()


func _open() -> void:
	root.add_child(load("res://tools/authoring/probe_real_radar.gd").new())
