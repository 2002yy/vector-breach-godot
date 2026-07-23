extends Node3D

signal targets_spawned(count: int)
signal combatants_spawned(friendly_count: int, enemy_count: int)
signal ai_shot(result: Dictionary, world_position: Vector3)
signal ai_footstep(world_position: Vector3, surface: String, quiet: bool)

@export var dummy_scene: PackedScene
@export var use_spawn_points: bool = true
@export var use_landmarks: bool = true
@export var fallback_target_count: int = 3
@export var max_targets: int = 5
@export var dummy_height: float = 1.15
@export var fallback_spacing: float = 6.0

func load_for_level(level_data: Dictionary) -> void:
	_clear_targets()
	if dummy_scene == null:
		targets_spawned.emit(0)
		combatants_spawned.emit(0, 0)
		return
	var friendly_count := 0
	var enemy_count := 0
	var navigation_graph := _build_navigation_graph(level_data)
	for record_variant in _build_spawn_records(level_data):
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		var target_instance := dummy_scene.instantiate()
		if not target_instance is Node3D:
			continue
		var target_node := target_instance as Node3D
		target_node.position = Vector3(float(record.get("x", 0.0)), float(record.get("y", dummy_height)), float(record.get("z", 0.0)))
		add_child(target_node)
		if target_node.has_method("configure_from_record"):
			var route_name := String(record.get("route", ""))
			var routes: Dictionary = level_data.get("routes", {}) as Dictionary
			var ai_routes: Dictionary = level_data.get("aiRoutes", {}) as Dictionary
			record["routePoints"] = ai_routes.get(route_name, routes.get(route_name, []))
			record["navigationGraph"] = navigation_graph
			target_node.call("configure_from_record", record)
		if target_node.has_signal("ai_shot"):
			target_node.connect("ai_shot", _on_actor_ai_shot)
		if target_node.has_signal("ai_footstep"):
			target_node.connect("ai_footstep", _on_actor_ai_footstep)
		var resolved_team := String(target_node.get("team"))
		if resolved_team == GameState.player_team:
			friendly_count += 1
		else:
			enemy_count += 1
	targets_spawned.emit(enemy_count)
	combatants_spawned.emit(friendly_count, enemy_count)

func _clear_targets() -> void:
	for child in get_children():
		child.queue_free()

func notify_ai_sound(world_position: Vector3, audible_radius: float, source_team: String) -> int:
	var notified := 0
	for child in get_children():
		if child.has_method("notify_ai_sound") and bool(child.call("notify_ai_sound", world_position, audible_radius, source_team)):
			notified += 1
	return notified

func _on_actor_ai_shot(result: Dictionary, world_position: Vector3) -> void:
	ai_shot.emit(result, world_position)
	notify_ai_sound(world_position, 52.0, String((result.get("shooter_team", ""))))

func _on_actor_ai_footstep(world_position: Vector3, surface: String, quiet: bool) -> void:
	ai_footstep.emit(world_position, surface, quiet)

func _build_navigation_graph(level_data: Dictionary) -> Dictionary:
	var points: Array = []
	var links: Array = []
	var point_indices: Dictionary = {}
	var link_keys: Dictionary = {}
	var route_sources: Array[Dictionary] = []
	var routes := level_data.get("routes", {}) as Dictionary
	var ai_routes := level_data.get("aiRoutes", {}) as Dictionary
	route_sources.append(routes)
	route_sources.append(ai_routes)
	for source in route_sources:
		for route_variant in source.values():
			if not route_variant is Array:
				continue
			var route := route_variant as Array
			if route.is_empty() or not route[0] is Array:
				continue
			var previous_index := -1
			for point_variant in route:
				if not point_variant is Array:
					continue
				var point_array := point_variant as Array
				if point_array.size() < 2:
					continue
				var point := Vector3(
					float(point_array[0]),
					float(point_array[1]) if point_array.size() >= 3 else dummy_height,
					float(point_array[2]) if point_array.size() >= 3 else float(point_array[1])
				)
				var point_key := "%d|%d|%d" % [
					roundi(point.x * 4.0),
					roundi(point.y * 4.0),
					roundi(point.z * 4.0),
				]
				var point_index: int
				if point_indices.has(point_key):
					point_index = int(point_indices[point_key])
				else:
					point_index = points.size()
					point_indices[point_key] = point_index
					points.append([point.x, point.y, point.z])
				if previous_index >= 0 and previous_index != point_index:
					var low := mini(previous_index, point_index)
					var high := maxi(previous_index, point_index)
					var link_key := "%d|%d" % [low, high]
					if not link_keys.has(link_key):
						link_keys[link_key] = true
						links.append([low, high])
				previous_index = point_index
	return {"points": points, "links": links}

func _build_spawn_records(level_data: Dictionary) -> Array:
	var records: Array = []
	var team_actors: Array = level_data.get("teamActors", []) as Array
	for actor_variant in team_actors:
		if actor_variant is Dictionary:
			var actor_record := (actor_variant as Dictionary).duplicate(true)
			if not actor_record.has("aiEnabled"):
				actor_record["aiEnabled"] = false
			records.append(actor_record)
	var combat_targets: Array = level_data.get("combatTargets", []) as Array
	for index in range(mini(max_targets, combat_targets.size())):
		var target_variant: Variant = combat_targets[index]
		if not target_variant is Dictionary:
			continue
		var target := target_variant as Dictionary
		records.append({
			"name": String(target.get("name", "敌方单位%d" % (index + 1))),
			"x": float(target.get("x", 0.0)), "y": float(target.get("y", dummy_height)), "z": float(target.get("z", 0.0)),
			"armor": int(target.get("armor", 0)), "helmet": bool(target.get("helmet", false)),
			"team": String(target.get("team", "enemy")), "weapon": String(target.get("weapon", "rifle")),
			"route": String(target.get("route", "")), "aiEnabled": bool(target.get("aiEnabled", true)),
			"aiReactionTime": float(target.get("aiReactionTime", 0.34)),
		})
	if not combat_targets.is_empty():
		return records
	if use_spawn_points:
		var spawn_points: Array = level_data.get("spawnPoints", []) as Array
		for index in range(mini(max_targets, spawn_points.size())):
			var point_variant: Variant = spawn_points[index]
			if point_variant is Dictionary:
				var point := point_variant as Dictionary
				records.append({"name": "敌方单位%d" % (index + 1), "x": float(point.get("x", 0.0)), "y": float(point.get("y", dummy_height)), "z": float(point.get("z", 0.0)), "team": "enemy"})
	if records.size() > team_actors.size():
		return records
	if use_landmarks:
		var landmarks: Array = level_data.get("landmarks", []) as Array
		for index in range(mini(max_targets, landmarks.size())):
			var landmark_variant: Variant = landmarks[index]
			if landmark_variant is Dictionary:
				var landmark := landmark_variant as Dictionary
				records.append({"name": "敌方单位%d" % (index + 1), "x": float(landmark.get("x", 0.0)), "y": float(landmark.get("y", dummy_height)), "z": float(landmark.get("z", 0.0)), "team": "enemy"})
	if records.size() > team_actors.size():
		return records
	var exit_record: Array = level_data.get("exit", [0.0, 0.0]) as Array
	var base_x := float(exit_record[0]) if exit_record.size() >= 2 else 0.0
	var base_z := float(exit_record[1]) if exit_record.size() >= 2 else 0.0
	for index in range(fallback_target_count):
		records.append({"name": "敌方单位%d" % (index + 1), "x": base_x - fallback_spacing * float(index), "y": dummy_height, "z": base_z, "team": "enemy"})
	return records
