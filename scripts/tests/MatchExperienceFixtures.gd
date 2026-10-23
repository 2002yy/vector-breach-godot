extends RefCounted


static func spectator_boundaries(host: Node) -> void:
	var main: Node3D = host.call("_instantiate_main")
	await host.call("_await_main_ready")
	main.call("_on_map_selected", main.call("find_level_option_index", "gatehouse"))
	main.call("_on_team_selected", "CT")
	await main.call("_on_start_pressed")
	var sandbox := main.get_node("CombatSandbox")
	for actor in sandbox.get_children():
		actor.set_physics_process(false)
	RoundManager.set_live()
	main.get_node("Player").call("apply_explosive_damage", 1000)
	var watch: Node = main.get("spectator")
	watch.call("tick")
	var first: Node = watch.get("target")
	sandbox.remove_child(first)
	host.call(
		"_assert_true", not watch.get_snapshot().has_target, "detached teammate is not sampled"
	)
	watch.call("tick")
	host.call("_assert_true", watch.get("target") != first, "detached target hands off")
	var foreign_view := SubViewport.new()
	foreign_view.own_world_3d = true
	main.add_child(foreign_view)
	foreign_view.add_child(first)
	watch.set("target", first)
	host.call(
		"_assert_true",
		not watch.get_snapshot().has_target,
		"moved target in another viewport is not sampled"
	)
	watch.call("tick")
	host.call("_assert_true", watch.get("target") != first, "moved target hands off locally")
	foreign_view.remove_child(first)
	sandbox.add_child(first)
	watch.set("target", first)
	first.free()
	watch.call("cycle", 1)
	watch.call("tick")
	host.call(
		"_assert_true",
		watch.get_snapshot().has_target,
		"freed target cycles without typed-array errors"
	)
	var foreign := preload("res://scenes/combat/TacticalActor.tscn").instantiate()
	foreign.set("team", "CT")
	foreign_view.add_child(foreign)
	foreign.set_physics_process(false)
	host.call(
		"_assert_true", not watch.teammates().has(foreign), "preview viewport teammate is excluded"
	)
	var last: Node = watch.get("target")
	last.queue_free()
	host.call(
		"_assert_true", not watch.get_snapshot().has_target, "retiring teammate is not sampled"
	)
	watch.call("tick")
	host.call(
		"_assert_true",
		not watch.get_snapshot().has_target,
		"no local teammate never falls back across viewports"
	)
	await host.call("_cleanup_main", main)


static func lobby_controls(host: Node) -> void:
	var main: Node3D = host.call("_instantiate_main")
	await host.call("_await_main_ready")
	var menu := main.get_node("StartMenu")
	menu.find_child("CTCard", true, false).pressed.emit()
	host.call("_assert_equal", GameState.player_team, "CT", "visible CT card changes actual side")
	menu.find_child("MapCard", true, false).pressed.emit()
	host.call("_assert_true", menu.get_node("MapPicker").visible, "map card opens visual selection")
	host.call(
		"_assert_true",
		menu.find_child("Map_depot", true, false) == null,
		"developer maps are absent from the normal map picker"
	)
	menu.find_child("Map_training_range", true, false).pressed.emit()
	await host.call("_await_main_ready")
	host.call(
		"_assert_equal",
		GameState.current_level_id,
		"training-range",
		"thumbnail selection loads its actual map, not a display-only state"
	)
	menu.call("toggle_player_help")
	var help := menu.get_node("PlayerHelp")
	host.call(
		"_assert_equal",
		help.find_child("GuideRows", true, false).get_child_count(),
		6,
		"basic guide shows six primary operations"
	)
	help.find_child("BombTab", true, false).pressed.emit()
	host.call(
		"_assert_true",
		(help.get("body") as RichTextLabel).text.contains("自由练习"),
		"rules reflect the selected practice mode"
	)
	menu.call("_toggle_settings", true)
	host.call(
		"_assert_true",
		not help.visible and not menu.get_node("MapPicker").visible,
		"settings do not stack over help or map selection"
	)
	menu.call("_toggle_settings", false)
	await main.call("_on_start_pressed")
	host.call(
		"_assert_true",
		(main.get_node("Player").call("get_camera_node") as Camera3D).current,
		"starting play restores the player camera from the lobby camera"
	)
	await host.call("_cleanup_main", main)


