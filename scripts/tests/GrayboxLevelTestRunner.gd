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
	await _run_test("depot_uses_cs_scale_metrics", _test_depot_uses_cs_scale_metrics)
	await _run_test("depot_stairs_align_with_target_edges", _test_depot_stairs_align_with_target_edges)
	await _run_test("depot_route_points_clear_player_collision", _test_depot_route_points_clear_player_collision)
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
	return 2 \
		+ (level_data.get("walls", []) as Array).size() \
		+ (level_data.get("covers", []) as Array).size() \
		+ (level_data.get("floors", []) as Array).size() \
		+ (level_data.get("stairs", []) as Array).size() \
		+ (level_data.get("ramps", []) as Array).size() \
		+ (level_data.get("catwalks", []) as Array).size() \
		+ (level_data.get("overheads", []) as Array).size()

func _marker_start_position(level_data: Dictionary) -> Vector3:
	var start: Array = level_data.get("start", [0.0, 0.0]) as Array
	return Vector3(float(start[0]), 1.05, float(start[1]))

func _marker_exit_position(level_data: Dictionary) -> Vector3:
	var exit: Array = level_data.get("exit", [0.0, 0.0]) as Array
	return Vector3(float(exit[0]), 0.5, float(exit[1]))

func _test_default_load_applies_markers_and_geometry() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	await get_tree().process_frame

	var level_data: Dictionary = LevelDataLoader.load_level("test-collision-room")
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var visual_root: Node3D = level.get_node("VisualRoot")
	var spawn_marker: Marker3D = level.get_node("SpawnMarker")
	var exit_marker: Marker3D = level.get_node("ExitMarker")

	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "test-collision-room", "graybox level should keep currently loaded level data")
	_assert_equal(geometry_root.get_child_count(), _expected_geometry_child_count(level_data), "geometry root should contain the expected built node count for default level")
	_assert_true(geometry_root.visible, "levels without a visual scene should keep graybox meshes visible")
	_assert_equal(visual_root.get_child_count(), 0, "levels without a visual scene should leave the visual root empty")
	_assert_vec3_close(spawn_marker.position, _marker_start_position(level_data), 0.001, "spawn marker should match level start coordinate")
	_assert_vec3_close(exit_marker.position, _marker_exit_position(level_data), 0.001, "exit marker should match level exit coordinate")
	_assert_vec3_close(GameState.player_spawn, spawn_marker.position, 0.001, "GameState spawn should mirror the spawn marker")
	_assert_equal(String(GameState.current_level_id), "test-collision-room", "GameState should track the loaded default level id")
	_assert_equal(String(GameState.current_level_name), String(level_data.get("name", "")), "GameState should track the loaded default level name")

	await _cleanup_level(level)

func _test_load_level_rebuilds_geometry_and_updates_state() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	await get_tree().process_frame

	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var visual_root: Node3D = level.get_node("VisualRoot")
	var lighting_root: Node3D = level.get_node("LightingRoot")
	var first_children: int = geometry_root.get_child_count()
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
	_assert_vec3_close(exit_marker.position, _marker_exit_position(depot_data), 0.001, "exit marker should update when loading depot")
	_assert_equal(String(GameState.current_level_id), "depot", "GameState should switch to depot after load_level")

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
