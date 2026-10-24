extends Node3D

signal targets_spawned(count: int)
signal combatants_spawned(friendly_count: int, enemy_count: int)
signal combatants_clearing
signal ai_shot(result: Dictionary, world_position: Vector3)
signal ai_footstep(world_position: Vector3, surface: String, quiet: bool)
signal radio_report(caller: String, message: String)

const Navigation = preload("res://scripts/ai/BotNavigationModel.gd")

@export var dummy_scene: PackedScene
@export var use_spawn_points: bool = true
@export var use_landmarks: bool = true
@export var fallback_target_count: int = 3
@export var max_targets: int = 5
@export var dummy_height: float = 1.15
@export var fallback_spacing: float = 6.0

var c4_device: Node3D
var last_load_timings: Dictionary = {}
var _load_generation := 0
var _current_level_data: Dictionary = {}
var _bomb_carrier_actor: CharacterBody3D
var _loaded_level_id: String = ""
var _saved_round_loadouts: Dictionary = {}
var _stable_match_roster: Dictionary = {}
var _competitive_hard_reset_pending: bool = false
var _round_economy: Dictionary = {}
var _team_loss_streaks := {"T": 0, "CT": 0}
var _income_round_serial := -1

func _ready() -> void:
	if not RoundManager.round_ended.is_connected(_on_round_ended_capture):
		RoundManager.round_ended.connect(_on_round_ended_capture)

