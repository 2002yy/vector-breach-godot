extends Node

const GRAYBOX_LEVEL_SCENE = preload("res://scenes/level/GrayboxLevel.tscn")
const LevelDataLoader = preload("res://scripts/level/LevelDataLoader.gd")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_all_tests()
	if _failures.is_empty():
		print("[GrayboxLevelTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return

	push_error("[GrayboxLevelTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_all_tests() -> void:
	await _run_test("default_load_applies_markers_and_geometry", _test_default_load_applies_markers_and_geometry)
	await _run_test("load_level_rebuilds_geometry_and_updates_state", _test_load_level_rebuilds_geometry_and_updates_state)
	await _run_test("semantic_ladder_and_water_volumes_build_metadata", _test_semantic_ladder_and_water_volumes_build_metadata)
	await _run_test("depot_uses_cs_scale_metrics", _test_depot_uses_cs_scale_metrics)
	await _run_test("depot_stairs_align_with_target_edges", _test_depot_stairs_align_with_target_edges)
	await _run_test("depot_route_points_clear_player_collision", _test_depot_route_points_clear_player_collision)
	await _run_test("optional_local_dustline_builds_imported_collision", _test_dustline_builds_imported_collision_and_custom_markers)
	await _run_test("foundry_reforged_builds_independent_ground_graybox", _test_foundry_reforged_builds_independent_ground_graybox)
	await _run_test("foundry_reforged_routes_clear_solids_and_interfaces", _test_foundry_reforged_routes_clear_solids_and_interfaces)
	await _run_test("visual_name_filters_hide_helpers_only", _test_visual_name_filters_hide_helpers_only)
	await _run_test("missing_level_does_not_clobber_current_state", _test_missing_level_does_not_clobber_current_state)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before: int = _failures.size()
	await callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[GrayboxLevelTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_vec3_close(actual: Vector3, expected: Vector3, epsilon: float, message: String) -> void:
	if actual.distance_to(expected) <= epsilon:
		return
	_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])

func _instantiate_level() -> Node3D:
	GameState.reset_runtime_state()
	GameState.set_graphics_preset("prototype")
	var level: Node3D = GRAYBOX_LEVEL_SCENE.instantiate()
	add_child(level)
	return level

func _cleanup_level(level: Node3D) -> void:
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func _expected_geometry_child_count(level_data: Dictionary) -> int:
	var build_options: Dictionary = level_data.get("buildOptions", {}) as Dictionary
	var generated_base_count: int = 0
	if bool(build_options.get("arena_floor_enabled", true)):
		generated_base_count += 1
	if bool(build_options.get("arena_bounds_enabled", true)):
		generated_base_count += 1
	return generated_base_count \
		+ (level_data.get("walls", []) as Array).size() \
		+ (level_data.get("covers", []) as Array).size() \
		+ (level_data.get("floors", []) as Array).size() \
		+ (level_data.get("stairs", []) as Array).size() \
		+ (level_data.get("ramps", []) as Array).size() \
		+ (level_data.get("catwalks", []) as Array).size() \
		+ (level_data.get("overheads", []) as Array).size() \
		+ (level_data.get("ladders", []) as Array).size() \
		+ (level_data.get("waterVolumes", []) as Array).size()

func _marker_start_position(level_data: Dictionary) -> Vector3:
	var start: Array = level_data.get("start", [0.0, 0.0]) as Array
	return Vector3(float(start[0]), float(level_data.get("startHeight", 1.05)), float(start[1]))

func _marker_exit_position(level_data: Dictionary) -> Vector3:
	var exit: Array = level_data.get("exit", [0.0, 0.0]) as Array
	return Vector3(float(exit[0]), float(level_data.get("exitHeight", 0.5)), float(exit[1]))

func _test_default_load_applies_markers_and_geometry() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	await get_tree().process_frame

	var level_data: Dictionary = LevelDataLoader.load_level("depot")
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var visual_root: Node3D = level.get_node("VisualRoot")
	var lighting_root: Node3D = level.get_node("LightingRoot")
	var spawn_marker: Marker3D = level.get_node("SpawnMarker")
	var exit_marker: Marker3D = level.get_node("ExitMarker")

	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "depot", "graybox level should load the portfolio map by default")
	_assert_equal(geometry_root.get_child_count(), _expected_geometry_child_count(level_data), "geometry root should contain the expected built node count for default level")
	_assert_true(not geometry_root.visible, "the default visual scene should hide duplicate graybox meshes while preserving collision")
	_assert_equal(visual_root.get_child_count(), 1, "the default depot should instantiate exactly one visual scene")
	_assert_true(_count_nodes_of_type(visual_root, "MeshInstance3D") >= 300, "the imported depot GLB should contain the complete authored mesh set")
	if visual_root.get_child_count() == 1:
		var depot_visual: Node = visual_root.get_child(0)
		_assert_equal(_count_nodes_with_name_prefix(depot_visual, "GEO-detail-wall-base-"), 38, "Depot should ground every authored wall with a structural base")
		_assert_equal(_count_nodes_with_name_prefix(depot_visual, "GEO-detail-wall-cladding-"), 8, "Depot should retain eight wall-contact maintenance cladding modules")
		_assert_equal(_count_nodes_with_name_prefix(depot_visual, "GEO-detail-floor-joint-"), 9, "Depot should retain its nine measured floor expansion joints")
		_assert_equal(_count_nodes_with_name_prefix(depot_visual, "GEO-detail-floor-wear-"), 7, "Depot should retain seven broad route wear zones")
		_assert_equal(_count_nodes_with_name_prefix(depot_visual, "GEO-detail-floor-drain-"), 3, "Depot should retain three route-anchored drainage grates")
		_assert_equal(_count_nodes_of_type(depot_visual, "StaticBody3D"), 0, "Depot's visual pass should not add collision outside the authored graybox")
	var depot_lights: Dictionary = level_data.get("lights", {}) as Dictionary
	_assert_equal(lighting_root.get_child_count(), (depot_lights.get("points", []) as Array).size(), "the default depot should instantiate every authored gameplay light")
	_assert_vec3_close(spawn_marker.position, _marker_start_position(level_data), 0.001, "spawn marker should match level start coordinate")
	_assert_true(is_equal_approx(spawn_marker.rotation.y, deg_to_rad(float(level_data.get("startYawDegrees", 0.0)))), "spawn marker should apply the authored starting yaw")
	_assert_vec3_close(exit_marker.position, _marker_exit_position(level_data), 0.001, "exit marker should match level exit coordinate")
	_assert_vec3_close(GameState.player_spawn, spawn_marker.position, 0.001, "GameState spawn should mirror the spawn marker")
	_assert_equal(String(GameState.current_level_id), "depot", "GameState should track the loaded default level id")
	_assert_equal(String(GameState.current_level_name), String(level_data.get("name", "")), "GameState should track the loaded default level name")

	await _cleanup_level(level)

