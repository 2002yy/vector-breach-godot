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

var c4_device: Node3D
var _current_level_data: Dictionary = {}
var _bomb_carrier_actor: CharacterBody3D
var _loaded_level_id: String = ""
var _saved_round_loadouts: Dictionary = {}

func _ready() -> void:
	if not RoundManager.round_ended.is_connected(_on_round_ended_capture):
		RoundManager.round_ended.connect(_on_round_ended_capture)

func load_for_level(level_data: Dictionary) -> void:
	_clear_targets()
	var level_id := String(level_data.get("id", ""))
	if _loaded_level_id != level_id:
		_loaded_level_id = level_id
		_saved_round_loadouts.clear()
	_current_level_data = level_data
	_bomb_carrier_actor = null
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
		var saved_loadout: Dictionary = _saved_round_loadouts.get(String(record.get("name", "")), {})
		if not saved_loadout.is_empty():
			record["weapon"] = saved_loadout.get("weapon", record.get("weapon", "rifle"))
			record["weaponAmmoMag"] = saved_loadout.get("ammo_in_mag", 30)
			record["weaponAmmoReserve"] = saved_loadout.get("ammo_reserve", 0)
			record["armor"] = saved_loadout.get("armor", 0)
			record["defuseKit"] = saved_loadout.get("defuse_kit", false)
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
		if target_node.has_signal("ai_spot"):
			target_node.connect("ai_spot", _on_actor_ai_spot.bind(target_node))
		if target_node.has_signal("ai_damaged"):
			target_node.connect("ai_damaged", _on_actor_ai_damaged.bind(target_node))
		if target_node.has_signal("actor_killed"):
			target_node.connect("actor_killed", _on_actor_killed.bind(target_node))
		if c4_device != null and target_node.has_method("set_ai_c4_device"):
			target_node.call("set_ai_c4_device", c4_device)
		var resolved_team := String(target_node.get("team"))
		if resolved_team == GameState.player_team:
			friendly_count += 1
		else:
			enemy_count += 1
	targets_spawned.emit(enemy_count)
	combatants_spawned.emit(friendly_count, enemy_count)
	_assign_bomb_roles(level_data)
	_sync_team_economy()

func set_c4_device(device: Node3D) -> void:
	c4_device = device
	for child in get_children():
		if child.has_method("set_ai_c4_device"):
			child.call("set_ai_c4_device", device)

func _clear_targets() -> void:
	for child in get_children():
		child.queue_free()

func _assign_bomb_roles(level_data: Dictionary) -> void:
	_bomb_carrier_actor = null
	var t_actors: Array[CharacterBody3D] = []
	var ct_actors: Array[CharacterBody3D] = []
	for child in get_children():
		if child is CharacterBody3D:
			var team := String((child as CharacterBody3D).get("team"))
			if team == "T":
				t_actors.append(child as CharacterBody3D)
			elif team == "CT":
				ct_actors.append(child as CharacterBody3D)
	var objectives: Array = level_data.get("objectives", []) as Array
	var primary_objective := objectives[0] as Dictionary if not objectives.is_empty() else {"id": "site-a", "x": 0.0, "z": 0.0}
	var secondary_objective := objectives[1] as Dictionary if objectives.size() > 1 else primary_objective
	var primary_target := Vector3(float(primary_objective.get("x", 0.0)), 1.15, float(primary_objective.get("z", 0.0)))
	var primary_site := "A" if String(primary_objective.get("id", "")).to_lower().contains("a") else "B"
	var secondary_target := Vector3(float(secondary_objective.get("x", 0.0)), 1.15, float(secondary_objective.get("z", 0.0)))
	var secondary_site := "A" if String(secondary_objective.get("id", "")).to_lower().contains("a") else "B"
	var t_carrier_enabled := GameState.player_team != "T" and not t_actors.is_empty()
	for index in range(t_actors.size()):
		var actor := t_actors[index]
		var role := "plant" if index == 0 else ("support" if index == 1 else "diversion")
		var objective := primary_objective if index < 2 else secondary_objective
		var site_target := Vector3(float(objective.get("x", 0.0)), 1.15, float(objective.get("z", 0.0)))
		var site_label := "A" if String(objective.get("id", "")).to_lower().contains("a") else "B"
		if actor.has_node("TacticalBotBrain"):
			actor.get_node("TacticalBotBrain").call(
				"configure_objective",
				role,
				site_target,
				site_label,
				t_carrier_enabled and index == 0
			)
		if t_carrier_enabled and index == 0:
			_bomb_carrier_actor = actor
	if c4_device != null and is_instance_valid(c4_device):
		c4_device.call("set_carried", "T")
	for index in range(ct_actors.size()):
		var actor := ct_actors[index]
		var objective_index := index % maxi(1, objectives.size())
		var objective := objectives[objective_index] as Dictionary if not objectives.is_empty() else primary_objective
		var site_target := Vector3(float(objective.get("x", 0.0)), 1.15, float(objective.get("z", 0.0)))
		var site_label := "A" if String(objective.get("id", "")).to_lower().contains("a") else "B"
		if actor.has_node("TacticalBotBrain"):
			actor.get_node("TacticalBotBrain").call("configure_objective", "defend_site", site_target, site_label)
		if index == 0:
			actor.set("has_defuse_kit", true)
			if actor.has_method("set_ai_defuse_kit"):
				actor.call("set_ai_defuse_kit", true)

