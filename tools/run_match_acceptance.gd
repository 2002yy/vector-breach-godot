extends SceneTree
## Local full-rule automation: idle human, AI squads, normal C4 and round clocks.
## Usage: godot --headless --fixed-fps 60 --path . --script tools/run_match_acceptance.gd
## -- <map-id> <T|CT> <seed> <evidence-directory>

var _main: Node3D
var _trace: FileAccess
var _seed := 0
var _game: Node
var _round: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(4800.0).timeout.connect(func() -> void: quit(2))
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 16
	_game = root.get_node("GameState")
	_round = root.get_node("RoundManager")
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 4, "map, side, seed and output directory required")
	_seed = int(args[2])
	DirAccess.make_dir_recursive_absolute(args[3])
	_trace = FileAccess.open(args[3] + "/trace.jsonl", FileAccess.WRITE)
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	for frame in range(5):
		await physics_frame
	var option := {
		"id": args[0],
		"name": args[0],
		"preview": "",
		"description": "自动整场验收",
		"recommended_use": "完整规则、静止玩家场景"
	}
	var options: Array = _main.get("level_options")
	options.append(option)
	_main.set("selected_level_index", options.size() - 1)
	_main.get_node("StartMenu").call("set_map_options", options, options.size() - 1)
	_main.call("_on_team_selected", args[1])
	await _main.call("_on_start_pressed")
	assert(_game.match_active and _game.match_team_size == 5)
	var actor_count := 0
	for actor in _main.get_node("CombatSandbox").get_children():
		if actor is CharacterBody3D and actor.has_node("TacticalBotBrain"):
			actor_count += 1
	assert(actor_count == 9, "five versus five requires player and nine actual AI actors")
	_round.round_ended.connect(_round_ended)
	var serial := -1
	var frames := 0
	var start_frame := Engine.get_physics_frames()
	var paused := false
	while _game.match_phase != "complete" and frames < 270000:
		await physics_frame
		frames = Engine.get_physics_frames() - start_frame
		if _round.state == _round.RoundState.FREEZE and _round.round_serial != serial:
			serial = _round.round_serial
			var actors := _main.get_node("CombatSandbox").get_children()
			for actor in actors:
				if not actor is CharacterBody3D or not actor.has_node("TacticalBotBrain"):
					continue
				var rng: RandomNumberGenerator = actor.get_node("TacticalBotBrain").get("_rng")
				rng.seed = _seed + serial * 1009 + absi(String(actor.get("display_name")).hash())
			await physics_frame
			_main.call("_on_player_ready")
			# A stationary human explicitly drops C4 through the game's real G input.
			if _game.player_team == "T" and bool(_main.call("_player_has_c4")):
				_main.get_node("TacticalEquipment").call("select_c4")
				var drop := InputEventAction.new()
				drop.action = "drop_weapon"
				drop.pressed = true
				_main.call("_unhandled_input", drop)
			print("MATCH_ROUND_START ", serial, " ", _game.match_phase)
		if not paused and _round.state == _round.RoundState.LIVE:
			var before: float = _round.time_remaining
			_main.call("_open_menu", false)
			await physics_frame
			await physics_frame
			assert(_round.time_remaining == before, "pause must freeze round clock")
			_main.call("_resume_game")
			paused = true
		if frames % 60 == 0:
			_sample(frames)
	assert(_game.match_phase == "complete", "full match exceeded 4500 simulated seconds")
	var summary_frames := 0
	while not bool(_main.get("menu_open")) and summary_frames < 720:
		await physics_frame
		summary_frames += 1
	assert(bool(_main.get("menu_open")), "completed match must show summary menu")
	assert(not bool(_main.get("spectator").get("active")), "summary must clear spectator")
	var result: Dictionary = _game.get_match_snapshot()
	result["seed"] = _seed
	result["automation"] = "idle human; AI squads; C4 dropped; ready; fixed 60Hz physics"
	result["simulated_seconds"] = float(frames) / 60.0
	result["pause_resume_checked"] = paused
	result["summary_menu_checked"] = true
	result["main_scene_context_checked"] = current_scene == _main
	result["physics_hz"] = Engine.physics_ticks_per_second
	result["process_fps"] = Engine.get_frames_per_second()
	result["process_step_seconds"] = root.get_process_delta_time()
	result["round_records"] = _game.match_rounds
	var file := FileAccess.open(args[3] + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	_trace.flush()
	print(
		"FULL_MATCH_COMPLETE ",
		args[0],
		" ",
		args[1],
		" seed=",
		_seed,
		" rounds=",
		result.regulation_rounds + result.overtime_rounds,
		" score=",
		result.player_score,
		":",
		result.opponent_score
	)
	quit(0)


func _sample(frames: int) -> void:
	var actors: Array = []
	for actor in _main.get_node("CombatSandbox").get_children():
		if not actor is CharacterBody3D or not actor.has_method("get_combat_snapshot"):
			continue
		var snapshot: Dictionary = actor.call("get_combat_snapshot")
		assert(int(snapshot.ai.money) >= 0 and int(snapshot.ai.money) <= 16000)
		actors.append(snapshot)
	_trace.store_line(
		JSON.stringify(
			{
				"frame": frames,
				"serial": _round.round_serial,
				"round": _round.get_objective_snapshot(),
				"round_state": _round.get_state_name(),
				"round_seconds": _round.time_remaining,
				"c4_state": _main.get_node("C4Device").get("device_state"),
				"c4_position": _main.get_node("C4Device").global_position,
				"active_grenade_effects": get_nodes_in_group("grenade_projectiles").size(),
				"fire_zones": get_nodes_in_group("fire_areas").size(),
				"smoke_volumes": get_nodes_in_group("smoke_volumes").size(),
				"actors": actors,
				"player_dead": _main.get_node("Player").get("is_dead"),
				"spectator": _main.get("spectator").call("get_snapshot")
			}
		)
	)
	_trace.flush()


func _round_ended(winner: String, reason: String) -> void:
	_trace.store_line(
		JSON.stringify(
			{
				"event": "round_ended",
				"serial": _round.round_serial,
				"winner": winner,
				"reason": reason,
				"remaining": _round.time_remaining
			}
		)
	)
	print("MATCH_ROUND_END ", _round.round_serial, " ", winner, " ", reason)