func _test_load_level_rebuilds_geometry_and_updates_state() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	await get_tree().process_frame

	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var visual_root: Node3D = level.get_node("VisualRoot")
	var lighting_root: Node3D = level.get_node("LightingRoot")
	level.call("load_level", "test-collision-room")
	await get_tree().physics_frame
	await get_tree().process_frame
	var first_children: int = geometry_root.get_child_count()
	_assert_true(geometry_root.visible, "switching to a level without a visual asset should restore graybox meshes")
	_assert_equal(visual_root.get_child_count(), 0, "switching away from depot should clear its visual scene")
	level.call("load_level", "depot")
	await get_tree().physics_frame
	await get_tree().process_frame

	var depot_data: Dictionary = LevelDataLoader.load_level("depot")
	var spawn_marker: Marker3D = level.get_node("SpawnMarker")
	var exit_marker: Marker3D = level.get_node("ExitMarker")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "depot", "load_level should replace current level payload")
	_assert_equal(geometry_root.get_child_count(), _expected_geometry_child_count(depot_data), "geometry root should be rebuilt to the new level node count")
	_assert_true(not geometry_root.visible, "a loaded visual scene should hide graybox meshes without removing their collision nodes")
	_assert_equal(visual_root.get_child_count(), 1, "depot should instantiate exactly one visual scene")
	var depot_lights: Dictionary = depot_data.get("lights", {}) as Dictionary
	_assert_equal(lighting_root.get_child_count(), (depot_lights.get("points", []) as Array).size(), "depot should instantiate every authored gameplay light")
	if visual_root.get_child_count() > 0:
		_assert_equal(visual_root.get_child(0).name, "LevelVisual", "the visual scene should use a stable integration node name")
	var central_stair: Node3D = geometry_root.get_node_or_null("stair_central-platform-access") as Node3D
	_assert_true(central_stair != null, "depot should build the authored central platform stair")
	if central_stair != null:
		_assert_equal(central_stair.get_child_count(), 20, "central platform stair should use walkable brush-sized steps")
		if central_stair.get_child_count() == 20:
			var first_step: Node3D = central_stair.get_child(0) as Node3D
			var last_step: Node3D = central_stair.get_child(19) as Node3D
			_assert_true(last_step.position.y > first_step.position.y, "central platform stair should rise toward its platform opening")
	var warehouse_catwalk: Node3D = geometry_root.get_node_or_null("catwalk_warehouse-upper") as Node3D
	_assert_true(warehouse_catwalk != null, "depot should build the authored warehouse upper structure")
	if warehouse_catwalk != null:
		_assert_true(warehouse_catwalk.get_node_or_null("support_0_0") != null, "catwalk visual supports should have matching gameplay collision")
		_assert_true(warehouse_catwalk.get_node_or_null("rail_z-_bar_0_0") != null, "catwalk should keep the first rail span beside its stair opening")
		_assert_true(warehouse_catwalk.get_node_or_null("rail_z-_bar_1_0") != null, "catwalk should keep the second rail span beside its stair opening")
	_assert_true(geometry_root.get_child_count() != first_children, "switching to depot should change built geometry count from the default room")
	_assert_vec3_close(spawn_marker.position, _marker_start_position(depot_data), 0.001, "spawn marker should update when loading depot")
	_assert_true(is_equal_approx(GameState.player_spawn_yaw_radians, spawn_marker.rotation.y), "GameState should mirror the authored depot spawn yaw")
	_assert_vec3_close(exit_marker.position, _marker_exit_position(depot_data), 0.001, "exit marker should update when loading depot")
	_assert_equal(String(GameState.current_level_id), "depot", "GameState should switch to depot after load_level")

	await _cleanup_level(level)