func load_for_level(level_data: Dictionary, staged: bool = false) -> void:
	_load_generation += 1
	var generation := _load_generation
	var pending: Array[Dictionary] = []
	var spawn_work_usec := 0
	var max_actor_usec := 0
	var yielded_frames := 0
	var began := Time.get_ticks_usec()
	last_load_timings = {"id": String(level_data.get("id", "")), "actor_count": 0, "staged": staged}
	var retiring_scenes: Array[PackedScene] = []
	for actor in get_children():
		if not actor.has_method("get_native_character"):
			continue
		var visual: Node = actor.call("get_native_character")
		if visual != null and visual.has_method("source_scenes"):
			for scene in visual.call("source_scenes"):
				if scene not in retiring_scenes:
					retiring_scenes.append(scene)
	last_load_timings["retained_scene_count"] = retiring_scenes.size()
	last_load_timings["retain_scenes_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	var detach_began := Time.get_ticks_usec()
	_clear_targets()
	# queue_free() completes later; this measures detachment, not destruction.
	last_load_timings["detach_ms"] = (Time.get_ticks_usec() - detach_began) / 1000.0
	last_load_timings["deferred_free_excluded"] = true
	var level_id := String(level_data.get("id", ""))
	if _loaded_level_id != level_id:
		_loaded_level_id = level_id
		_saved_round_loadouts.clear()
	_current_level_data = level_data
	_round_economy.clear()
	_bomb_carrier_actor = null
	if dummy_scene == null:
		targets_spawned.emit(0)
		combatants_spawned.emit(0, 0)
		last_load_timings["total_ms"] = (Time.get_ticks_usec() - began) / 1000.0
		return
	var friendly_count := 0
	var enemy_count := 0
	var appearance_counts := {"CT": 0, "T": 0}
	var phase := Time.get_ticks_usec()
	var navigation_graph := _build_navigation_graph(level_data)
	var navigation_template := Navigation.prepare(navigation_graph)
	last_load_timings["navigation_prepare_count"] = 1
	last_load_timings["navigation_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	phase = Time.get_ticks_usec()
	for record_variant in _build_spawn_records(level_data):
		if not record_variant is Dictionary:
			continue
		var actor_began := Time.get_ticks_usec()
		var record := record_variant as Dictionary
		if _competitive_hard_reset_pending and GameState.is_competitive_level():
			_apply_competitive_reset(record)
		var saved_loadout: Dictionary = _saved_round_loadouts.get(String(record.get("name", "")), {})
		if not saved_loadout.is_empty():
			record["weaponInventory"] = saved_loadout.get("inventory", {})
			record["weapon"] = saved_loadout.get("weapon", record.get("weapon", "rifle"))
			record["weaponAmmoMag"] = saved_loadout.get("ammo_in_mag", 30)
			record["weaponAmmoReserve"] = saved_loadout.get("ammo_reserve", 0)
			record["armor"] = saved_loadout.get("armor", 0)
			record["helmet"] = saved_loadout.get("helmet", false)
			record["defuseKit"] = saved_loadout.get("defuse_kit", false)
			record["aiMoney"] = saved_loadout.get("money", record.get("aiMoney", 800))
			record["aiGrenades"] = saved_loadout.get("grenades", {})
		var target_instance := dummy_scene.instantiate()
		if not target_instance is Node3D:
			continue
		var target_node := target_instance as Node3D
		target_node.position = Vector3(float(record.get("x", 0.0)), float(record.get("y", dummy_height)), float(record.get("z", 0.0)))
		if staged:
			pending.append({"node": target_node, "mode": target_node.process_mode})
			target_node.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(target_node)
		if target_node.has_method("configure_from_record"):
			var route_name := String(record.get("route", ""))
			var routes: Dictionary = level_data.get("routes", {}) as Dictionary
			var ai_routes: Dictionary = level_data.get("aiRoutes", {}) as Dictionary
			record["routePoints"] = ai_routes.get(route_name, routes.get(route_name, []))
			record["navigationGraph"] = navigation_graph
			record["navigationTemplate"] = navigation_template
			var appearance_team := String(record.get("team", "T"))
			if appearance_team == "friendly":
				appearance_team = GameState.player_team
			elif appearance_team == "enemy":
				appearance_team = "CT" if GameState.player_team == "T" else "T"
			appearance_team = "CT" if appearance_team == "CT" else "T"
			record["appearance_id"] = record.get("appearance_id", preload("res://scripts/characters/CharacterAppearance.gd").profile_for(appearance_team, appearance_counts[appearance_team]))
			appearance_counts[appearance_team] += 1
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
		var actor_usec := Time.get_ticks_usec() - actor_began
		spawn_work_usec += actor_usec
		max_actor_usec = maxi(max_actor_usec, actor_usec)
		if staged:
			# Only the explicit start path yields; round resets remain synchronous.
			yielded_frames += 1
			await get_tree().process_frame
			if generation != _load_generation:
				return
	for entry in pending:
		(entry.node as Node).process_mode = entry.mode
	last_load_timings["spawn_work_ms"] = spawn_work_usec / 1000.0
	last_load_timings["max_actor_work_ms"] = max_actor_usec / 1000.0
	last_load_timings["yielded_frames"] = yielded_frames
	last_load_timings["spawn_configure_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	last_load_timings.actor_count = friendly_count + enemy_count
	phase = Time.get_ticks_usec()
	targets_spawned.emit(enemy_count)
	combatants_spawned.emit(friendly_count, enemy_count)
	_assign_bomb_roles(level_data)
	var scoreboard_records: Array = []
	for child in get_children():
		if child is CharacterBody3D and (child as CharacterBody3D).has_method("get_combat_snapshot"):
			scoreboard_records.append((child as CharacterBody3D).call("get_combat_snapshot"))
			if GameState.is_competitive_level():
				_remember_round_loadout(child as CharacterBody3D)
	GameState.set_scoreboard_combatants(scoreboard_records)
	_sync_team_economy()
	_competitive_hard_reset_pending = false
	# Old sources bridge deferred actor destruction only until the new roster is ready.
	retiring_scenes.clear()
	last_load_timings["finalize_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	last_load_timings["total_ms"] = (Time.get_ticks_usec() - began) / 1000.0

func clear_saved_round_state(reset_roster: bool = false) -> void:
	_saved_round_loadouts.clear()
	_round_economy.clear()
	_team_loss_streaks = {"T": 0, "CT": 0}
	_income_round_serial = -1
	_competitive_hard_reset_pending = true
	if reset_roster:
		_stable_match_roster.clear()

func _apply_competitive_reset(record: Dictionary) -> void:
	record["weaponInventory"] = {}
	record["weapon"] = "pistol"
	record["weaponAmmoMag"] = 12
	record["weaponAmmoReserve"] = 24
	record["armor"] = 0
	record["helmet"] = false
	record["defuseKit"] = false
	record["aiMoney"] = 800
	record["aiGrenades"] = {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0, "fire_grenade": 0}

func set_c4_device(device: Node3D) -> void:
	c4_device = device
	for child in get_children():
		if child.has_method("set_ai_c4_device"):
			child.call("set_ai_c4_device", device)

func _clear_targets() -> void:
	combatants_clearing.emit()
	for child in get_children():
		remove_child(child)
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
	var primary_target := Vector3(float(primary_objective.get("x", 0.0)), float(primary_objective.get("y", 1.15)), float(primary_objective.get("z", 0.0)))
	var primary_site := "A" if String(primary_objective.get("id", "")).to_lower().contains("a") else "B"
	var secondary_target := Vector3(float(secondary_objective.get("x", 0.0)), float(secondary_objective.get("y", 1.15)), float(secondary_objective.get("z", 0.0)))
	var secondary_site := "A" if String(secondary_objective.get("id", "")).to_lower().contains("a") else "B"
	var t_carrier_enabled := GameState.player_team != "T" and not t_actors.is_empty()
	for index in range(t_actors.size()):
		var actor := t_actors[index]
		actor.set_meta("squad_role_index", index)
		var role := "plant" if index == 0 else ("support" if index == 1 else "diversion")
		var objective := primary_objective if index < 2 else secondary_objective
		var site_target := Vector3(float(objective.get("x", 0.0)), float(objective.get("y", 1.15)), float(objective.get("z", 0.0)))
		var site_label := "A" if String(objective.get("id", "")).to_lower().contains("a") else "B"
		if actor.has_node("TacticalBotBrain"):
			actor.get_node("TacticalBotBrain").set(
				"alternate_site_target", secondary_target if index < 2 else primary_target
			)
			actor.get_node("TacticalBotBrain").set(
				"alternate_site_label", secondary_site if index < 2 else primary_site
			)
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
		c4_device.call("set_carried", "T", _bomb_carrier_actor.get_instance_id() if is_instance_valid(_bomb_carrier_actor) else 0)
	for index in range(ct_actors.size()):
		var actor := ct_actors[index]
		actor.set_meta("squad_role_index", index)
		var objective_index := index % maxi(1, objectives.size())
		var objective := objectives[objective_index] as Dictionary if not objectives.is_empty() else primary_objective
		var site_target := Vector3(float(objective.get("x", 0.0)), float(objective.get("y", 1.15)), float(objective.get("z", 0.0)))
		var site_label := "A" if String(objective.get("id", "")).to_lower().contains("a") else "B"
		if actor.has_node("TacticalBotBrain"):
			actor.get_node("TacticalBotBrain").call("configure_objective", "defend_site", site_target, site_label)
		if index == 0 and not _competitive_hard_reset_pending:
			actor.set("has_defuse_kit", true)
			if actor.has_method("set_ai_defuse_kit"):
				actor.call("set_ai_defuse_kit", true)

func _sync_team_economy() -> void:
	var team_money_totals := {"T": 0, "CT": 0}
	# Count every squad participant, including the local player.
	if GameState.player_team in team_money_totals:
		team_money_totals[GameState.player_team] = GameState.player_money
	for child in get_children():
		if child is CharacterBody3D and (child as CharacterBody3D).has_node("TacticalBotBrain"):
			var team := String((child as CharacterBody3D).get("team"))
			if team in team_money_totals:
				team_money_totals[team] = int(team_money_totals[team]) + int((child as CharacterBody3D).get_node("TacticalBotBrain").get("ai_money"))
	for child in get_children():
		if child is CharacterBody3D and (child as CharacterBody3D).has_node("TacticalBotBrain"):
			var team := String((child as CharacterBody3D).get("team"))
			var loss_streak := int(_team_loss_streaks.get(team, 0)) if GameState.is_competitive_level() else (GameState.loss_streak if team == GameState.player_team else 0)
			(child as CharacterBody3D).get_node("TacticalBotBrain").call(
				"set_team_economy",
				int(team_money_totals.get(team, 0)),
				loss_streak,
				GameState.match_team_size
			)

func _on_round_ended_capture(winner: String, _reason: String) -> void:
	if GameState.is_competitive_level() and _income_round_serial == RoundManager.round_serial:
		return
	if not GameState.is_competitive_level():
		_round_economy.clear()
	for child in get_children():
		if child is CharacterBody3D and (GameState.is_competitive_level() or not bool(child.get("is_dead"))):
			_remember_round_loadout(child as CharacterBody3D)
	var rewards := {"T": 0, "CT": 0}
	if GameState.is_competitive_level() and winner in ["T", "CT"]:
		_income_round_serial = RoundManager.round_serial
		for team in ["T", "CT"]:
			if team == winner:
				rewards[team] = 3250
				_team_loss_streaks[team] = 0
			else:
				var streak := int(_team_loss_streaks[team])
				rewards[team] = GameState.LOSS_BONUSES[mini(streak, GameState.LOSS_BONUSES.size() - 1)]
				_team_loss_streaks[team] = mini(streak + 1, GameState.LOSS_BONUSES.size() - 1)
				if team == "T" and not RoundManager.bomb_site.is_empty():
					rewards[team] += 800
	for actor_name in _round_economy:
		var participant: Dictionary = _round_economy[actor_name]
		var loadout: Dictionary = participant["loadout"].duplicate(true)
		loadout["money"] = mini(GameState.MAX_MONEY, int(loadout["money"]) + int(rewards.get(participant["team"], 0)))
		_saved_round_loadouts[actor_name] = loadout

func _remember_round_loadout(actor: CharacterBody3D) -> void:
	var snapshot := actor.call("get_combat_snapshot") as Dictionary
	var ai: Dictionary = snapshot.get("ai", {})
	var dead := bool(actor.get("is_dead"))
	var primary: Dictionary = actor.get_node("TacticalBotBrain").call("get_weapon_pickup_record", true)
	_round_economy[String(snapshot.get("name", ""))] = {
		"team": String(snapshot.get("team", "")),
		"loadout": {
			"weapon": "pistol" if dead else String(primary.get("weapon_id", "pistol")),
			"ammo_in_mag": 12 if dead else int(primary.get("ammo_in_mag", 12)),
			"ammo_reserve": 24 if dead else int(primary.get("ammo_reserve", 24)),
			"inventory": {} if dead else ai.get("inventory", {}).duplicate(true),
			"armor": 0 if dead else int(snapshot.get("armor", 0)),
			"helmet": not dead and bool(snapshot.get("helmet", false)),
			"defuse_kit": not dead and bool(snapshot.get("defuse_kit", false)),
			"money": int(ai.get("money", 800)),
			"grenades": {} if dead else (ai.get("grenades", {}) as Dictionary).duplicate(true),
		},
	}

func _on_actor_killed(_actor_name: String, _team: String, actor: CharacterBody3D) -> void:
	if GameState.is_competitive_level():
		_remember_round_loadout(actor)
	if c4_device == null or not is_instance_valid(c4_device) or not bool(c4_device.call("is_carried_by", actor)):
		return
	if c4_device != null and is_instance_valid(c4_device) and String(c4_device.get("device_state")) == "carried":
		c4_device.call("drop_at", actor.global_position)
		if _team == GameState.player_team:
			radio_report.emit(_actor_name, "携弹队员阵亡，C4 已掉落")
	RoundManager.bomb_carried = false
	_bomb_carrier_actor = null

func _on_actor_ai_spot(
	world_position: Vector3, enemy_team: String, spotter: CharacterBody3D
) -> void:
	_broadcast_teammate_report(world_position, enemy_team, String(spotter.get("team")), spotter)
	if String(spotter.get("team")) == GameState.player_team:
		radio_report.emit(
			String(spotter.get("display_name")), _report_area(spotter.global_position) + "发现敌方，注意交火"
		)


func _on_actor_ai_damaged(
	world_position: Vector3, source_team: String, damaged_actor: CharacterBody3D
) -> void:
	if source_team == String(damaged_actor.get("team")):
		if source_team == GameState.player_team:
			radio_report.emit(
				String(damaged_actor.get("display_name")),
				_report_area(damaged_actor.global_position) + "受到友军伤害，请注意射界"
			)
		return
	_broadcast_teammate_report(
		world_position, source_team, String(damaged_actor.get("team")), damaged_actor
	)
	if String(damaged_actor.get("team")) == GameState.player_team and not source_team.is_empty():
		radio_report.emit(
			String(damaged_actor.get("display_name")),
			_report_area(damaged_actor.global_position) + "受到攻击，请求支援"
		)


func _report_area(at: Vector3) -> String:
	var closest := 12.0
	var label := ""
	for objective in _current_level_data.get("objectives", []):
		var position := Vector3(float(objective.get("x", 0)), at.y, float(objective.get("z", 0)))
		var distance := at.distance_to(position)
		if distance < closest:
			closest = distance
			label = (
				"A 点附近 · "
				if String(objective.get("id", "")) == "site-a"
				else "B 点附近 · " if String(objective.get("id", "")) == "site-b" else ""
			)
	return label


func _broadcast_teammate_report(world_position: Vector3, enemy_team: String, friendly_team: String, exclude_actor: CharacterBody3D) -> void:
	if enemy_team.is_empty() or friendly_team.is_empty():
		return
	var candidates: Array[Node3D] = []
	for child in get_children():
		if (
			child is CharacterBody3D
			and child != exclude_actor
			and String(child.get("team")) == friendly_team
			and not bool(child.get("is_dead"))
		):
			candidates.append(child)
	candidates.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return (
				a.global_position.distance_squared_to(world_position)
				< b.global_position.distance_squared_to(world_position)
			)
	)
	for index in range(mini(2, candidates.size())):
		if candidates[index].has_method("notify_ai_teammate_report"):
			candidates[index].call("notify_ai_teammate_report", world_position, enemy_team)

func notify_ai_sound(world_position: Vector3, audible_radius: float, source_team: String) -> int:
	var notified := 0
	for child in get_children():
		if child.has_method("notify_ai_sound") and bool(child.call("notify_ai_sound", world_position, audible_radius, source_team)):
			notified += 1
	return notified

func _on_actor_ai_shot(result: Dictionary, world_position: Vector3) -> void:
	for damage in result.get("damage_events", [result.get("damage_result", {})]):
		GameState.record_scoreboard_damage(
			String(result.get("shooter_name", "Bot")),
			String(result.get("shooter_team", "")),
			damage
		)
	ai_shot.emit(result, world_position)
	notify_ai_sound(world_position, 52.0, String((result.get("shooter_team", ""))))

func _on_actor_ai_footstep(world_position: Vector3, surface: String, quiet: bool) -> void:
	ai_footstep.emit(world_position, surface, quiet)

func _build_navigation_graph(level_data: Dictionary) -> Dictionary:
	if level_data.has("navigationGraph"):
		return level_data["navigationGraph"] as Dictionary
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
		return _build_competitive_roster(records) if GameState.is_competitive_level() and GameState.match_phase != "inactive" else records
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

func _build_competitive_roster(source_records: Array) -> Array:
	var by_team := {"T": [], "CT": []}
	for record_variant in source_records:
		if record_variant is Dictionary:
			var record := record_variant as Dictionary
			var team := String(record.get("team", ""))
			if team in by_team:
				(by_team[team] as Array).append(record)
	var opponent_team := "CT" if GameState.player_team == "T" else "T"
	if _stable_match_roster.is_empty():
		var player_templates: Array = by_team[GameState.player_team] as Array
		var opponent_templates: Array = by_team[opponent_team] as Array
		var player_names: Array[String] = []
		if GameState.match_team_size == 5:
			for index in range(player_templates.size()):
				if index != player_templates.size() / 2 and player_names.size() < 4:
					player_names.append(String(player_templates[index].get("name", "ALLY")))
		elif player_templates.size() >= 3:
			player_names.append(String((player_templates[0] as Dictionary).get("name", "ALLY-1")))
			player_names.append(String((player_templates[2] as Dictionary).get("name", "ALLY-2")))
		else:
			for record_variant in player_templates.slice(0, 2):
				player_names.append(String((record_variant as Dictionary).get("name", "ALLY")))
		var opponent_names: Array[String] = []
		for record_variant in opponent_templates.slice(0, GameState.match_team_size):
			opponent_names.append(String((record_variant as Dictionary).get("name", "OPPONENT")))
		_stable_match_roster = {"player": player_names, "opponent": opponent_names}
	var output: Array = []
	_append_squad_records(output, by_team[GameState.player_team] as Array, _stable_match_roster.get("player", []) as Array, true)
	_append_squad_records(output, by_team[opponent_team] as Array, _stable_match_roster.get("opponent", []) as Array, false)
	return output

func _append_squad_records(output: Array, templates: Array, stable_names: Array, player_squad: bool) -> void:
	var selected_templates: Array = templates
	if player_squad and GameState.match_team_size == 5:
		selected_templates = []
		for index in range(templates.size()):
			if index != templates.size() / 2:
				selected_templates.append(templates[index])
	elif player_squad and templates.size() >= 3:
		selected_templates = [templates[0], templates[2]]
	else:
		selected_templates = templates.slice(0, stable_names.size())
	for index in range(mini(selected_templates.size(), stable_names.size())):
		var record := (selected_templates[index] as Dictionary).duplicate(true)
		record["name"] = String(stable_names[index])
		record["squad"] = "player" if player_squad else "opponent"
		output.append(record)
