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
	_run_test("optional_local_dustline_keeps_reference_boundary", _test_dustline_locks_reference_and_single_difference_layer)
	_run_test("foundry_depot_v2_freeze_manifest_matches", _test_foundry_depot_v2_freeze_manifest_matches)
	_run_test("foundry_reforged_prioritizes_three_ground_routes", _test_foundry_reforged_prioritizes_three_ground_routes)
	_run_test("gatehouse_core_vault_author_tactical_routes", _test_gatehouse_core_vault_author_tactical_routes)

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

func _test_dustline_locks_reference_and_single_difference_layer() -> void:
	if not FileAccess.file_exists("res://data/levels/dustline-depths.json"):
		return
	var level_data: Dictionary = LevelDataLoader.load_level("dustline-depths")
	var source_trace: Dictionary = level_data.get("sourceTrace", {}) as Dictionary
	var difference: Dictionary = level_data.get("differenceLayer", {}) as Dictionary
	var routes: Dictionary = level_data.get("routes", {}) as Dictionary
	var build_options: Dictionary = level_data.get("buildOptions", {}) as Dictionary

	_assert_equal(String(source_trace.get("referenceMap", "")), "de_dust2", "dustline should retain its reference map identity")
	_assert_equal(String(source_trace.get("manifest", "")), "118363704811264052", "dustline should retain the exact reference manifest")
	_assert_equal(String(source_trace.get("vpkSha256", "")).length(), 64, "dustline should retain a full SHA-256 reference hash")
	_assert_true(not bool(source_trace.get("referenceAssetsCommitted", true)), "raw reference assets should stay outside the repository")
	_assert_true(bool(level_data.get("runtime_collision_from_visual", false)), "dustline should opt into imported runtime collision")
	_assert_true(not bool(build_options.get("arena_floor_enabled", true)), "dustline should not cover the reference terrain with a generated arena floor")
	_assert_true(not bool(build_options.get("arena_bounds_enabled", true)), "dustline should not add generated bounds over the reference layout")
	var authored_start: Array = level_data.get("start", []) as Array
	for route_name in ["longA", "shortA", "tunnelsB", "midB"]:
		var route_points: Array = routes.get(route_name, []) as Array
		_assert_true(route_points.size() >= 5, "dustline route %s should retain enough ground-layer anchors" % route_name)
		if not route_points.is_empty():
			_assert_equal(route_points[0], authored_start, "dustline route %s should begin at the actual authored spawn" % route_name)
	_assert_equal(int(difference.get("count", 0)), 1, "dustline should add exactly one difference route")
	_assert_equal(int(difference.get("groundLayerCuts", -1)), 0, "the difference route should not cut the original ground layer")
	_assert_true(bool(difference.get("usesExistingElevatedAccess", false)), "the optional high route should reuse Dust2's existing elevated access")
	_assert_true(float(difference.get("accessStepHeight", 1.0)) <= 0.2, "dustline skywalk access should stay within one walkable step")
	_assert_true(float(difference.get("minimumUnderpassClearance", 0.0)) >= 2.4, "dustline skywalk should preserve standing combat below")
	_assert_equal((difference.get("collisionParts", []) as Array).size(), 3, "dustline skywalk should limit collision to its deck and two rails")

func _test_foundry_depot_v2_freeze_manifest_matches() -> void:
	var manifest_path := "res://docs/map-data/foundry-depot-v2-freeze.json"
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	_assert_true(manifest_file != null, "Foundry Depot v2 should keep a machine-readable freeze manifest")
	if manifest_file == null:
		return
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	_assert_true(parsed is Dictionary, "Foundry Depot v2 freeze manifest should parse as a dictionary")
	if not (parsed is Dictionary):
		return
	var manifest: Dictionary = parsed as Dictionary
	_assert_equal(String(manifest.get("status", "")), "frozen", "Foundry Depot v2 should remain frozen")
	_assert_equal(String(manifest.get("successor", "")), "foundry-reforged", "freeze manifest should point layout work at Foundry Reforged")
	for entry_variant in manifest.get("files", []):
		var entry: Dictionary = entry_variant as Dictionary
		var path := String(entry.get("path", ""))
		_assert_true(FileAccess.file_exists(path), "frozen Foundry file should exist: %s" % path)
		if not FileAccess.file_exists(path):
			continue
		var frozen_file := FileAccess.open(path, FileAccess.READ)
		_assert_equal(frozen_file.get_length(), int(entry.get("bytes", -1)), "frozen Foundry file size should match: %s" % path)
		_assert_equal(FileAccess.get_sha256(path).to_upper(), String(entry.get("sha256", "")).to_upper(), "frozen Foundry hash should match: %s" % path)