func _test_semantic_ladder_and_water_volumes_build_metadata() -> void:
	var level: Node3D = _instantiate_level()
	level.call("load_level", "test-collision-room")
	await get_tree().physics_frame
	await get_tree().process_frame
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var ladder := geometry_root.get_node_or_null("Ladder_ladder-calibration") as Area3D
	var shallow_water := geometry_root.get_node_or_null("Water_shallow-water-calibration") as Area3D
	var deep_water := geometry_root.get_node_or_null("Water_deep-water-calibration") as Area3D
	_assert_true(ladder != null, "test room should build its authored Ladder Area3D")
	_assert_true(shallow_water != null and deep_water != null, "test room should build shallow and deep Water Area3D volumes")
	if ladder != null:
		_assert_equal(String(ladder.get_meta("environment_type", "")), "ladder", "ladder should expose stable environment metadata")
		_assert_true(float(ladder.get_meta("ladder_top", 0.0)) > float(ladder.get_meta("ladder_bottom", 0.0)), "ladder metadata should preserve a positive climb height")
		_assert_equal(ladder.collision_layer, 2, "ladder semantic volume should use the environment collision layer")
	if shallow_water != null and deep_water != null:
		_assert_true(float(shallow_water.get_meta("water_depth", 0.0)) < 1.2, "shallow water fixture should remain below the deep-water threshold")
		_assert_true(float(deep_water.get_meta("water_depth", 0.0)) >= 1.2, "deep water fixture should reach the deep-water threshold")
	await _cleanup_level(level)

