extends Node

const Catalog = preload("res://scripts/level/LocalClassicMaps.gd")
var _out := "user://classic-maps-ui"
var _failures: Array = []
var _records: Array = []


func _ready() -> void:
	get_window().gui_embed_subwindows = true
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var original := UserSettings.get_snapshot()
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames()
	var menu := main.get_node("StartMenu")
	await _click(menu.get_node("MenuPanel/Margin/VBox/SettingsButton"))
	_expect((menu.get("_settings_panel") as Control).visible, "settings button opens actual panel")
	for team in ["CT", "T"]:
		var choice: OptionButton = (menu.get("_appearance_choices") as Dictionary)[team]
		await _select(choice, 2)
		var selected := UserSettings.ct_appearance if team == "CT" else UserSettings.t_appearance
		_expect(
			selected == ("ct-fbi" if team == "CT" else "t-blackwolf"),
			"actual dropdown updates " + team
		)
	await _capture("skin-settings-clicked")
	menu.call("_toggle_settings", false)
	if "--ui-only" in args:
		main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
		await _click(menu.get("start_button"))
		await _frames(20)
		_check_hands(main, "t-blackwolf")
		await _capture("skin-first-person-from-ui")
	else:
		for id in Catalog.MAPS:
			if "--map" in args and id != args[args.find("--map") + 1]:
				continue
			if not main.get("menu_open"):
				main.call("_open_menu", false)
				await _click(menu.get("_return_to_maps_button"))
			var index := int(main.call("find_level_option_index", id))
			_expect(index >= 0, "installed playable map " + id)
			if index < 0:
				continue
			var select: OptionButton = menu.get("map_select")
			for item in range(select.item_count):
				if select.get_item_id(item) == index:
					await _select(select, item)
					break
			var team_index := 0 if id.begins_with("inferno") else 1
			if "--team" in args:
				team_index = 0 if args[args.find("--team") + 1] == "T" else 1
			await _select(menu.get("team_select"), team_index)
			await _capture(id + "-menu")
			await _click(menu.get("start_button"))
			await _frames(20)
			_expect(GameState.current_level_id == id, "UI starts selected level")
			_expect(GameState.match_team_size == 5, "five players per team")
			_expect(RoundManager.can_buy(), "competitive buy phase")
			var roster: Array = []
			for actor in main.get_node("CombatSandbox").get_children():
				if actor.has_method("get_combat_snapshot"):
					roster.append(actor.call("get_combat_snapshot"))
			_expect(roster.size() == 9, "nine AI plus human")
			_check_hands(main, "t-blackwolf" if GameState.player_team == "T" else "ct-fbi")
			await _capture(id + "-buy")
			var page: Control = main.get_node("CombatHud").get("buy_menu")
			await _click(page.get("_ready_button"))
			_expect(RoundManager.state == RoundManager.RoundState.LIVE, "ready click ends wait")
			await _capture(id + "-live")
			_records.append({"level": id, "roster": roster, "team": GameState.player_team})
			if "--observe" in args:
				var seconds := 60
				if "--observe-seconds" in args:
					seconds = clampi(int(args[args.find("--observe-seconds") + 1]), 1, 130)
				await _observe(main, id, seconds, not ("--real-time-observe" in args))
	UserSettings.apply_snapshot(original, true)
	main.queue_free()
	await _frames(3)
	var receipt := FileAccess.open(_out.path_join("ui-receipt.json"), FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"failures": _failures, "records": _records}, "\t"))
	print("CLASSIC_MAPS_UI_PROBE=" + JSON.stringify({"failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_hands(main: Node, expected: String) -> void:
	var view := main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var hands: Node = view.get("hands")
	var snapshot: Dictionary = hands.call("snapshot")
	_expect(snapshot.appearance == expected, "UI selection reaches first person")
	_expect(snapshot.native.get("arms", 0) == 2, "actual pair of skinned arms installed")
	_records.append(snapshot)


func _observe(main: Node, id: String, seconds: int, accelerated: bool = true) -> void:
	var origins := {}
	var movements := {}
	var samples: Array = []
	for actor in main.get_node("CombatSandbox").get_children():
		if actor.has_method("get_combat_snapshot"):
			origins[actor.name] = actor.global_position
	var original_scale := Engine.time_scale
	var original_ticks := Engine.physics_ticks_per_second
	if accelerated:
		Engine.time_scale = 4.0
		Engine.physics_ticks_per_second = 240
	for second in range(seconds):
		await get_tree().create_timer(1.0).timeout
		var roster: Array = []
		for actor in main.get_node("CombatSandbox").get_children():
			if not actor.has_method("get_combat_snapshot"):
				continue
			var record: Dictionary = actor.call("get_combat_snapshot")
			roster.append(record)
			if origins.has(actor.name):
				movements[actor.name] = maxf(
					float(movements.get(actor.name, 0)),
					actor.global_position.distance_to(origins[actor.name])
				)
				_expect(
					actor.global_position.y > (origins[actor.name] as Vector3).y - 12.0,
					"actor must not fall out of map"
				)
		(
			samples
			. append(
				{
					"second": second + 1,
					"actors": roster,
					"round_state": RoundManager.get_state_name(),
					"render_fps": Engine.get_frames_per_second(),
					"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
					"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
					"draw_calls":
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					"primitives":
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				}
			)
		)
		if RoundManager.state == RoundManager.RoundState.ROUND_END:
			break
	Engine.time_scale = original_scale
	Engine.physics_ticks_per_second = original_ticks
	_expect(
		movements.values().any(func(distance: float) -> bool: return distance > 5.0),
		"natural AI leaves spawn on " + id
	)
	_records.append(
		{
			"level": id,
			"natural_observation": samples,
			"max_displacements": movements,
			"observation_mode": "accelerated" if accelerated else "real_time"
		}
	)
	await _capture(id + "-observed")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
		push_error(label)


func _frames(count: int = 8) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func _click(control: Control) -> void:
	await _frames(4)
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await _frames(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _select(control: OptionButton, index: int) -> void:
	await _click(control)
	var popup := control.get_popup()
	await get_tree().create_timer(0.4).timeout
	var point := (
		Vector2(popup.position)
		+ Vector2(popup.size.x * 0.5, popup.size.y * (index + 0.5) / popup.item_count)
	)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await _frames(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames()
	_expect(control.selected == index, "dropdown selected item " + str(index))


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _capture(label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png"))
