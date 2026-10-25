extends SceneTree
## Public flat calibration only; never a substitute for map qualification.

var samples: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 3)
	var physics_hz := int(args[0])
	var process_hz := int(args[1])
	Engine.physics_ticks_per_second = physics_hz
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	root.get_node("GameState").call("reset_runtime_state")
	root.get_node("GameState").set("player_spawn", Vector3(0, 0.95, 1))
	root.get_node("GameState").set("player_spawn_yaw_radians", 0.0)
	root.get_node("RoundManager").call("set_warmup")
	var player = load("res://scenes/player/Player.tscn").instantiate()
	player.set_script(load("res://tools/authoring/QueueCadenceProbePlayer.gd"))
	root.add_child(player)
	for frame in range(physics_hz / 2):
		await physics_frame
	player.queued_input = true
	player.mouse_capture_enabled = true
	(
		player
		. timeline
		. assign(
			[
				{"at": 0.0, "keys": ["W"], "mouse_dx": 0.0},
				{"at": 0.2, "keys": ["W", "Space"], "mouse_dx": 0.0},
				{"at": 0.25, "keys": ["W"], "mouse_dx": 0.0},
				{"at": 0.3, "keys": ["D"], "mouse_dx": 20.0},
				{"at": 0.6, "keys": [], "mouse_dx": -20.0},
			]
		)
	)
	player.movement_step.connect(
		func(sample):
			samples.append(
				{
					"input": sample.input.duplicate(true),
					"cadence": player.last_cadence.duplicate(true),
					"command": player.last_command.duplicate(true)
				}
			)
	)
	player.active = true
	player.set_controls_enabled(true)
	for frame in range(physics_hz):
		await physics_frame
	player.set_controls_enabled(false)
	var violations := samples.filter(func(s): return s.cadence.violation).size()
	var supported := violations == 0
	assert(samples.size() == physics_hz)
	assert(supported == (process_hz == physics_hz))
	var jumps := samples.filter(func(s): return s.input.jump)
	var mouse_commands := samples.filter(func(s): return not is_zero_approx(s.command.mouse_dx))
	if supported:
		assert(jumps.size() == 1 and absf(jumps[0].input.sample_time - 0.2) < 0.000001)
		assert(mouse_commands.size() == 2)
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	assert(file != null)
	file.store_string(
		JSON.stringify(
			{
				"physics_hz": physics_hz,
				"declared_process_hz": process_hz,
				"supported": supported,
				"violation_samples": violations,
				"native_mouse_events": player.mouse_events_seen,
				"recorded_mouse_commands": mouse_commands.size(),
				"samples": samples
			},
			"\t"
		)
	)
	file.close()
	player.queue_free()
	floor_body.queue_free()
	await process_frame
	print(
		"QUEUED_CADENCE_OBSERVATION_OK supported=",
		supported,
		" process=",
		process_hz,
		" physics=",
		physics_hz
	)
	quit(0)
