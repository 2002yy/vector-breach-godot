extends Node

const LevelDataLoader = preload("res://scripts/level/LevelDataLoader.gd")

const LEVELS_DIR := "res://data/levels"

var _failures: PackedStringArray = []
var _passes: int = 0
var _temp_level_paths: PackedStringArray = []

func _ready() -> void:
	_run_all_tests()
	_cleanup_temp_levels()
	if _failures.is_empty():
		print("[LevelDataLoaderTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return

	push_error("[LevelDataLoaderTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_all_tests() -> void:
	_run_test("missing_level_returns_empty", _test_missing_level_returns_empty)
	_run_test("invalid_json_returns_empty", _test_invalid_json_returns_empty)
	_run_test("non_dictionary_json_returns_empty", _test_non_dictionary_json_returns_empty)
	_run_test("all_shipped_levels_have_required_shape", _test_all_shipped_levels_have_required_shape)
	_run_test("obstacles_reference_known_semantic_ids", _test_obstacles_reference_known_semantic_ids)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before: int = _failures.size()
	callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[LevelDataLoaderTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _test_missing_level_returns_empty() -> void:
	var level_data: Dictionary = LevelDataLoader.load_level("__missing_level_for_test__", false)
	_assert_true(level_data.is_empty(), "missing level id should resolve to empty dictionary")

func _test_invalid_json_returns_empty() -> void:
	var temp_level_id: String = "_temp_invalid_json_level"
	_write_temp_level(temp_level_id, "{\"id\": ")
	var level_data: Dictionary = LevelDataLoader.load_level(temp_level_id, false)
	_assert_true(level_data.is_empty(), "invalid JSON payload should resolve to empty dictionary")

func _test_non_dictionary_json_returns_empty() -> void:
	var temp_level_id: String = "_temp_array_level"
	_write_temp_level(temp_level_id, "[1, 2, 3]")
	var level_data: Dictionary = LevelDataLoader.load_level(temp_level_id, false)
	_assert_true(level_data.is_empty(), "non-dictionary JSON payload should resolve to empty dictionary")

func _test_all_shipped_levels_have_required_shape() -> void:
	for level_id in _list_level_ids():
		var level_data: Dictionary = LevelDataLoader.load_level(level_id)
		_assert_true(not level_data.is_empty(), "level should load: %s" % level_id)
		_assert_equal(String(level_data.get("id", "")), level_id, "level id should match filename for %s" % level_id)
		_assert_true(_is_vec2_array(level_data.get("start", [])), "level start should be a 2D coordinate pair for %s" % level_id)
		_assert_true(_is_vec2_array(level_data.get("exit", [])), "level exit should be a 2D coordinate pair for %s" % level_id)
		_assert_true(level_data.get("obstacles", []) is Array, "level obstacles should be an array for %s" % level_id)
		for semantic_key in ["walls", "covers", "floors", "stairs", "ramps", "catwalks", "overheads"]:
			_assert_true(level_data.get(semantic_key, []) is Array, "level %s should expose array key %s" % [level_id, semantic_key])

func _test_obstacles_reference_known_semantic_ids() -> void:
	for level_id in _list_level_ids():
		var level_data: Dictionary = LevelDataLoader.load_level(level_id)
		var known_ids: Dictionary = {}
		for semantic_key in ["walls", "covers", "floors", "stairs", "ramps", "catwalks", "overheads"]:
			for entry_variant in level_data.get(semantic_key, []):
				if typeof(entry_variant) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = entry_variant as Dictionary
				var entry_id: String = String(entry.get("id", ""))
				if not entry_id.is_empty():
					known_ids[entry_id] = true

		for obstacle_variant in level_data.get("obstacles", []):
			_assert_true(typeof(obstacle_variant) == TYPE_DICTIONARY, "obstacle entries should stay dictionaries for %s" % level_id)
			if typeof(obstacle_variant) != TYPE_DICTIONARY:
				continue
			var obstacle: Dictionary = obstacle_variant as Dictionary
			for numeric_key in ["x", "z", "sx", "sz", "h"]:
				_assert_true(_is_number(obstacle.get(numeric_key, null)), "obstacle %s should keep numeric key %s for %s" % [str(obstacle.get("id", obstacle.get("sourceId", ""))), numeric_key, level_id])
			var source_id: String = String(obstacle.get("sourceId", ""))
			if not source_id.is_empty():
				_assert_true(known_ids.has(source_id), "obstacle sourceId should point to a semantic entry for %s: %s" % [level_id, source_id])

func _list_level_ids() -> PackedStringArray:
	var level_ids: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(LEVELS_DIR)
	if dir == null:
		_failures.append("unable to open level directory: %s" % LEVELS_DIR)
		return level_ids

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if file_name.ends_with(".json"):
			if file_name.begins_with("_temp_"):
				continue
			level_ids.append(file_name.trim_suffix(".json"))
	dir.list_dir_end()
	level_ids.sort()
	return level_ids

func _is_vec2_array(value: Variant) -> bool:
	if not (value is Array):
		return false
	var array_value: Array = value as Array
	if array_value.size() != 2:
		return false
	return _is_number(array_value[0]) and _is_number(array_value[1])

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _write_temp_level(level_id: String, json_text: String) -> void:
	var res_path: String = "%s/%s.json" % [LEVELS_DIR, level_id]
	var absolute_path: String = ProjectSettings.globalize_path(res_path)
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_failures.append("unable to create temp level file: %s" % absolute_path)
		return
	file.store_string(json_text)
	file.flush()
	_temp_level_paths.append(res_path)

func _cleanup_temp_levels() -> void:
	for res_path in _temp_level_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(res_path))
