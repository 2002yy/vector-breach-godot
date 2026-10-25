extends RefCounted


static func run(host: Node) -> void:
	var main: Node3D = host._instantiate_main(false)
	main.call("_on_map_selected", main.call("find_level_option_index", "gatehouse"))
	main.call("_on_start_pressed")
	while main.get("_starting"):
		await host.get_tree().process_frame
	host._assert_true(main.get("game_started"), "blast fixture starts a real competitive world")
	main.call("_set_buy_menu", false)
	var player: CharacterBody3D = main.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 100, 0)
	var actors := main.get_node("CombatSandbox").get_children()
	var near: CharacterBody3D = actors[0]
	var far: CharacterBody3D = actors[-1]
	for index in range(actors.size()):
		var actor: CharacterBody3D = actors[index]
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.get_node("TacticalBotBrain").process_mode = Node.PROCESS_MODE_DISABLED
		actor.global_position = Vector3(35 + index * 3, 100, 0)
	near.global_position = Vector3(1, 100, 0)
	near.set("current_armor", 0)
	GameState.player_armor = 0
	GameState.player_squad_score = 6
	RoundManager.set_live()
	var c4: Node3D = main.get_node("C4Device")
	c4.call("plant_at", Vector3(0, 99.18, 0), "A")
	RoundManager.plant_bomb("A")
	await host.get_tree().physics_frame
	var far_health := int(far.get("current_health"))
	var settled: Array = []
	var listener := func(_winner: String, _reason: String) -> void:
		settled.append(bool(player.get("is_dead")) and bool(near.get("is_dead")))
	RoundManager.round_ended.connect(listener)
	RoundManager.time_remaining = 0.01
	RoundManager.call("_process", 0.02)
	RoundManager.round_ended.disconnect(listener)
	host._assert_equal(settled, [true], "player and bot blast deaths precede round settlement")
	host._assert_equal(
		int(far.get("current_health")), far_health, "outside blast radius is unharmed"
	)
	host._assert_equal(
		RoundManager.round_reason, "BOMB EXPLODED", "deaths cannot override blast win"
	)
	host._assert_equal(GameState.match_phase, "complete", "blast can end the final match round")
	var effect: Node3D = c4.get_node("ExplosionEffect")
	effect.set_process(false)
	main.call("_update_ui", true)
	var hud := main.get_node("CombatHud")
	host._assert_true(not hud.get("training_end").visible, "initial blast precedes result panel")
	host._assert_true(main.get("spectator").get("active"), "blast death retains spectator flow")
	await host.get_tree().process_frame
	var path := String(main.get("_completed_match_record_path"))
	host._assert_true(not path.is_empty(), "terminal record is exported after blast deaths")
	if not path.is_empty():
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var scoreboard: Dictionary = record.get("scoreboard", {})
		host._assert_equal(
			int(scoreboard.get("你", {}).get("deaths", 0)), 1, "record includes blast death"
		)
	effect.call("_process", 1.3)
	main.call("_update_ui", true)
	host._assert_true(hud.get("training_end").visible, "result appears after initial explosion")
	RoundManager.call("_process", RoundManager.round_end_duration + 0.1)
	host._assert_true(
		not main.get("game_started"), "final round returns to menu after end interval"
	)
	host._assert_true(
		not is_instance_valid(effect), "menu transition frees lingering blast and sound"
	)
	host._assert_true(not main.get("spectator").get("active"), "final summary releases spectator")
	await host._cleanup_main(main)
