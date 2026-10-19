extends RefCounted


static func purchases_and_help(host: Node) -> void:
	var main: Node3D = host.call("_instantiate_main")
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
