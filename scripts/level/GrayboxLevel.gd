extends Node3D

const LevelDataLoader = preload("res://scripts/level/LevelDataLoader.gd")
const ShapeBuilder = preload("res://scripts/level/ShapeBuilder.gd")

signal level_loaded(level_data: Dictionary)

@export var level_id: String = "test-collision-room"

@onready var geometry_root: Node3D = $GeometryRoot
@onready var spawn_marker: Marker3D = $SpawnMarker
@onready var exit_marker: Marker3D = $ExitMarker

var _current_level_data: Dictionary = {}

func _ready() -> void:
	load_level(level_id)

func load_level(next_level_id: String, emit_errors: bool = true) -> void:
	level_id = next_level_id
	var level_data: Dictionary = LevelDataLoader.load_level(level_id, emit_errors)
	if level_data.is_empty():
		return

	_current_level_data = level_data
	var build_options: Dictionary = GameState.get_shape_build_options()
	ShapeBuilder.build_into(geometry_root, level_data, build_options)
	_apply_markers(level_data)
	GameState.set_level(level_id, String(level_data.get("name", level_id)))
	level_loaded.emit(level_data)

func get_current_level_data() -> Dictionary:
	return _current_level_data

func _apply_markers(level_data: Dictionary) -> void:
	var start: Array = level_data.get("start", [0.0, 0.0]) as Array
	var exit: Array = level_data.get("exit", [0.0, 0.0]) as Array
	if start.size() >= 2:
		spawn_marker.position = Vector3(float(start[0]), 1.75, float(start[1]))
		GameState.player_spawn = spawn_marker.position
	if exit.size() >= 2:
		exit_marker.position = Vector3(float(exit[0]), 0.5, float(exit[1]))