func _test_depot_stairs_align_with_target_edges() -> void:
	var depot_data: Dictionary = LevelDataLoader.load_level("depot")
	var targets: Dictionary = {}
	for group_name in ["floors", "catwalks"]:
		for entry_variant in depot_data.get(group_name, []):
			var entry: Dictionary = entry_variant as Dictionary
			var entry_id := String(entry.get("id", ""))
			if not entry_id.is_empty():
				targets[entry_id] = entry

	for stair_variant in depot_data.get("stairs", []):
		var stair: Dictionary = stair_variant as Dictionary
		var stair_id := String(stair.get("id", ""))
		var target_id := String(stair.get("targetId", ""))
		_assert_true(targets.has(target_id), "stair %s should reference an existing platform or catwalk" % stair_id)
		if not targets.has(target_id):
			continue
		var target: Dictionary = targets[target_id] as Dictionary
		var direction := String(stair.get("direction", ""))
		var target_edge := String(stair.get("targetEdge", ""))
		var stair_edge := _box_edge(stair, direction)
		var target_position := _box_edge(target, target_edge)
		_assert_true(is_equal_approx(stair_edge, target_position), "stair %s should meet target edge %s without a gap or overlap" % [stair_id, target_edge])
		_assert_true(is_equal_approx(float(stair.get("h", 0.0)), float(target.get("h", 0.0))), "stair %s should finish at its target platform height" % stair_id)

func _test_depot_uses_cs_scale_metrics() -> void:
	var depot_data: Dictionary = LevelDataLoader.load_level("depot")
	var metrics: Dictionary = depot_data.get("metrics", {}) as Dictionary
	_assert_true(is_equal_approx(float(metrics.get("playerHeight", 0.0)), 1.8), "depot scale should be authored around a 1.8 meter player")
	_assert_true(float(depot_data.get("arenaSizeX", 0.0)) * 2.0 >= 90.0, "depot should preserve a CS-sized long-axis combat distance")
	_assert_true(float(depot_data.get("arenaSizeZ", 0.0)) * 2.0 >= 80.0, "depot should preserve enough depth for three distinct routes")

	for cover_variant in depot_data.get("covers", []):
		var cover: Dictionary = cover_variant as Dictionary
		var cover_height := float(cover.get("h", 0.0))
		_assert_true(cover_height >= 1.0 and cover_height <= 1.85, "cover %s should stay within crouch/full-cover scale" % String(cover.get("id", "")))
		_assert_true(maxf(float(cover.get("sx", 0.0)), float(cover.get("sz", 0.0))) <= 3.2, "cover %s should not become an oversized sight-blocking ribbon" % String(cover.get("id", "")))

	var full_height_accesses := 0
	for stair_variant in depot_data.get("stairs", []):
		var stair: Dictionary = stair_variant as Dictionary
		var step_count := maxi(1, int(stair.get("steps", 1)))
		var riser := float(stair.get("h", 0.0)) / float(step_count)
		var direction := String(stair.get("direction", "x+"))
		var width := float(stair.get("sz", 0.0)) if direction.begins_with("x") else float(stair.get("sx", 0.0))
		_assert_true(riser >= 0.18 and riser <= 0.22, "stair %s should use roughly 20 cm risers" % String(stair.get("id", "")))
		_assert_true(width >= 2.6, "stair %s should allow a readable multi-player combat lane" % String(stair.get("id", "")))
		if float(stair.get("h", 0.0)) >= 3.8:
			full_height_accesses += 1
	_assert_true(full_height_accesses >= 3, "depot upper route should have at least three independent full-height accesses")

	for overhead_variant in depot_data.get("overheads", []):
		var overhead: Dictionary = overhead_variant as Dictionary
		_assert_true(float(overhead.get("y", 0.0)) >= 3.25, "overhead %s should preserve standing combat clearance" % String(overhead.get("id", "")))

	var player_height := float(metrics.get("playerHeight", 1.8))
	for catwalk_variant in depot_data.get("catwalks", []):
		var catwalk: Dictionary = catwalk_variant as Dictionary
		for overhead_variant in depot_data.get("overheads", []):
			var overhead: Dictionary = overhead_variant as Dictionary
			if not _boxes_overlap_xz(catwalk, overhead):
				continue
			var roof_underside := float(overhead.get("y", 0.0)) - float(overhead.get("thickness", 0.0)) * 0.5
			var upper_clearance := roof_underside - float(catwalk.get("h", 0.0))
			_assert_true(upper_clearance >= player_height + 0.4, "catwalk %s should keep headroom below %s" % [String(catwalk.get("id", "")), String(overhead.get("id", ""))])

