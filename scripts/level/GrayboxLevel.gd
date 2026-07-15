extends Node3D

const LevelDataLoader = preload("res://scripts/level/LevelDataLoader.gd")
const ShapeBuilder = preload("res://scripts/level/ShapeBuilder.gd")

signal level_loaded(level_data: Dictionary)

@export var level_id: String = "depot"

@onready var geometry_root: Node3D = $GeometryRoot
@onready var visual_root: Node3D = $VisualRoot
@onready var lighting_root: Node3D = $LightingRoot
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
	_apply_visual_scene(level_data, emit_errors)
	_apply_lights(level_data)
	_apply_markers(level_data)
	GameState.set_level(level_id, String(level_data.get("name", level_id)))
	level_loaded.emit(level_data)

func get_current_level_data() -> Dictionary:
	return _current_level_data

func _apply_visual_scene(level_data: Dictionary, emit_errors: bool) -> void:
	_clear_visual_scene()
	geometry_root.visible = true
	var visual_scene_path: String = String(level_data.get("visual_scene", ""))
	if visual_scene_path.is_empty():
		return
	if not ResourceLoader.exists(visual_scene_path, "PackedScene"):
		if emit_errors:
			push_warning("Missing level visual scene: %s" % visual_scene_path)
		return

	var visual_resource: Resource = load(visual_scene_path)
	if not (visual_resource is PackedScene):
		if emit_errors:
			push_warning("Level visual resource is not a PackedScene: %s" % visual_scene_path)
		return

	var visual_instance: Node = (visual_resource as PackedScene).instantiate()
	visual_instance.name = "LevelVisual"
	visual_root.add_child(visual_instance)
	geometry_root.visible = false

func _clear_visual_scene() -> void:
	for child in visual_root.get_children():
		child.free()

func _apply_lights(level_data: Dictionary) -> void:
	for child in lighting_root.get_children():
		child.free()
	var lighting: Dictionary = level_data.get("lights", {}) as Dictionary
	var points: Array = lighting.get("points", []) as Array
	var colors: Array = lighting.get("colors", []) as Array
	for index in range(points.size()):
		var point: Array = points[index] as Array
		if point.size() < 3:
			continue
		var light := OmniLight3D.new()
		light.name = "MapLight%02d" % index
		light.position = Vector3(float(point[0]), float(point[1]), float(point[2]))
		light.light_energy = 3.2
		light.omni_range = 15.0
		light.omni_attenuation = 1.15
		light.shadow_enabled = false
		if index < colors.size():
			var color_values: Array = colors[index] as Array
			if color_values.size() >= 3:
				light.light_color = Color(float(color_values[0]), float(color_values[1]), float(color_values[2]))
		lighting_root.add_child(light)

func _apply_markers(level_data: Dictionary) -> void:
	var start: Array = level_data.get("start", [0.0, 0.0]) as Array
	var exit: Array = level_data.get("exit", [0.0, 0.0]) as Array
	if start.size() >= 2:
		spawn_marker.position = Vector3(float(start[0]), 1.05, float(start[1]))
		spawn_marker.rotation.y = deg_to_rad(float(level_data.get("startYawDegrees", 0.0)))
		GameState.player_spawn = spawn_marker.position
		GameState.player_spawn_yaw_radians = spawn_marker.rotation.y
	if exit.size() >= 2:
		exit_marker.position = Vector3(float(exit[0]), 0.5, float(exit[1]))