func _test_foundry_reforged_prioritizes_three_ground_routes() -> void:
	var level_data: Dictionary = LevelDataLoader.load_level("foundry-reforged")
	var intent: Dictionary = level_data.get("designIntent", {}) as Dictionary
	var routes: Dictionary = level_data.get("routes", {}) as Dictionary
	var objectives: Array = level_data.get("objectives", []) as Array
	var catwalks: Array = level_data.get("catwalks", []) as Array
	var drops: Array = level_data.get("drops", []) as Array
	var ramps: Array = level_data.get("ramps", []) as Array
	var doorways: Array = level_data.get("doorways", []) as Array
	var low_areas: Array = level_data.get("relativeLowAreas", []) as Array
	var combat_lanes: Array = level_data.get("combatLanes", []) as Array
	var contact_audits: Array = level_data.get("contactAudits", []) as Array
	var combat_targets: Array = level_data.get("combatTargets", []) as Array
	var metrics: Dictionary = level_data.get("metrics", {}) as Dictionary
	var timing_targets: Dictionary = level_data.get("timingTargets", {}) as Dictionary
	var timing_measurements: Dictionary = level_data.get("timingMeasurements", {}) as Dictionary
	var environment: Dictionary = level_data.get("environment", {}) as Dictionary
	var sprint_speed := float(metrics.get("sprintSpeedMetersPerSecond", 0.0))

	_assert_equal(String(level_data.get("predecessor", "")), "depot", "Foundry Reforged should retain an explicit predecessor trace")
	_assert_equal(String(level_data.get("designRevision", "")), "reforged-ground-combat-v0.2", "Foundry Reforged should expose the current ground-combat revision")
	_assert_equal(String(level_data.get("visual_scene", "")), "res://assets/models/foundry/foundry_reforged.glb", "Foundry Reforged should use its own industrial visual")
	_assert_true(String(level_data.get("visual_scene", "")) != "res://assets/models/foundry/foundry_depot.glb", "Foundry Reforged must not reuse the frozen Depot visual")
	_assert_equal(String(environment.get("sky_panorama", "")), "res://assets/environment/overcast_soil_puresky_1k.hdr", "Foundry Reforged should use the architecture-free CC0 sky")
	_assert_true(FileAccess.file_exists(String(environment.get("sky_panorama", ""))), "Foundry Reforged pure-sky panorama should exist in the project")
	_assert_true(String(environment.get("sky_mode", "")).is_empty(), "Foundry Reforged should reserve PhysicalSky for fallback instead of the shipped sky")
	_assert_true(bool(environment.get("sun_shadow_enabled", false)), "Foundry Reforged should retain one shadowed directional key light")
	_assert_true(float(environment.get("fog_density", 1.0)) <= 0.0015, "Foundry Reforged should keep only enough fog to blend the distant skyline")
	_assert_true(not bool(environment.get("volumetric_fog_enabled", false)), "Foundry Reforged should not require volumetric fog")
	_assert_true(bool(intent.get("groundLayerPriority", false)), "Foundry Reforged should prioritize the ground combat layer")
	_assert_equal(int(intent.get("groundRouteCount", 0)), 3, "Foundry Reforged should commit to three primary ground routes")
	_assert_true(not bool(intent.get("continuousUpperLoop", true)), "Foundry Reforged should not recreate a continuous upper map")
	for route_name in ["aLong", "mid", "bServiceDock", "bServiceControl"]:
		_assert_true((routes.get(route_name, []) as Array).size() >= 6, "Foundry Reforged route %s should retain six or more timing anchors" % route_name)
	_assert_equal(objectives.size(), 2, "Foundry Reforged should expose two readable objectives")
	for objective_variant in objectives:
		var objective: Dictionary = objective_variant as Dictionary
		_assert_true((objective.get("approaches", []) as Array).size() >= 2, "objective %s should keep at least two attack approaches" % String(objective.get("id", "")))
		_assert_equal(String(objective.get("defenderRotation", "")), "defenderRotation", "each objective should reference the authored defender rotation")
	_assert_equal(catwalks.size(), 1, "Foundry Reforged should contain one localized high-route catwalk")
	_assert_equal(drops.size(), 1, "Foundry Reforged high route should have one authored drop into the ground objective")
	_assert_equal(ramps.size(), 1, "Foundry Reforged A long should contain one measured ground ramp")
	_assert_true(doorways.size() >= 8, "Foundry Reforged should expose attack and defender rotation doorways")
	_assert_equal(low_areas.size(), 1, "Foundry Reforged should contain one relative low pit instead of another upper layer")
	_assert_equal(combat_targets.size(), 5, "Foundry Reforged should author combat targets separately from route spawn markers")
	_assert_true(not String(timing_targets.get("measurementStatus", "")).contains("pending"), "Foundry Reforged timing measurements should not remain pending")
	_assert_true(bool(timing_measurements.get("allSweepsClear", false)), "Foundry Reforged should record a clear player-collider sweep")
	if catwalks.size() == 1:
		var catwalk: Dictionary = catwalks[0] as Dictionary
		_assert_equal(String(catwalk.get("id", "")), "b-local-catwalk", "the single high route should stay localized at B")
		_assert_true(float(catwalk.get("h", 0.0)) <= 3.2, "the B catwalk should keep modest combat elevation")
	_assert_true(sprint_speed > 0.0, "Foundry Reforged timing audits require a positive sprint speed")
	if sprint_speed <= 0.0:
		return

	var known_interrupters: Dictionary = {}
	for group_name in ["walls", "covers"]:
		for entry_variant in level_data.get(group_name, []):
			var entry: Dictionary = entry_variant as Dictionary
			known_interrupters[String(entry.get("id", ""))] = true
	for lane_variant in combat_lanes:
		var lane: Dictionary = lane_variant as Dictionary
		var target_range: Array = lane.get("targetRangeMeters", []) as Array
		_assert_equal(target_range.size(), 2, "combat lane %s should define a min/max distance" % String(lane.get("id", "")))
		for interrupter_variant in lane.get("interrupters", []):
			var interrupter := String(interrupter_variant)
			_assert_true(known_interrupters.has(interrupter), "combat lane %s should reference existing interrupter %s" % [String(lane.get("id", "")), interrupter])
		if lane.has("distanceMeters") and target_range.size() == 2:
			var distance := float(lane.get("distanceMeters", 0.0))
			_assert_true(distance >= float(target_range[0]) and distance <= float(target_range[1]), "combat lane %s should stay inside its authored distance range" % String(lane.get("id", "")))

	for route_name in ["bServiceDock", "bServiceControl"]:
		var points: Array = routes.get(route_name, []) as Array
		for point_index in range(points.size() - 1):
			var segment_length := _route_point_distance(points[point_index] as Array, points[point_index + 1] as Array)
			_assert_true(segment_length >= 8.0 and segment_length <= 20.0, "B service segment %s[%d] should preserve an 8-20 meter clearing beat" % [route_name, point_index])

	var contact_target: Array = timing_targets.get("attackerFirstContactSeconds", []) as Array
	_assert_equal(contact_target.size(), 2, "Foundry Reforged should define first-contact timing bounds")
	for audit_variant in contact_audits:
		var audit: Dictionary = audit_variant as Dictionary
		var route_name := String(audit.get("route", ""))
		var route_points: Array = routes.get(route_name, []) as Array
		var point_index := int(audit.get("pointIndex", -1))
		_assert_true(point_index > 0 and point_index < route_points.size(), "contact audit %s should reference a valid route point" % String(audit.get("id", "")))
		if point_index <= 0 or point_index >= route_points.size() or contact_target.size() != 2:
			continue
		var contact_seconds := _route_length(route_points, point_index) / sprint_speed
		_assert_true(contact_seconds >= float(contact_target[0]) and contact_seconds <= float(contact_target[1]), "contact audit %s should land inside the target timing window" % String(audit.get("id", "")))

	var rotation_target: Array = timing_targets.get("siteToSiteRotationSeconds", []) as Array
	var rotation_points: Array = routes.get("defenderRotation", []) as Array
	_assert_equal(rotation_target.size(), 2, "Foundry Reforged should define site rotation timing bounds")
	if rotation_target.size() == 2:
		var rotation_seconds := _route_length(rotation_points) / sprint_speed
		_assert_true(rotation_seconds >= float(rotation_target[0]) and rotation_seconds <= float(rotation_target[1]), "defender site rotation should stay inside the 12-18 second target")
		var measured_rotation := float(timing_measurements.get("siteToSiteRotationSeconds", 0.0))
		_assert_true(measured_rotation >= float(rotation_target[0]) and measured_rotation <= float(rotation_target[1]), "measured defender rotation should stay inside the 12-18 second target")

	if contact_target.size() == 2:
		for measurement_name in ["aFirstContactSeconds", "midFirstContactSeconds", "bFirstContactSeconds"]:
			var measured_contact := float(timing_measurements.get(measurement_name, 0.0))
			_assert_true(measured_contact >= float(contact_target[0]) and measured_contact <= float(contact_target[1]), "measured %s should stay inside the first-contact target" % measurement_name)

