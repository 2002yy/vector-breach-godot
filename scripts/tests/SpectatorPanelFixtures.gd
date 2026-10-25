extends RefCounted


static func run(host: Node) -> void:
	var main: Node3D = host._instantiate_main(false)
	main.call("_on_map_selected", main.call("find_level_option_index", "gatehouse"))
	main.call("_on_team_selected", "T")
	main.call("_on_start_pressed")
	while main.get("_starting"):
		await host.get_tree().process_frame
	main.call("_set_buy_menu", false)
	for actor in main.get_node("CombatSandbox").get_children():
		actor.set_physics_process(false)
		actor.get_node("TacticalBotBrain").process_mode = Node.PROCESS_MODE_DISABLED
	RoundManager.set_live()
	var player: CharacterBody3D = main.get_node("Player")
	player.call("apply_explosive_damage", 1000)
	var watch: Node = main.get("spectator")
	watch.call("tick")
	main.call("_update_ui", true)
	var hud := main.get_node("CombatHud")
	var panel: PanelContainer = hud.get("_spectator_panel")
	var alive: Array = watch.call("teammates")
	var snapshot: Dictionary = watch.call("get_snapshot")
	host._assert_equal(snapshot.teammates.size(), 2, "roster contains only the two alive allies")
	host._assert_true(panel.is_visible_in_tree(), "death presents new spectator panel")
	host._assert_true(
		not hud.get("_objective_hint").visible, "no duplicate objective text over panel"
	)
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_2
	main.call("_unhandled_input", event)
	host._assert_equal(watch.get("target"), alive[1], "number key selects displayed second ally")
	watch.call("tick")
	main.call("_update_ui", true)
	host._assert_true(
		panel.get("title").text.contains(alive[1].display_name), "target identity follows input"
	)
	host._assert_equal(
		(watch.call("get_snapshot") as Dictionary).teammates[1].selected,
		true,
		"roster highlights selected teammate"
	)
	event.keycode = KEY_4
	main.call("_unhandled_input", event)
	host._assert_equal(
		watch.get("target"), alive[1], "unavailable number leaves current ally intact"
	)
	main.call("_open_menu", false)
	event.keycode = KEY_1
	main.call("_unhandled_input", event)
	host._assert_equal(watch.get("target"), alive[1], "menu blocks teammate selection")
	main.call("_resume_game")
	hud.call("toggle_player_help")
	main.call("_unhandled_input", event)
	host._assert_equal(watch.get("target"), alive[1], "help blocks teammate selection")
	hud.call("toggle_player_help")
	alive[1].call("apply_hitscan_damage", 1000, alive[1].global_position, 1.0, false, "CT")
	watch.call("tick")
	main.call("_update_ui", true)
	host._assert_equal(watch.get("target"), alive[0], "dead target automatically hands off")
	host._assert_equal(
		(watch.call("get_snapshot") as Dictionary).teammates.size(), 1, "dead row retires"
	)
	host._assert_true(
		panel.get("status").text.contains("最后一名"), "last ally receives clutch hierarchy"
	)
	main.get_node("C4Device").call("plant_at", player.global_position, "A")
	# The previous carrier died; model the surviving ally recovering and planting C4.
	RoundManager.bomb_carried = true
	host._assert_true(RoundManager.plant_bomb("A"), "remaining ally commits planted C4")
	alive[0].call("apply_hitscan_damage", 1000, alive[0].global_position, 1.0, false, "CT")
	watch.call("tick")
	main.call("_check_team_elimination")
	main.call("_update_ui", true)
	host._assert_equal(
		RoundManager.state, RoundManager.RoundState.BOMB_PLANTED, "bomb outlives attackers"
	)
	host._assert_true(
		panel.get("title").text.contains("无存活队友"), "empty roster has clear waiting state"
	)
	host._assert_true(
		panel.get("status").text.contains("C4"), "waiting state retains planted timer"
	)
	host._assert_true(not panel.get("roster").visible, "empty roster hides stale teammate slots")
	host._assert_true(
		not panel.get("controls").text.contains("选择队友"), "empty state offers valid controls"
	)
	GameState.opponent_squad_score = 6
	RoundManager.defuse_bomb()
	main.call("_update_ui", true)
	host._assert_true(
		panel.get("status").text.contains("赛果"), "last round does not promise another round"
	)
	host._assert_true(
		not hud.get_node("HudRoot/TrainingEnd/Margin/Stack/Hint").text.contains("下一回合"),
		"terminal result footer agrees with spectator status"
	)
	RoundManager.call("_process", RoundManager.round_end_duration + 0.1)
	host._assert_true(not panel.is_visible_in_tree(), "match summary clears spectator presentation")
	host._assert_true(not watch.get("active"), "terminal transition releases spectator owner")
	await host._cleanup_main(main)