func _test_depot_route_points_clear_player_collision() -> void:
	var depot_data: Dictionary = LevelDataLoader.load_level("depot")
	var routes: Dictionary = depot_data.get("routes", {}) as Dictionary
	var solids: Array = []
	solids.append_array(depot_data.get("walls", []) as Array)
	solids.append_array(depot_data.get("covers", []) as Array)
	var player_radius := 0.4

	for route_name in ["long", "mid", "service"]:
		var points: Array = routes.get(route_name, []) as Array
		_assert_true(points.size() >= 4, "route %s should keep enough authored navigation anchors" % route_name)
		for point_index in points.size():
			var point: Array = points[point_index] as Array
			for solid_variant in solids:
				var solid: Dictionary = solid_variant as Dictionary
				_assert_true(not _point_inside_box_with_margin(point, solid, player_radius), "route %s point %d should clear %s by one player radius" % [route_name, point_index, String(solid.get("id", ""))])

	for spawn_variant in depot_data.get("spawnPoints", []):
		var spawn: Dictionary = spawn_variant as Dictionary
		var point := [float(spawn.get("x", 0.0)), float(spawn.get("z", 0.0))]
		for solid_variant in solids:
			var solid: Dictionary = solid_variant as Dictionary
			_assert_true(not _point_inside_box_with_margin(point, solid, player_radius), "spawn point on %s should clear %s by one player radius" % [String(spawn.get("route", "")), String(solid.get("id", ""))])

func _point_inside_box_with_margin(point: Array, entry: Dictionary, margin: float) -> bool:
	if point.size() < 2:
		return true
	var half_x := float(entry.get("sx", 0.0)) * 0.5 + margin
	var half_z := float(entry.get("sz", 0.0)) * 0.5 + margin
	return absf(float(point[0]) - float(entry.get("x", 0.0))) <= half_x \
		and absf(float(point[1]) - float(entry.get("z", 0.0))) <= half_z

func _boxes_overlap_xz(a: Dictionary, b: Dictionary) -> bool:
	var x_overlap := absf(float(a.get("x", 0.0)) - float(b.get("x", 0.0))) \
		< (float(a.get("sx", 0.0)) + float(b.get("sx", 0.0))) * 0.5
	var z_overlap := absf(float(a.get("z", 0.0)) - float(b.get("z", 0.0))) \
		< (float(a.get("sz", 0.0)) + float(b.get("sz", 0.0))) * 0.5
	return x_overlap and z_overlap

func _box_edge(entry: Dictionary, edge: String) -> float:
	match edge:
		"x+":
			return float(entry.get("x", 0.0)) + float(entry.get("sx", 0.0)) * 0.5
		"x-":
			return float(entry.get("x", 0.0)) - float(entry.get("sx", 0.0)) * 0.5
		"z+":
			return float(entry.get("z", 0.0)) + float(entry.get("sz", 0.0)) * 0.5
		"z-":
			return float(entry.get("z", 0.0)) - float(entry.get("sz", 0.0)) * 0.5
	return INF

func _count_nodes_of_type(root: Node, type_name: StringName) -> int:
	var count := 1 if root.is_class(type_name) else 0
	for child in root.get_children():
		count += _count_nodes_of_type(child, type_name)
	return count