static func purchases_and_help(host: Node) -> void:
	var main: Node3D = host.call("_instantiate_main")
	await host.call("_await_main_ready")
	var preview_player: CharacterBody3D = main.get_node("Player")
	preview_player.global_position = Vector3(999, 999, 999)
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	await host.call("_await_main_ready")
	host.call(
		"_assert_true",
		preview_player.global_position.distance_to(GameState.player_spawn) < 0.5,
		"map selection resets preview camera to the new map spawn"
	)
	host.call("_assert_true", not bool(main.get("game_started")), "preview does not start match")
	main.call("_on_map_selected", main.call("find_level_option_index", "gatehouse"))
	await host.call("_await_main_ready")
	main.call("_on_team_selected", "CT")
	await main.call("_on_start_pressed")
	for actor in main.get_node("CombatSandbox").get_children():
		actor.set_physics_process(false)
	var system := main.get_node("WeaponSystem")
	var hud := main.get_node("CombatHud")
	GameState.player_money = 16000
	main.call("_purchase_item", "sniper")
	host.call("_assert_equal", GameState.player_money, 11250, "sniper purchase charges exact price")
	var states: Array = system.get("_weapon_states")
	states[0].ammo_in_mag = 2
	states[0].ammo_reserve = 7
	main.call("_purchase_item", "smg")
	host.call(
		"_assert_equal",
		system.call("get_slot_record", 0).weapon_id,
		"smg",
		"primary replacement is real"
	)
	var drops := main.get_tree().get_nodes_in_group("weapon_pickups")
	host.call("_assert_equal", drops.size(), 1, "replacing weapon drops one old gun")
	if not drops.is_empty():
		var record: Dictionary = drops[0].get("weapon_record")
		host.call("_assert_equal", record.ammo_in_mag, 2, "old magazine survives replacement")
		host.call("_assert_equal", record.ammo_reserve, 7, "old reserve survives replacement")
	main.call("_purchase_item", "smg")
	host.call("_assert_equal", GameState.player_money, 9750, "duplicate weapon does not charge")
	for item in ["he_grenade", "flash_grenade", "flash_grenade", "smoke_grenade"]:
		main.call("_purchase_item", item)
	host.call(
		"_assert_true",
		not main.call("_purchase_offer", "fire_grenade").success,
		"four grenade capacity prevents a fifth purchase"
	)
	var buy: Control = hud.get_node("HudRoot/BuyMenu")
	hud.call("toggle_player_help")
	host.call("_assert_true", (buy.get("_help_copy") as Control).visible, "buy help expands inline")
	host.call(
		"_assert_true", not bool(hud.call("is_help_open")), "inline help does not stack modal"
	)
	main.call("_set_buy_menu", false)
	hud.call("toggle_player_help")
	host.call(
		"_assert_true", bool(hud.call("is_help_open")), "full help opens outside purchase page"
	)
	host.call(
		"_assert_true",
		not bool(main.get_node("Player").get("controls_enabled")),
		"help releases gameplay controls"
	)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	main.call("_unhandled_input", escape)
	host.call("_assert_true", not bool(hud.call("is_help_open")), "escape closes help first")
	host.call(
		"_assert_equal",
		RoundManager.state,
		RoundManager.RoundState.FREEZE,
		"closing help never pauses match"
	)
	main.call("_on_player_ready")
	host.call(
		"_assert_equal",
		(hud.get("_controls_hint") as Label).text,
		"F1 操作帮助",
		"live combat replaces the buying tutorial with a compact help entry"
	)
	await host.call("_cleanup_main", main)


static func spectator_lifecycle(host: Node) -> void:
	var main: Node3D = host.call("_instantiate_main")
	await host.call("_await_main_ready")
	main.call("_on_team_selected", "CT")
	await main.call("_on_start_pressed")
	var player: CharacterBody3D = main.get_node("Player")
	var watch: Node3D = main.get("spectator")
	for actor in main.get_node("CombatSandbox").get_children():
		actor.set_physics_process(false)
	RoundManager.set_live()
	player.call("apply_explosive_damage", 1000)
	watch.call("tick")
	var snapshot: Dictionary = watch.call("get_snapshot")
	host.call(
		"_assert_true", snapshot.active and snapshot.has_target, "death follows a living teammate"
	)
	var first: CharacterBody3D = watch.get("target")
	host.call("_assert_equal", first.get("team"), "CT", "spectator never selects an enemy")
	host.call(
		"_assert_true",
		not main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel").visible,
		"dead player's weapon must not overlay teammate camera"
	)
	watch.call("cycle", 1)
	host.call("_assert_true", watch.get("target") != first, "next teammate cycles")
	watch.call("toggle_mode")
	host.call(
		"_assert_true",
		bool((watch.call("get_snapshot") as Dictionary).first_person),
		"first-person viewing mode is selectable"
	)
	var second: CharacterBody3D = watch.get("target")
	watch.call("tick")
	var viewed_hands: Node = (watch.get("_view_model") as Node).get("hands")
	host.call(
		"_assert_equal",
		viewed_hands.call("snapshot").appearance,
		second.call("get_combat_snapshot").appearance,
		"spectator hands match target, not local selection"
	)
	second.call("apply_hitscan_damage", 1000, second.global_position, 1.0, false, "T")
	watch.call("tick")
	host.call("_assert_true", watch.get("target") == first, "dead target automatically hands off")
	main.call("_open_menu", false)
	main.call("_resume_game")
	host.call(
		"_assert_true",
		not bool(player.get("controls_enabled")),
		"pause/resume never controls teammate"
	)
	for row in main.call("_build_radar_players"):
		host.call(
			"_assert_true", row.get("team") == "CT", "spectator radar contains no enemy records"
		)
	first.call("apply_hitscan_damage", 1000, first.global_position, 1.0, false, "T")
	watch.call("tick")
	host.call(
		"_assert_true",
		not bool((watch.call("get_snapshot") as Dictionary).has_target),
		"no teammate leaves a waiting camera, never an enemy fallback"
	)
	main.call("_open_menu", false)
	main.call("_return_to_map_selection")
	host.call(
		"_assert_true", not bool(watch.get("active")), "return to maps clears spectator state"
	)
	host.call(
		"_assert_true",
		(player.call("get_camera_node") as Camera3D).current,
		"player camera is restored on spectator exit"
	)
	await host.call("_cleanup_main", main)
