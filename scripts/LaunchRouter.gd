extends Node


static func entry_for(args: PackedStringArray) -> String:
	if "--controlled-game" in args:
		return "res://scenes/ControlledGame.tscn"
	return "res://scenes/Main.tscn"


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(entry_for(OS.get_cmdline_user_args()))