func _count_nodes_with_name_prefix(root: Node, prefix: String) -> int:
	var count := 1 if String(root.name).begins_with(prefix) else 0
	for child in root.get_children():
		count += _count_nodes_with_name_prefix(child, prefix)
	return count

func _all_prefixed_meshes_hidden(root: Node, prefix: String) -> bool:
	if root is MeshInstance3D and String(root.name).begins_with(prefix):
		if (root as MeshInstance3D).visible:
			return false
	for child in root.get_children():
		if not _all_prefixed_meshes_hidden(child, prefix):
			return false
	return true

func _test_dustline_builds_imported_collision_and_custom_markers() -> void:
	if not FileAccess.file_exists("res://data/levels/dustline-depths.json"):
		return
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	level.call("load_level", "dustline-depths")
	await get_tree().physics_frame
	await get_tree().process_frame

	var level_data: Dictionary = LevelDataLoader.load_level("dustline-depths")
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var visual_root: Node3D = level.get_node("VisualRoot")
	var spawn_marker: Marker3D = level.get_node("SpawnMarker")
	var exit_marker: Marker3D = level.get_node("ExitMarker")

	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "dustline-depths", "dustline should load as an independent level")
	_assert_equal(geometry_root.get_child_count(), 0, "dustline should not overlay generated graybox floor or boundary nodes")
	_assert_equal(visual_root.get_child_count(), 1, "dustline should instantiate exactly one authored visual scene")
	if visual_root.get_child_count() == 1:
		var level_visual: Node = visual_root.get_child(0)
		var collision_mesh_count: int = _count_nodes_with_name_prefix(level_visual, "COLLISION_")
		var runtime_body_count: int = _count_nodes_of_type(level_visual, "StaticBody3D")
		_assert_equal(collision_mesh_count, 35, "dustline should expose 32 locked base collision groups plus three skywalk collision parts")
		_assert_equal(runtime_body_count, collision_mesh_count, "every authored collision mesh should receive one runtime StaticBody3D")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "COLLISION_ONLY_"), 2, "dustline should retain both player-clip groups")
		_assert_true(_all_prefixed_meshes_hidden(level_visual, "COLLISION_ONLY_"), "player-clip meshes should remain collidable without rendering")
		_assert_true(level_visual.find_child("VISUAL_NAV_FLOOR_DUST2_BASE", true, false) != null, "dustline should retain the exact nav-derived floor overlay")
		_assert_true(level_visual.find_child("COLLISION_VISIBLE_SKYBRIDGE_deck_00", true, false) != null, "dustline should retain its single authored high-route deck")
	_assert_vec3_close(spawn_marker.position, _marker_start_position(level_data), 0.001, "dustline spawn should preserve the authored T-side height")
	_assert_vec3_close(exit_marker.position, _marker_exit_position(level_data), 0.001, "dustline exit should preserve the authored A-site height")
	_assert_vec3_close(GameState.player_spawn, spawn_marker.position, 0.001, "GameState should mirror the elevated dustline spawn")

	await _cleanup_level(level)

