extends SceneTree
## Public flat-floor InputMap/mouse regression; no private map assets required.

var samples: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var rate := int(args[0]) if not args.is_empty() else 60
	Engine.physics_ticks_per_second = rate
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	root.get_node("GameState").call("reset_runtime_state")
	root.get_node("GameState").set("player_spawn", Vector3(0, 0.95, 1))
	root.get_node("GameState").set("player_spawn_yaw_radians", 0.0)
	root.get_node("RoundManager").call("set_warmup")
	var player = load("res://scenes/player/Player.tscn").instantiate()
	player.set_script(load("res://tools/authoring/NativeRoutePlayer.gd"))
	root.add_child(player)
	for frame in range(rate / 2):
		await physics_frame
	player.mouse_capture_enabled = true
	(
		player
		. timeline
		. assign(
			[
				{"at": 0.0, "keys": ["W"], "mouse_dx": 0.0},
				{"at": 0.1, "keys": ["D"], "mouse_dx": 20.0},
				{"at": 0.2, "keys": ["S"], "mouse_dx": -20.0},
				{"at": 0.3, "keys": ["A"], "mouse_dx": 0.0},
				{"at": 0.4, "keys": ["W", "D"], "mouse_dx": 0.0},
				{"at": 0.5, "keys": ["W", "Shift"], "mouse_dx": 0.0},
				{"at": 0.6, "keys": ["W", "Ctrl"], "mouse_dx": 0.0},
				{"at": 0.7, "keys": ["W", "Space"], "mouse_dx": 0.0},
				{"at": 0.8, "keys": ["W"], "mouse_dx": 0.0},
				{"at": 0.9, "keys": [], "mouse_dx": 0.0},
			]
		)
	)
	player.movement_step.connect(func(sample): samples.append(sample.duplicate(true)))
	player.active = true
	player.set_controls_enabled(true)
	for frame in range(rate):
		await physics_frame
	player.set_controls_enabled(false)
	assert(samples.size() == rate)
	var expected := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for index in range(4):
		assert(samples[index * rate / 10].input.direction.is_equal_approx(expected[index]))
	assert(samples[4 * rate / 10].input.direction.is_equal_approx(Vector2(1, -1).normalized()))
	assert(samples[5 * rate / 10].input.walk)
	assert(samples[6 * rate / 10].input.crouch)
	assert(samples[9 * rate / 10].input.direction == Vector2.ZERO)
	var jumps := samples.filter(func(s): return s.input.jump)
	assert(jumps.size() == 1)
	assert(absf(jumps[0].input.sample_time - 0.7) <= 1.0 / rate + 0.000001)
	assert(is_equal_approx(jumps[0].input.requested_jump_time, 0.7))
	assert(player.mouse_events_seen == 2)
	assert(is_equal_approx(player.last_mouse.dx, -20.0))
	assert(absf(player.rotation.y) < 0.00001)
	assert(player.key_events_seen == 18)
	for action in [
		"move_forward", "move_left", "move_backward", "move_right", "jump", "crouch", "walk"
	]:
		assert(not Input.is_action_pressed(action))
	player.queue_free()
	floor_body.queue_free()
	await process_frame
	print("NATIVE_ROUTE_INPUT_OK rate=", rate, " keys=WASD/Space/Ctrl/Shift mouse=unscaled")
	quit(0)
