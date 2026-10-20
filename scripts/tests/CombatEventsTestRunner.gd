extends Node3D

const ACTOR = preload("res://scenes/combat/TacticalActor.tscn")
const PLAYER = preload("res://scenes/player/Player.tscn")
const HUD = preload("res://scenes/ui/CombatHud.tscn")
const GRENADE = preload("res://scripts/combat/GrenadeProjectile.gd")
const FIRE = preload("res://scripts/combat/FireArea.gd")
var _failures: Array[String] = []
var _passes := 0
var _settings: Dictionary
var _fixture: Node3D
var _serial := 0


func _ready() -> void:
	_settings = UserSettings.get_snapshot()
	for test in [
		_test_all_damage_kinds_block_friend,
		_test_enabled_pairs_and_armor,
		_test_friendly_kill_no_reward,
		_test_self_damage_and_environment,
		_test_one_death_and_score_per_life,
		_test_dead_thrower_he_hits_player,
		_test_fire_policy_and_delayed_source,
		_test_real_assist_and_score_dedup,
		_test_round_snapshot_and_stale_projectile,
		_test_settings_roundtrip,
		_test_message_separation_and_bounds,
	]:
		await _run(test)
	UserSettings.apply_snapshot(_settings, false)
	CombatEvents.begin_round()
	if _failures.is_empty():
		print("[CombatEventsTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _run(test: Callable) -> void:
	var before := _failures.size()
	RoundManager.set_warmup()
	UserSettings.apply_snapshot({"friendly_fire": false}, false)
	GameState.reset_runtime_state()
	GameState.player_team = "T"
	_fixture = Node3D.new()
	add_child(_fixture)
	await test.call()
	_fixture.queue_free()
	await get_tree().process_frame
	if _failures.size() == before:
		_passes += 1
		print("[CombatEventsTests] PASS ", test.get_method())


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _actor(team: String, at: Vector3 = Vector3(5, 1, 0)) -> CharacterBody3D:
	var actor: CharacterBody3D = ACTOR.instantiate()
	_serial += 1
	actor.set("display_name", "单位%d" % _serial)
	actor.set("team", team)
	_fixture.add_child(actor)
	actor.global_position = at
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.get_node("TacticalBotBrain").set_physics_process(false)
	actor.get_node("TacticalBotBrain").set_process(false)
	actor.call("set_ai_combat_enabled", false)
	return actor


func _player() -> CharacterBody3D:
	var player: CharacterBody3D = PLAYER.instantiate()
	_fixture.add_child(player)
	player.global_position = Vector3(0, 1, 0)
	player.set_physics_process(false)
	player.set_process(false)
	return player


func _hit(target: Node3D, source: Dictionary, amount: int = 30) -> Dictionary:
	return CombatEvents.apply_damage(
		target,
		"apply_hitscan_damage",
		[amount, target.global_position, 1.0, false, String(source.get("team", "")), Vector3.ZERO],
		source
	)


func _enable() -> void:
	UserSettings.apply_snapshot({"friendly_fire": true}, false)
	CombatEvents.begin_round()


func _test_all_damage_kinds_block_friend() -> void:
	var shooter := _actor("T", Vector3(-5, 1, 0))
	var target := _actor("T")
	target.set("current_armor", 100)
	for kind in ["bullet", "melee", "explosion", "fire"]:
		var result := _hit(target, CombatEvents.actor_source(shooter, "rifle", kind), 900)
		_check(not bool(result.get("hit", false)), kind + " must block friendly damage")
	_check(
		target.get("current_health") == 100 and target.get("current_armor") == 100,
		"blocked damage preserves health and armor"
	)
	_check(CombatEvents.recent_deaths.is_empty(), "blocked damage cannot publish death")
	var player := _player()
	var result := CombatEvents.apply_damage(
		player,
		"apply_explosive_damage",
		[900, 1.0],
		CombatEvents.actor_source(shooter, "he_grenade", "explosion")
	)
	_check(
		not bool(result.hit) and GameState.player_health == 100,
		"same rule protects player from AI explosion"
	)


func _test_enabled_pairs_and_armor() -> void:
	_enable()
	var player := _player()
	var shooter := _actor("T", Vector3(-5, 1, 0))
	var target := _actor("T")
	var player_source := CombatEvents.actor_source(player, "rifle")
	_check(bool(_hit(target, player_source).get("hit", false)), "enabled player to ally")
	_check(
		bool(_hit(target, CombatEvents.actor_source(shooter, "knife", "melee")).get("hit", false)),
		"enabled AI to AI"
	)
	GameState.player_armor = 100
	_check(
		bool(_hit(player, CombatEvents.actor_source(shooter, "rifle")).get("hit", false)),
		"enabled AI to player"
	)
	_check(GameState.player_armor < 100, "enabled friendly bullet consumes real armor")


func _test_friendly_kill_no_reward() -> void:
	_enable()
	var player := _player()
	var target := _actor("T")
	var money := GameState.player_money
	var result := _hit(target, CombatEvents.actor_source(player, "rifle"), 900)
	GameState.register_hit(bool(result.killed), "rifle", String(result.target_team))
	var event: Dictionary = CombatEvents.recent_deaths.back()
	_check(bool(event.team_kill), "friendly death is labelled team kill")
	_check(
		GameState.player_money == money and GameState.kill_count == 0,
		"friendly kill grants no money or enemy kill"
	)
	_check(int(GameState.unit_scoreboard["你"].kills) == 0, "scoreboard excludes friendly kill")


func _test_self_damage_and_environment() -> void:
	var player := _player()
	var result := CombatEvents.apply_damage(
		player,
		"apply_explosive_damage",
		[900, 1.0],
		CombatEvents.actor_source(player, "he_grenade", "explosion")
	)
	_check(bool(result.killed), "self damage remains enabled when friendly fire is off")
	_check(bool(CombatEvents.recent_deaths.back().self_kill), "self death attribution")
	_check(
		(
			int(GameState.unit_scoreboard["你"].deaths) == 1
			and int(GameState.unit_scoreboard["你"].kills) == 0
		),
		"self death scoreboard survives same-name update"
	)
	player.set("is_dead", false)
	GameState.player_health = 100
	CombatEvents.forget_actor(player)
	player.call("_apply_fall_damage", 100.0)
	_check(
		CombatEvents.recent_deaths.back().killer == "环境",
		"fall death has explicit environment attribution"
	)


func _test_one_death_and_score_per_life() -> void:
	var shooter := _actor("T", Vector3(-5, 1, 0))
	var target := _actor("CT")
	var source := CombatEvents.actor_source(shooter, "shotgun")
	for pellet in range(8):
		_hit(target, source, 80)
	_check(CombatEvents.recent_deaths.size() == 1, "multiple pellets publish only one death")
	var name := String(target.get("display_name"))
	_check(int(GameState.unit_scoreboard[name].deaths) == 1, "death counted once")
	target.call("reset_actor")
	target.call("set_ai_combat_enabled", false)
	_hit(target, source, 900)
	_check(CombatEvents.recent_deaths.size() == 2, "new life can die once again")


func _test_dead_thrower_he_hits_player() -> void:
	var player := _player()
	var shooter := _actor("CT", Vector3(-5, 1, 0))
	var shooter_name := String(shooter.get("display_name"))
	var grenade := GRENADE.new()
	_fixture.add_child(grenade)
	grenade.configure(
		"he_grenade", shooter, player.global_position + Vector3(0, 0.2, 0), Vector3.ZERO
	)
	grenade.set_physics_process(false)
	shooter.queue_free()
	await get_tree().process_frame
	GameState.player_health = 1
	grenade.call("_apply_he_damage")
	_check(bool(player.get("is_dead")), "AI grenade must actually damage local player")
	_check(CombatEvents.recent_deaths.back().killer == shooter_name, "freed thrower name preserved")
	_check(
		CombatEvents.recent_deaths.back().weapon_id == "he_grenade",
		"HE does not appear as fire or rifle"
	)


func _test_fire_policy_and_delayed_source() -> void:
	var shooter := _actor("T", Vector3(-5, 1, 0))
	var target := _actor("T", Vector3(0, 1, 0))
	var attribution := CombatEvents.actor_source(shooter, "fire_grenade", "fire")
	var fire := FIRE.new()
	_fixture.add_child(fire)
	fire.configure(shooter, "T", target.global_position, attribution)
	fire.set_physics_process(false)
	await get_tree().physics_frame
	fire.apply_damage_tick()
	_check(target.get("current_health") == 100, "friendly fire area blocked")
	_enable()
	fire.apply_damage_tick()
	_check(int(target.get("current_health")) < 100, "enabled fire area damages ally")
	target.set("team", "CT")
	target.set("current_health", 1)
	shooter.queue_free()
	await get_tree().process_frame
	fire.apply_damage_tick()
	_check(
		CombatEvents.recent_deaths.back().killer == attribution.name,
		"persistent fire keeps freed source identity"
	)


func _test_real_assist_and_score_dedup() -> void:
	var first := _actor("T", Vector3(-5, 1, 0))
	var second := _actor("T", Vector3(-4, 1, 0))
	var target := _actor("CT")
	_hit(target, CombatEvents.actor_source(first, "rifle"), 40)
	var result := _hit(target, CombatEvents.actor_source(second, "sniper"), 900)
	GameState.record_scoreboard_damage(String(second.get("display_name")), "T", result)
	var event: Dictionary = CombatEvents.recent_deaths.back()
	_check(String(first.get("display_name")) in event.assists, "assist derives from actual damage")
	_check(
		int(GameState.unit_scoreboard[String(second.get("display_name"))].kills) == 1,
		"legacy callback cannot double count score"
	)


func _test_round_snapshot_and_stale_projectile() -> void:
	var source := CombatEvents.actor_source(_actor("T"), "he_grenade", "explosion")
	RoundManager.set_live()
	UserSettings.apply_snapshot({"friendly_fire": true}, false)
	_check(not CombatEvents.friendly_fire, "live setting change waits for next round")
	RoundManager.start_round()
	_check(CombatEvents.friendly_fire, "new round activates persisted preference")
	var target := _actor("CT")
	_check(not bool(_hit(target, source, 900).hit), "old-round projectile cannot damage new life")
	_check(CombatEvents.recent_deaths.is_empty(), "old round feed cleared")


func _test_settings_roundtrip() -> void:
	var path := "user://combat-events-test-settings.cfg"
	UserSettings.apply_snapshot({"friendly_fire": true}, false)
	UserSettings.save_settings(path)
	UserSettings.apply_snapshot({"friendly_fire": false}, false)
	UserSettings.load_settings(path)
	_check(UserSettings.friendly_fire, "friendly fire preference survives ConfigFile roundtrip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_message_separation_and_bounds() -> void:
	var hud := HUD.instantiate()
	_fixture.add_child(hud)
	var kills := hud.get_node("HudRoot/KillFeed")
	var messages := hud.get_node("HudRoot/TeamMessages")
	hud.call("show_radio_report", "队友", "发现敌人")
	hud.call("show_radio_report", "队友", "发现敌人")
	_check(
		kills.get_child_count() == 0 and messages.get_child_count() == 1,
		"radio separated and rate limited"
	)
	var first := _actor("T", Vector3(-5, 1, 0))
	for index in range(7):
		var target := _actor("CT", Vector3(5 + index, 1, 0))
		_hit(target, CombatEvents.actor_source(first, "rifle"), 900)
	_check(kills.get_child_count() == 5, "real kill queue is bounded")
	CombatEvents.death_reported.emit(CombatEvents.recent_deaths.back())
	_check(kills.get_child_count() == 5, "duplicate event does not add UI entry")
	CombatEvents.begin_round()
	_check(
		kills.get_child_count() == 0 and messages.get_child_count() == 0,
		"round clears both channels"
	)