func _test_foundry_reforged_builds_independent_ground_graybox() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	level.call("load_level", "foundry-reforged")
	await get_tree().physics_frame
	await get_tree().process_frame

	var level_data: Dictionary = LevelDataLoader.load_level("foundry-reforged")
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var visual_root: Node3D = level.get_node("VisualRoot")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "foundry-reforged", "Foundry Reforged should load independently from Depot v2")
	_assert_true(not geometry_root.visible, "Foundry Reforged should hide duplicate graybox rendering while retaining its collision")
	_assert_equal(visual_root.get_child_count(), 1, "Foundry Reforged should instantiate exactly one independent industrial visual")
	_assert_equal(geometry_root.get_child_count(), _expected_geometry_child_count(level_data), "Foundry Reforged should build every authored graybox group")
	_assert_true(geometry_root.get_node_or_null("catwalk_b-local-catwalk") != null, "Foundry Reforged should build its single localized B catwalk")
	_assert_true(geometry_root.get_node_or_null("stair_b-catwalk-access") != null, "the localized B catwalk should keep one measured stair access")
	_assert_true(geometry_root.get_node_or_null("ramp_a-long-ramp") != null, "A long should build its authored ground ramp")
	if visual_root.get_child_count() == 1:
		var level_visual: Node = visual_root.get_child(0)
		_assert_equal(String(level_visual.name), "LevelVisual", "Foundry Reforged visual should use the stable integration name")
		_assert_true(_count_nodes_of_type(level_visual, "MeshInstance3D") >= 280, "Foundry Reforged visual should retain the complete material and environment asset pass")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-skyline-") >= 20, "Foundry Reforged should retain its perspective-correct distant industrial skyline")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-wall-base-") >= 25, "every authored wall except the furnace core should keep a grounded visual base")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-door-kick-") >= 16, "all eight doorways should keep two grounded protective sleeves")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-door-accent-") >= 16, "doorways should expose route color on both approach faces")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-wall-module-") >= 19, "long walls should retain their joined structural bay modules")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-wall-vent-") >= 4, "A, Mid, and B should retain four wall-contact ventilation landmarks")
		_assert_true(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-boundary-module-") >= 4, "the four arena boundaries should retain joined long-span structure modules")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-equipment-"), 3, "the cable spool, pump, and valve should replace their generic cover visuals")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-surface-oil-"), 3, "surface dressing should retain three low-profile oil stains")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-surface-rust-"), 3, "surface dressing should retain three wall-contact rust runs")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-surface-weld-"), 3, "surface dressing should retain three wall-contact weld seams")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-wall-cladding-"), 6, "long walls should retain six grounded maintenance cladding modules")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-floor-joint-"), 9, "the arena floor should retain its expansion-joint rhythm")
		_assert_equal(_count_nodes_with_name_prefix(level_visual, "GEO-reforged-floor-wear-"), 7, "major routes should retain seven broad floor-wear zones")
		_assert_equal(_count_nodes_of_type(level_visual, "StaticBody3D"), 0, "the visual-only skyline should not add collision outside the audited graybox")

	await _cleanup_level(level)

func _test_foundry_reforged_routes_clear_solids_and_interfaces() -> void:
	var level_data: Dictionary = LevelDataLoader.load_level("foundry-reforged")
	var routes: Dictionary = level_data.get("routes", {}) as Dictionary
	var solids: Array = []
	solids.append_array(level_data.get("walls", []) as Array)
	solids.append_array(level_data.get("covers", []) as Array)
	var player_margin := 0.45

	for route_name in ["aLong", "mid", "midToA", "midToB", "bServiceDock", "bServiceControl", "defenderRotation"]:
		var points: Array = routes.get(route_name, []) as Array
		for point_index in range(points.size() - 1):
			var from_point: Array = points[point_index] as Array
			var to_point: Array = points[point_index + 1] as Array
			for solid_variant in solids:
				var solid: Dictionary = solid_variant as Dictionary
				_assert_true(
					not _segment_intersects_expanded_box(from_point, to_point, solid, player_margin),
					"route %s segment %d should clear %s by one player radius" % [route_name, point_index, String(solid.get("id", ""))]
				)

	var entries_by_id: Dictionary = {}
	for group_name in ["floors", "stairs", "ramps", "catwalks"]:
		for entry_variant in level_data.get(group_name, []):
			var entry: Dictionary = entry_variant as Dictionary
			entries_by_id[String(entry.get("id", ""))] = entry
	_assert_connected_x_edges(entries_by_id, "a-long-ramp", "x+", "a-ramp-landing", "x-", "A ramp should seat exactly against its landing")
	_assert_connected_x_edges(entries_by_id, "a-ramp-landing", "x+", "a-ramp-descent", "x-", "A landing should seat exactly against its descent")
	_assert_connected_x_edges(entries_by_id, "b-catwalk-access", "x+", "b-local-catwalk", "x-", "B stair should seat exactly against its local catwalk")

