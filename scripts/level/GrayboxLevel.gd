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
	var level_build_options: Variant = level_data.get("buildOptions", {})
	if level_build_options is Dictionary:
		build_options.merge(level_build_options as Dictionary, true)
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
	var has_visible_scene := false
	var visual_instance := _instantiate_visual_resource(
		String(level_data.get("visual_scene", "")),
		"LevelVisual",
		emit_errors
	)
	if visual_instance != null:
		has_visible_scene = true
		_hide_filtered_visual_meshes(visual_instance, level_data.get("hidden_visual_name_contains", []) as Array)
		if bool(level_data.get("runtime_collision_from_visual", false)):
			_build_runtime_collision(visual_instance, emit_errors)

	var collision_instance := _instantiate_visual_resource(
		String(level_data.get("runtime_collision_scene", "")),
		"LevelCollisionSource",
		emit_errors
	)
	if collision_instance != null:
		_build_runtime_collision(collision_instance, emit_errors)
		if collision_instance is Node3D:
			(collision_instance as Node3D).visible = false

	var overlay_instance := _instantiate_visual_resource(
		String(level_data.get("overlay_visual_scene", "")),
		"LevelOverlay",
		emit_errors
	)
	if overlay_instance != null:
		has_visible_scene = true

	geometry_root.visible = not has_visible_scene

func _instantiate_visual_resource(scene_path: String, stable_name: String, emit_errors: bool) -> Node:
	if scene_path.is_empty():
		return null
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		if emit_errors:
			push_warning("Missing level scene layer: %s" % scene_path)
		return null

	var scene_resource: Resource = load(scene_path)
	if not (scene_resource is PackedScene):
		if emit_errors:
			push_warning("Level scene layer is not a PackedScene: %s" % scene_path)
		return null

	var scene_instance: Node = (scene_resource as PackedScene).instantiate()
	scene_instance.name = stable_name
	visual_root.add_child(scene_instance)
	return scene_instance

func _hide_filtered_visual_meshes(root: Node, name_filters: Array) -> void:
	if name_filters.is_empty():
		return
	_hide_filtered_visual_meshes_recursive(root, name_filters)

func _hide_filtered_visual_meshes_recursive(node: Node, name_filters: Array) -> void:
	if node is Node3D:
		var normalized_name := String(node.name).to_lower()
		for filter_variant in name_filters:
			var name_filter := String(filter_variant).to_lower()
			if not name_filter.is_empty() and normalized_name.contains(name_filter):
				(node as Node3D).visible = false
				return
	for child in node.get_children():
		_hide_filtered_visual_meshes_recursive(child, name_filters)

func _build_runtime_collision(root: Node, emit_errors: bool) -> void:
	var collision_mesh_count: int = _build_runtime_collision_recursive(root)
	if collision_mesh_count == 0 and emit_errors:
		push_warning("Runtime collision requested, but no COLLISION_* meshes were found")

func _build_runtime_collision_recursive(node: Node) -> int:
	var collision_mesh_count: int = 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh_name: String = String(mesh_instance.name)
		if mesh_name.begins_with("COLLISION_") and mesh_instance.mesh != null:
			var collision_shape: Shape3D = mesh_instance.mesh.create_trimesh_shape()
			if collision_shape != null:
				var static_body := StaticBody3D.new()
				static_body.name = "RuntimeCollision"
				var shape_node := CollisionShape3D.new()
				shape_node.name = "CollisionShape3D"
				shape_node.shape = collision_shape
				mesh_instance.add_child(static_body)
				static_body.add_child(shape_node)
				collision_mesh_count += 1
			if mesh_name.begins_with("COLLISION_ONLY_"):
				mesh_instance.visible = false

	for child in node.get_children():
		collision_mesh_count += _build_runtime_collision_recursive(child)
	return collision_mesh_count

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
		spawn_marker.position = Vector3(float(start[0]), float(level_data.get("startHeight", 1.05)), float(start[1]))
		spawn_marker.rotation.y = deg_to_rad(float(level_data.get("startYawDegrees", 0.0)))
		GameState.player_spawn = spawn_marker.position
		GameState.player_spawn_yaw_radians = spawn_marker.rotation.y
	if exit.size() >= 2:
		exit_marker.position = Vector3(float(exit[0]), float(level_data.get("exitHeight", 0.5)), float(exit[1]))