func _test_gatehouse_core_vault_author_tactical_routes() -> void:
	for level_id in ["gatehouse", "core-vault"]:
		var level_data := LevelDataLoader.load_level(level_id)
		var routes: Dictionary = level_data.get("routes", {}) as Dictionary
		var profiles: Dictionary = level_data.get("aiRouteProfiles", {}) as Dictionary
		var spawn_groups: Dictionary = level_data.get("spawnGroups", {}) as Dictionary
		var spawn_points: Array = level_data.get("spawnPoints", []) as Array
		var objectives: Array = level_data.get("objectives", []) as Array
		var combat_targets: Array = level_data.get("combatTargets", []) as Array
		var landmarks: Array = level_data.get("landmarks", []) as Array
		_assert_true(String(level_data.get("gameplayRevision", "")).ends_with("tactical-routes-v1"), "%s should expose its tactical gameplay revision" % level_id)
		for route_name in ["attackerSpawn", "defenderSpawn", "siteA", "siteB", "defenderRotation"]:
			_assert_true(routes.has(route_name), "%s should author required route %s" % [level_id, route_name])
		_assert_true(profiles.size() >= 5, "%s should attach traversal profiles to its main route graph" % level_id)
		_assert_equal((spawn_groups.get("T", []) as Array).size(), 3, "%s should author three T spawn slots" % level_id)
		_assert_equal((spawn_groups.get("CT", []) as Array).size(), 3, "%s should author three CT spawn slots" % level_id)
		_assert_equal(spawn_points.size(), 6, "%s should expose both spawn groups to shared map systems" % level_id)
		_assert_equal(objectives.size(), 2, "%s should expose two bomb target areas" % level_id)
		for objective_variant in objectives:
			var objective := objective_variant as Dictionary
			var approaches: Array = objective.get("approaches", []) as Array
			_assert_true(approaches.size() >= 2, "%s objective %s should have two attack approaches" % [level_id, String(objective.get("id", ""))])
			for approach_variant in approaches:
				_assert_true(routes.has(String(approach_variant)), "%s objective approach should reference a known route" % level_id)
			_assert_true(routes.has(String(objective.get("defenderRotation", ""))), "%s objective should reference a known defender rotation" % level_id)
		_assert_equal(combat_targets.size(), 3, "%s should spawn a three-bot defending group" % level_id)
		for target_variant in combat_targets:
			var target := target_variant as Dictionary
			_assert_true(bool(target.get("aiEnabled", false)), "%s combat target should enable its bot brain" % level_id)
			_assert_true(routes.has(String(target.get("route", ""))), "%s combat target should reference a known route" % level_id)
			_assert_true(bool(target.get("helmet", false)) and int(target.get("armor", 0)) == 100, "%s defending bots should use full armor for repeatable combat tests" % level_id)
		_assert_true(landmarks.size() >= 6, "%s should provide route callout anchors" % level_id)

func _route_point_distance(a: Array, b: Array) -> float:
	if a.size() < 2 or b.size() < 2:
		return 0.0
	return Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))

func _route_length(points: Array, end_index: int = -1) -> float:
	var limit := points.size() - 1 if end_index < 0 else mini(end_index, points.size() - 1)
	var total := 0.0
	for point_index in range(limit):
		total += _route_point_distance(points[point_index] as Array, points[point_index + 1] as Array)
	return total

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