func _assert_connected_x_edges(entries: Dictionary, first_id: String, first_edge: String, second_id: String, second_edge: String, message: String) -> void:
	_assert_true(entries.has(first_id) and entries.has(second_id), "%s should reference existing geometry" % message)
	if not entries.has(first_id) or not entries.has(second_id):
		return
	_assert_true(is_equal_approx(_box_edge(entries[first_id] as Dictionary, first_edge), _box_edge(entries[second_id] as Dictionary, second_edge)), message)

func _segment_intersects_expanded_box(from_point: Array, to_point: Array, entry: Dictionary, margin: float) -> bool:
	if from_point.size() < 2 or to_point.size() < 2:
		return true
	var start := Vector2(float(from_point[0]), float(from_point[1]))
	var finish := Vector2(float(to_point[0]), float(to_point[1]))
	var minimum := Vector2(
		float(entry.get("x", 0.0)) - float(entry.get("sx", 0.0)) * 0.5 - margin,
		float(entry.get("z", 0.0)) - float(entry.get("sz", 0.0)) * 0.5 - margin
	)
	var maximum := Vector2(
		float(entry.get("x", 0.0)) + float(entry.get("sx", 0.0)) * 0.5 + margin,
		float(entry.get("z", 0.0)) + float(entry.get("sz", 0.0)) * 0.5 + margin
	)
	var lower := 0.0
	var upper := 1.0
	for axis in range(2):
		var delta := finish[axis] - start[axis]
		if absf(delta) < 0.000001:
			if start[axis] < minimum[axis] or start[axis] > maximum[axis]:
				return false
			continue
		var axis_lower := (minimum[axis] - start[axis]) / delta
		var axis_upper := (maximum[axis] - start[axis]) / delta
		if axis_lower > axis_upper:
			var swap := axis_lower
			axis_lower = axis_upper
			axis_upper = swap
		lower = maxf(lower, axis_lower)
		upper = minf(upper, axis_upper)
		if lower > upper:
			return false
	return true

func _test_visual_name_filters_hide_helpers_only() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	var visual_fixture := Node3D.new()
	var helper_mesh := MeshInstance3D.new()
	helper_mesh.name = "n0_cb_bl_mesh_blocklight_fixture"
	visual_fixture.add_child(helper_mesh)
	var authored_mesh := MeshInstance3D.new()
	authored_mesh.name = "dust_kasbah_wall_fixture"
	visual_fixture.add_child(authored_mesh)
	var imported_light := DirectionalLight3D.new()
	imported_light.name = "light_environment"
	visual_fixture.add_child(imported_light)

	level.call(
		"_hide_filtered_visual_meshes",
		visual_fixture,
		["_cb_bl_mesh_blocklight", "light_environment"]
	)
	_assert_true(not helper_mesh.visible, "visual filters should hide exported blocklight helper meshes")
	_assert_true(authored_mesh.visible, "visual filters should preserve authored map meshes")
	_assert_true(not imported_light.visible, "visual filters should disable exported environment lights")
	visual_fixture.free()
	await _cleanup_level(level)

func _test_missing_level_does_not_clobber_current_state() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	await get_tree().process_frame

	level.call("load_level", "depot")
	await get_tree().physics_frame
	await get_tree().process_frame
	var before_data: Dictionary = level.call("get_current_level_data")
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var before_children: int = geometry_root.get_child_count()
	var before_spawn: Vector3 = GameState.player_spawn
	var before_level_id: String = GameState.current_level_id

	level.call("load_level", "__missing_level_for_test__", false)
	await get_tree().physics_frame
	await get_tree().process_frame

	var after_data: Dictionary = level.call("get_current_level_data")
	_assert_equal(String(after_data.get("id", "")), String(before_data.get("id", "")), "missing level load should keep the previously loaded level data intact")
	_assert_equal(geometry_root.get_child_count(), before_children, "missing level load should not clear or append geometry")
	_assert_vec3_close(GameState.player_spawn, before_spawn, 0.001, "missing level load should preserve current player spawn")
	_assert_equal(String(GameState.current_level_id), before_level_id, "missing level load should preserve GameState level id")

	await _cleanup_level(level)
