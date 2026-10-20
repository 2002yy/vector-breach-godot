extends Node

var _out := "user://combat-events-visual"
var _main: Node3D
var _original: Dictionary
var _records: Array[Dictionary] = []


func _ready() -> void:
	get_tree().create_timer(55).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	_original = UserSettings.get_snapshot()
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	_main.call("_on_map_selected", _main.call("find_level_option_index", "gatehouse"))
	_main.call("_on_team_selected", "T")
	await get_tree().process_frame
	while bool(_main.get("_level_loading")):
		await get_tree().process_frame
	var menu := _main.get_node("StartMenu")
	await _click(menu.find_child("SettingsButton", true, false))
	var toggle: CheckButton = menu.get("_friendly_fire_toggle")
	if toggle.button_pressed:
		await _click(toggle)
	assert(not UserSettings.friendly_fire)
	await _capture("settings-friendly-off")
	await _click(toggle)
	assert(UserSettings.friendly_fire)
	var config := ConfigFile.new()
	assert(config.load(UserSettings.SETTINGS_PATH) == OK)
	assert(bool(config.get_value("match", "friendly_fire", false)))
	await _capture("settings-friendly-on")
	menu.call("_toggle_settings", false)
	await _click(menu.get("start_button"))
	while not bool(_main.get("game_started")) or bool(_main.get("_level_loading")):
		await get_tree().process_frame
	var actors: Array[Node] = []
	for actor in _main.get_node("CombatSandbox").get_children():
		if actor is CharacterBody3D:
			actor.call("set_ai_combat_enabled", false)
			actors.append(actor)
	await _click((_main.get_node("CombatHud").get("buy_menu") as Node).get("_ready_button"))
	assert(CombatEvents.friendly_fire)
	var player := _main.get_node("Player")
	var weapon := _main.get_node("WeaponSystem")
	var profile: Resource = weapon.call("_current_profile")
	var enemy: Node3D
	var ally: Node3D
	for actor in actors:
		if String(actor.get("team")) != GameState.player_team:
			enemy = actor
		else:
			ally = actor
	assert(enemy != null and ally != null)
	# Controlled real damage: no fabricated HUD death entries.
	for target in [enemy, ally]:
		for shot in range(10):
			if bool(target.get("is_dead")):
				break
			var result: Dictionary = weapon.call(
				"_apply_damage_to_hit",
				{"collider": target, "position": target.global_position + Vector3.UP * 0.65},
				player.global_position,
				profile,
				false
			)
			_main.call(
				"_on_shot_resolved",
				{
					"damage_events": [result],
					"damage_result": result,
					"weapon_name": "手枪",
					"hit": true
				}
			)
	await _capture("actual-enemy-and-team-kill")
	assert(CombatEvents.recent_deaths.size() == 2)
	assert(bool(CombatEvents.recent_deaths.back().team_kill))
	var hud := _main.get_node("CombatHud")
	assert(hud.get_node("HudRoot/KillFeed").get_child_count() == 2)
	assert(hud.get_node("HudRoot/TeamMessages").get_child_count() > 0)
	# Real hostile damage also drives the spectator flow.
	var hostile: Node3D
	for actor in actors:
		if String(actor.get("team")) != GameState.player_team and not bool(actor.get("is_dead")):
			hostile = actor
	assert(hostile != null)
	CombatEvents.apply_damage(
		player,
		"apply_hitscan_damage",
		[
			900,
			player.global_position,
			1.0,
			false,
			String(hostile.get("team")),
			hostile.global_position
		],
		CombatEvents.actor_source(hostile, "rifle")
	)
	await _capture("actual-death-spectator")
	var file := FileAccess.open(_out.path_join("events.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"events": CombatEvents.recent_deaths,
				"views": _records,
				"scope": "controlled real damage and actual UI input; not manual match acceptance"
			},
			"  "
		)
	)
	UserSettings.apply_snapshot(_original, true)
	print("COMBAT_EVENTS_VISUAL_OK views=4 deaths=3")
	get_tree().quit(0)


func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	Input.parse_input_event(move)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame


func _capture(label: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var path := _out.path_join(label + ".png")
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	_records.append({"label": label, "path": path})