func _sync_team_economy() -> void:
	var team_money_totals := {"T": 0, "CT": 0}
	for child in get_children():
		if child is CharacterBody3D and (child as CharacterBody3D).has_node("TacticalBotBrain"):
			var team := String((child as CharacterBody3D).get("team"))
			if team in team_money_totals:
				team_money_totals[team] = int(team_money_totals[team]) + int((child as CharacterBody3D).get_node("TacticalBotBrain").get("ai_money"))
	for child in get_children():
		if child is CharacterBody3D and (child as CharacterBody3D).has_node("TacticalBotBrain"):
			var team := String((child as CharacterBody3D).get("team"))
			var loss_streak := GameState.loss_streak if team == GameState.player_team else 0
			(child as CharacterBody3D).get_node("TacticalBotBrain").call(
				"set_team_economy",
				int(team_money_totals.get(team, 0)),
				loss_streak
			)

func _on_round_ended_capture(_winner: String, _reason: String) -> void:
	for child in get_children():
		if child is CharacterBody3D and not bool((child as CharacterBody3D).get("is_dead")):
			var snapshot := (child as CharacterBody3D).call("get_combat_snapshot") as Dictionary
			var ai := snapshot.get("ai", {}) as Dictionary
			_saved_round_loadouts[String(snapshot.get("name", ""))] = {
				"weapon": String(snapshot.get("weapon", "rifle")),
				"ammo_in_mag": int(ai.get("ammo", 30)),
				"ammo_reserve": int(ai.get("ammo_reserve", 0)),
				"armor": int(snapshot.get("armor", 0)),
				"defuse_kit": bool(snapshot.get("defuse_kit", false)),
			}

func _on_actor_killed(_actor_name: String, _team: String, actor: CharacterBody3D) -> void:
	if actor != _bomb_carrier_actor:
		return
	if c4_device != null and is_instance_valid(c4_device) and String(c4_device.get("device_state")) == "carried":
		c4_device.call("drop_at", actor.global_position)
	RoundManager.bomb_carried = false
	_bomb_carrier_actor = null

func _on_actor_ai_spot(world_position: Vector3, enemy_team: String, spotter: CharacterBody3D) -> void:
	_broadcast_teammate_report(world_position, enemy_team, String(spotter.get("team")), spotter)

func _on_actor_ai_damaged(world_position: Vector3, source_team: String, damaged_actor: CharacterBody3D) -> void:
	_broadcast_teammate_report(world_position, source_team, String(damaged_actor.get("team")), damaged_actor)

func _broadcast_teammate_report(world_position: Vector3, enemy_team: String, friendly_team: String, exclude_actor: CharacterBody3D) -> void:
	if enemy_team.is_empty() or friendly_team.is_empty():
		return
	var nearest_bot: Node = null
	var nearest_distance := INF
	for child in get_children():
		if child is CharacterBody3D and (child as CharacterBody3D) != exclude_actor and String((child as CharacterBody3D).get("team")) == friendly_team:
			var distance := (child as CharacterBody3D).global_position.distance_squared_to(world_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_bot = child as Node
	if nearest_bot != null and nearest_bot.has_method("notify_ai_teammate_report"):
		nearest_bot.call("notify_ai_teammate_report", world_position, enemy_team)

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
	var route_profiles: Dictionary = level_data.get("aiRouteProfiles", {}) as Dictionary
	var route_sources: Array[Dictionary] = []
	var routes := level_data.get("routes", {}) as Dictionary
	var ai_routes := level_data.get("aiRoutes", {}) as Dictionary
	route_sources.append(routes)
	route_sources.append(ai_routes)
	for source in route_sources:
		for route_name_variant in source.keys():
			var route_name := String(route_name_variant)
			var route_variant: Variant = source.get(route_name, [])
			if not route_variant is Array:
				continue
			var route := route_variant as Array
			if route.is_empty() or not route[0] is Array:
				continue
			var profile: Dictionary = route_profiles.get(route_name, {}) as Dictionary
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
					var link_record := _build_navigation_link(low, high, route_name, profile)
					var link_key := "%d|%d|%s" % [low, high, JSON.stringify(link_record)]
					if not link_keys.has(link_key):
						link_keys[link_key] = true
						links.append(link_record)
				previous_index = point_index
	return {"points": points, "links": links}

func _build_navigation_link(from_index: int, to_index: int, route_name: String, profile: Dictionary) -> Dictionary:
	var link := {
		"from": from_index,
		"to": to_index,
		"route": route_name,
		"danger": clampf(float(profile.get("danger", 0.0)), 0.0, 1.0),
		"cover": clampf(float(profile.get("cover", 0.0)), 0.0, 1.0),
		"costMultiplier": clampf(float(profile.get("costMultiplier", 1.0)), 0.25, 4.0),
	}
	for flag_name in ["precise", "crouch", "ladder"]:
		link[flag_name] = bool(profile.get(flag_name, false))
	return link

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
