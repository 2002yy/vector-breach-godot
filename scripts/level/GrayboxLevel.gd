extends Node3D

const LevelDataLoader = preload("res://scripts/level/LevelDataLoader.gd")
const ShapeBuilder = preload("res://scripts/level/ShapeBuilder.gd")

signal level_loaded(level_data: Dictionary)

@export var level_id: String = "depot"
@export var load_on_ready := true
var load_count := 0
var last_load_timings: Dictionary = {}

@onready var geometry_root: Node3D = $GeometryRoot
@onready var visual_root: Node3D = $VisualRoot
@onready var lighting_root: Node3D = $LightingRoot
@onready var spawn_marker: Marker3D = $SpawnMarker
@onready var exit_marker: Marker3D = $ExitMarker

var _current_level_data: Dictionary = {}
var _render_profile_state: Dictionary = {}

func _ready() -> void:
	if load_on_ready:
		load_level(level_id)

func load_level(next_level_id: String, emit_errors: bool = true) -> bool:
	var began := Time.get_ticks_usec()
	load_count += 1
	last_load_timings = {"id": next_level_id, "success": false}
	level_id = next_level_id
	var level_data: Dictionary = LevelDataLoader.load_level(level_id, emit_errors)
	last_load_timings["data_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	if level_data.is_empty():
		last_load_timings["level_ms"] = (Time.get_ticks_usec() - began) / 1000.0
		return false

	_current_level_data = level_data
	var build_options: Dictionary = GameState.get_shape_build_options()
	var level_build_options: Variant = level_data.get("buildOptions", {})
	if level_build_options is Dictionary:
		build_options.merge(level_build_options as Dictionary, true)
	var phase := Time.get_ticks_usec()
	ShapeBuilder.build_into(geometry_root, level_data, build_options)
	last_load_timings["geometry_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	phase = Time.get_ticks_usec()
	_apply_visual_scene(level_data, emit_errors)
	last_load_timings["visual_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	phase = Time.get_ticks_usec()
	_apply_render_profile(level_data)
	_apply_lights(level_data)
	_apply_markers(level_data)
	GameState.set_level(level_id, String(level_data.get("name", level_id)))
	last_load_timings["setup_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	last_load_timings["level_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	last_load_timings["success"] = true
	level_loaded.emit(level_data)
	return true

func _apply_render_profile(level_data: Dictionary) -> void:
	_restore_render_profile()
	var viewport := get_viewport()
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var profile: Dictionary = level_data.get("render_profile", {})
	if profile.is_empty():
		return
	_render_profile_state = {"occlusion": viewport.use_occlusion_culling}
	if sun != null:
		_render_profile_state.shadow_distance = sun.directional_shadow_max_distance
		_render_profile_state.shadow_mode = sun.directional_shadow_mode
		var distance := float(profile.get("sun_shadow_distance", sun.directional_shadow_max_distance))
		if distance > 0.0:
			sun.directional_shadow_max_distance = distance
		if int(profile.get("sun_shadow_cascades", 4)) == 2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	var path := String(profile.get("occluder_resource", ""))
	if path.is_empty() or not ResourceLoader.exists(path, "Occluder3D"):
		return
	var resource := load(path) as Occluder3D
	if resource == null:
		return
	var instance := OccluderInstance3D.new()
	instance.name = "LevelOccluder"
	instance.occluder = resource
	visual_root.add_child(instance)
	viewport.use_occlusion_culling = true

func _exit_tree() -> void:
	_restore_render_profile()

func _restore_render_profile() -> void:
	if _render_profile_state.is_empty():
		return
	get_viewport().use_occlusion_culling = bool(_render_profile_state.occlusion)
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null and _render_profile_state.has("shadow_distance"):
		sun.directional_shadow_max_distance = float(_render_profile_state.shadow_distance)
		sun.directional_shadow_mode = int(_render_profile_state.shadow_mode)
	_render_profile_state.clear()

func get_current_level_data() -> Dictionary:
	return _current_level_data

func _apply_visual_scene(level_data: Dictionary, emit_errors: bool) -> void:
	# Synchronous wall time only: nested layer timings must not be added twice.
	last_load_timings["visual_phases_ms"] = {}
	last_load_timings["scene_layers"] = {}
	var phase := Time.get_ticks_usec()
	_clear_visual_scene()
	phase = _finish_visual_phase("retire_previous", phase)
	geometry_root.visible = true
	var has_visible_scene := false
	# Build independent physics before the original render scene raises memory
	# pressure. Runtime keeps the shapes and transforms, not duplicate GPU meshes.
	var collision_instance := _instantiate_visual_resource(
		String(level_data.get("runtime_collision_scene", "")),
		"LevelCollisionSource",
		emit_errors
	)
	phase = _finish_visual_phase("collision_scene", phase)
	if collision_instance != null:
		if collision_instance is Node3D:
			(collision_instance as Node3D).visible = false
		_build_runtime_collision(collision_instance, emit_errors, not bool(level_data.get("retain_collision_meshes", false)))
	phase = _finish_visual_phase("collision_shapes", phase)
	var visual_instance := _instantiate_visual_resource(
		String(level_data.get("visual_scene", "")),
		"LevelVisual",
		emit_errors
	)
	phase = _finish_visual_phase("visual_scene", phase)
	if visual_instance != null:
		has_visible_scene = true
		_hide_filtered_visual_meshes(visual_instance, level_data.get("hidden_visual_name_contains", []) as Array)
		if bool(level_data.get("reconstructed_materials", false)):
			preload("res://scripts/level/ClassicResearchMaterials.gd").apply(visual_instance)
		phase = _finish_visual_phase("filter_and_reconstructed_materials", phase)
		if bool(level_data.get("original_reference_materials", false)) or String(level_data.get("id", "")) == "dustline-depths-original-local":
			_repair_reference_vertex_channels(visual_instance)
			phase = _finish_visual_phase("vertex_channels", phase)
			var effect_manifest := String(level_data.get("visual_scene", "")).get_base_dir().path_join("source-effects.json")
			preload("res://scripts/level/SourceEffectMaterials.gd").apply(visual_instance, effect_manifest)
			phase = _finish_visual_phase("effect_materials", phase)
			var overlay_manifest := String(level_data.get("visual_scene", "")).get_base_dir().path_join("source-overlay-offset.json")
			var overlays: int = preload("res://scripts/level/SourceOverlayMaterials.gd").apply(visual_instance, overlay_manifest)
			visual_instance.set_meta("source_overlay_repair_surfaces", overlays)
			phase = _finish_visual_phase("overlay_materials", phase)
			var decal_manifest := (
				String(level_data.get("visual_scene", ""))
				.get_base_dir().path_join("source-decal-alpha.json")
			)
			var decals: int = preload("res://scripts/level/SourceDecalMaterials.gd").apply(
				visual_instance, decal_manifest
			)
			visual_instance.set_meta("source_decal_alpha_surfaces", decals)
			phase = _finish_visual_phase("decal_materials", phase)
			var modulate_manifest := decal_manifest.get_base_dir().path_join("source-modulate.json")
			var modulates: int = preload("res://scripts/level/SourceModulateMaterials.gd").apply(
				visual_instance, modulate_manifest
			)
			visual_instance.set_meta("source_mod2x_surfaces", modulates)
			phase = _finish_visual_phase("mod2x_materials", phase)
			preload("res://scripts/level/SourceVisualHelpers.gd").apply(visual_instance)
			phase = _finish_visual_phase("visual_helpers", phase)
		if bool(level_data.get("runtime_collision_from_visual", false)):
			_build_runtime_collision(visual_instance, emit_errors)
		phase = _finish_visual_phase("visual_collision_shapes", phase)
		var batch_manifest := String(level_data.get("visual_scene", "")).get_base_dir().path_join("source-overlay-offset.json")
		if visual_instance is Node3D:
			preload("res://scripts/level/SourceStaticBatches.gd").apply(visual_instance, batch_manifest)
		phase = _finish_visual_phase("static_batches", phase)

	var overlay_instance := _instantiate_visual_resource(
		String(level_data.get("overlay_visual_scene", "")),
		"LevelOverlay",
		emit_errors
	)
	_finish_visual_phase("overlay_scene", phase)
	if overlay_instance != null:
		has_visible_scene = true

	geometry_root.visible = not has_visible_scene

func _finish_visual_phase(key: String, began: int) -> int:
	var ended := Time.get_ticks_usec()
	last_load_timings.visual_phases_ms[key] = (ended - began) / 1000.0
	return ended

func _repair_reference_vertex_channels(node: Node) -> void:
	# Source 2 foliage / fabric packs animation weights into COLOR_0.
	# glTF imports these as albedo tint, producing black / magenta surfaces.
	# Keep the original texture, alpha cutout and material tint; override only
	# the affected visual surfaces, never the shared resource or collision.
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo:
				continue
			var name_key := material.resource_name.to_lower()
			if name_key not in ["agave_plant_01", "dust_weeds_01", "grape_leaves_01", "olive_branch_01", "olive_bark_01", "palm_bark_01", "palm_frond_01", "sagebrush_01", "sumac_01", "weeds_cressa_01", "zebra_grass_01", "dust_awning_fabric_01", "dust_awning_fabric_ripped_01"]:
				continue
			var repaired := material.duplicate() as StandardMaterial3D
			repaired.vertex_color_use_as_albedo = false
			instance.set_surface_override_material(surface, repaired)
	for child in node.get_children():
		_repair_reference_vertex_channels(child)

func _instantiate_visual_resource(scene_path: String, stable_name: String, emit_errors: bool) -> Node:
	var began := Time.get_ticks_usec()
	# This helper also serves isolated fixtures outside load_level().
	if not last_load_timings.has("scene_layers"):
		last_load_timings["scene_layers"] = {}
	var timing := {"path": scene_path, "status": "skipped"}
	last_load_timings.scene_layers[stable_name] = timing
	if scene_path.is_empty():
		return null
	timing.status = "missing"
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		if emit_errors:
			push_warning("Missing level scene layer: %s" % scene_path)
		return null

	timing["cached_before_load"] = ResourceLoader.has_cached(scene_path)
	var scene_resource: Resource = load(scene_path)
	timing["resource_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	timing.status = "invalid"
	if not (scene_resource is PackedScene):
		if emit_errors:
			push_warning("Level scene layer is not a PackedScene: %s" % scene_path)
		return null

	var phase := Time.get_ticks_usec()
	var scene_instance: Node = (scene_resource as PackedScene).instantiate()
	timing["instantiate_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	scene_instance.name = stable_name
	phase = Time.get_ticks_usec()
	visual_root.add_child(scene_instance)
	timing["attach_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	timing["total_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	timing.status = "ready"
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

func _build_runtime_collision(root: Node, emit_errors: bool, release_meshes: bool = false) -> void:
	var collision_mesh_count: int = _build_runtime_collision_recursive(root, release_meshes)
	if collision_mesh_count == 0 and emit_errors:
		push_warning("Runtime collision requested, but no COLLISION_* meshes were found")

func _build_runtime_collision_recursive(node: Node, release_meshes: bool = false) -> int:
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
			if release_meshes and collision_shape != null:
				mesh_instance.mesh = null

	for child in node.get_children():
		collision_mesh_count += _build_runtime_collision_recursive(child, release_meshes)
	return collision_mesh_count

func _clear_visual_scene() -> void:
	for child in visual_root.get_children():
		child.free()

func _apply_lights(level_data: Dictionary) -> void:
	for child in lighting_root.get_children():
		child.free()
	var lighting: Dictionary = level_data.get("lights", {}) as Dictionary
	# The shared sky/ambient/shadowed key-light foundation owns normal map
	# illumination. Legacy overhead point lights stay opt-in so they cannot
	# reintroduce floating ceiling fixtures or flatten the scene by default.
	if not bool(lighting.get("enabled", false)):
		return
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
	var spawn_groups: Dictionary = level_data.get("spawnGroups", {}) as Dictionary
	var team_spawns: Array = spawn_groups.get(GameState.player_team, []) as Array
	if not team_spawns.is_empty():
		var selected_spawn: Array = team_spawns[team_spawns.size() / 2] as Array
		if selected_spawn.size() >= 2:
			start = selected_spawn
	if start.size() >= 2:
		spawn_marker.position = Vector3(float(start[0]), float(level_data.get("startHeight", 1.05)), float(start[1]))
		var yaw_degrees := float(level_data.get("startYawDegrees", 0.0))
		if not team_spawns.is_empty():
			yaw_degrees = 180.0 if GameState.player_team == "T" else 0.0
		spawn_marker.rotation.y = deg_to_rad(yaw_degrees)
		GameState.player_spawn = spawn_marker.position
		GameState.player_spawn_yaw_radians = spawn_marker.rotation.y
	if exit.size() >= 2:
		exit_marker.position = Vector3(float(exit[0]), float(level_data.get("exitHeight", 0.5)), float(exit[1]))
