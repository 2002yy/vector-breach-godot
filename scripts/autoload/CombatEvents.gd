extends Node

signal death_reported(event: Dictionary)
signal round_cleared

var friendly_fire := false
var recent_deaths: Array[Dictionary] = []
var _source: Dictionary = {}
var _dead: Dictionary = {}
var _damage_ledger: Dictionary = {}
var _sequence := 0


func _ready() -> void:
	UserSettings.settings_changed.connect(_settings_changed)
	begin_round()


func begin_round() -> void:
	friendly_fire = UserSettings.friendly_fire
	_dead.clear()
	_damage_ledger.clear()
	recent_deaths.clear()
	round_cleared.emit()


func _settings_changed(_snapshot: Dictionary) -> void:
	if RoundManager.state == RoundManager.RoundState.WARMUP:
		friendly_fire = UserSettings.friendly_fire


func forget_actor(actor: Node) -> void:
	_dead.erase(actor.get_instance_id())
	_damage_ledger.erase(actor.get_instance_id())


func actor_source(actor: Node, weapon: String, kind: String = "bullet") -> Dictionary:
	var local := is_instance_valid(actor) and actor.is_in_group("local_player")
	return {
		"actor_id": actor.get_instance_id() if is_instance_valid(actor) else 0,
		"name":
		"你" if local else String(actor.get("display_name")) if is_instance_valid(actor) else "环境",
		"team":
		(
			GameState.player_team
			if local
			else String(actor.get("team")) if is_instance_valid(actor) else ""
		),
		"player": local,
		"weapon_id": weapon,
		"kind": kind,
		"round_serial": RoundManager.round_serial,
	}


func player_source(weapon: String) -> Dictionary:
	var source := actor_source(get_tree().get_first_node_in_group("local_player"), weapon)
	source.merge({"name": "你", "team": GameState.player_team, "player": true}, true)
	return source


func apply_damage(target: Node, method: String, args: Array, source: Dictionary) -> Dictionary:
	if int(source.get("round_serial", RoundManager.round_serial)) != RoundManager.round_serial:
		return {"hit": false, "killed": false, "stale_round": true}
	var previous := _source
	_source = source
	var result: Dictionary = target.callv(method, args)
	_source = previous
	return result


func allows_damage(target: Node, fallback_team: String = "") -> bool:
	var source_team := String(_source.get("team", fallback_team))
	if source_team.is_empty() or int(_source.get("actor_id", 0)) == target.get_instance_id():
		return true
	var target_team := (
		GameState.player_team
		if target.is_in_group("local_player")
		else String(target.get("team")) if target.is_in_group("combat_actors") else ""
	)
	return friendly_fire or source_team != target_team


func finish_damage(target: Node, result: Dictionary) -> Dictionary:
	if not bool(result.get("hit", false)):
		return result
	var source := _source.duplicate(true)
	var target_id := target.get_instance_id()
	if _dead.has(target_id):
		return {"hit": false, "killed": false}
	var local := target.is_in_group("local_player")
	result["target_name"] = "你" if local else String(target.get("display_name"))
	result["target_team"] = (
		GameState.player_team
		if local
		else (
			String(target.get("team"))
			if target.is_in_group("combat_actors")
			else String(result.get("target_team", ""))
		)
	)
	result["target_id"] = target_id
	var killer := String(source.get("name", "环境"))
	var source_team := String(source.get("team", ""))
	var self_kill := int(source.get("actor_id", 0)) == target_id
	var team_kill := (
		not source_team.is_empty() and source_team == String(result.target_team) and not self_kill
	)
	result["friendly_fire"] = team_kill
	result["self_damage"] = self_kill
	_record_assist_damage(target_id, source, result)
	GameState.record_scoreboard_damage(killer, source_team, result)
	result["score_recorded"] = true
	if not bool(result.get("killed", false)) or _dead.has(target_id):
		return result
	_dead[target_id] = true
	_sequence += 1
	var event := {
		"id": _sequence,
		"round_serial": RoundManager.round_serial,
		"killer": killer,
		"killer_id": int(source.get("actor_id", 0)),
		"killer_team": source_team,
		"victim": String(result.target_name),
		"victim_id": target_id,
		"victim_team": String(result.target_team),
		"weapon_id": String(source.get("weapon_id", "environment")),
		"kind": String(source.get("kind", "environment")),
		"headshot":
		bool(result.get("headshot", false)) and String(source.get("kind", "")) == "bullet",
		"penetrated": bool(result.get("penetrated", false)),
		"team_kill": team_kill,
		"self_kill": self_kill,
		"assists": _assists(target_id, source),
		"local_involved": local or bool(source.get("player", false)),
	}
	recent_deaths.append(event.duplicate(true))
	if recent_deaths.size() > 32:
		recent_deaths.pop_front()
	_damage_ledger.erase(target_id)
	death_reported.emit(event)
	return result


func _record_assist_damage(target_id: int, source: Dictionary, result: Dictionary) -> void:
	var id := int(source.get("actor_id", 0))
	if id == 0 or bool(result.friendly_fire) or bool(result.self_damage):
		return
	var ledger: Dictionary = _damage_ledger.get(target_id, {})
	var row: Dictionary = ledger.get(
		id, {"name": source.get("name", ""), "team": source.get("team", ""), "damage": 0}
	)
	row["damage"] = int(row.damage) + int(result.get("damage", 0))
	row["time"] = Time.get_ticks_msec()
	ledger[id] = row
	_damage_ledger[target_id] = ledger


func _assists(target_id: int, source: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var ledger: Dictionary = _damage_ledger.get(target_id, {})
	for id in ledger:
		var row: Dictionary = ledger[id]
		if (
			id != int(source.get("actor_id", 0))
			and row.team == source.get("team", "")
			and int(row.damage) >= 40
			and Time.get_ticks_msec() - int(row.time) <= 10000
		):
			names.append(String(row.name))
	return names
