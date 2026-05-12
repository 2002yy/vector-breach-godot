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
		+ (level_data.get("catwalks", []) as Array).size()

func _marker_start_position(level_data: Dictionary) -> Vector3:
	var start: Array = level_data.get("start", [0.0, 0.0]) as Array
	return Vector3(float(start[0]), 1.75, float(start[1]))

func _marker_exit_position(level_data: Dictionary) -> Vector3:
	var exit: Array = level_data.get("exit", [0.0, 0.0]) as Array
	return Vector3(float(exit[0]), 0.5, float(exit[1]))

func _test_default_load_applies_markers_and_geometry() -> void:
	var level: Node3D = _instantiate_level()
	await get_tree().physics_frame
	await get_tree().process_frame

	var level_data: Dictionary = LevelDataLoader.load_level("test-collision-room")
	var geometry_root: Node3D = level.get_node("GeometryRoot")
	var spawn_marker: Marker3D = level.get_node("SpawnMarker")
	var exit_marker: Marker3D = level.get_node("ExitMarker")

	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "test-collision-room", "graybox level should keep currently loaded level data")
	_assert_equal(geometry_root.get_child_count(), _expected_geometry_child_count(level_data), "geometry root should contain the expected built node count for default level")
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
	var first_children: int = geometry_root.get_child_count()
	level.call("load_level", "depot")
	await get_tree().physics_frame
	await get_tree().process_frame

	var depot_data: Dictionary = LevelDataLoader.load_level("depot")
	var spawn_marker: Marker3D = level.get_node("SpawnMarker")
	var exit_marker: Marker3D = level.get_node("ExitMarker")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "depot", "load_level should replace current level payload")
	_assert_equal(geometry_root.get_child_count(), _expected_geometry_child_count(depot_data), "geometry root should be rebuilt to the new level node count")
	_assert_true(geometry_root.get_child_count() != first_children, "switching to depot should change built geometry count from the default room")
	_assert_vec3_close(spawn_marker.position, _marker_start_position(depot_data), 0.001, "spawn marker should update when loading depot")
	_assert_vec3_close(exit_marker.position, _marker_exit_position(depot_data), 0.001, "exit marker should update when loading depot")
	_assert_equal(String(GameState.current_level_id), "depot", "GameState should switch to depot after load_level")

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
