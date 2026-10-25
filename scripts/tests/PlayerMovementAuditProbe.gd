extends Node

var player: CharacterBody3D
var rate := 60
var report := {}
var actions := [
	"move_forward", "move_backward", "move_left", "move_right", "jump", "crouch", "walk"
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "user://player-movement-audit.json"
	if "--rate" in args:
		rate = int(args[args.find("--rate") + 1])
	if "--out" in args:
		out = args[args.find("--out") + 1]
	assert(rate in [60, 120])
	Engine.physics_ticks_per_second = rate
	GameState.reset_runtime_state()
	GameState.player_spawn = Vector3(0, 0.91, 0)
	RoundManager.set_warmup()
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	collision.shape = box
	floor_body.position.y = -0.1
	floor_body.add_child(collision)
	add_child(floor_body)
	player = preload("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	report["physics_hz"] = rate
	report["parameters"] = {}
	for key in [
		"gravity",
		"run_speed",
		"quiet_walk_speed",
		"crouch_speed",
		"jump_velocity",
		"crouch_jump_velocity",
		"acceleration",
		"deceleration",
		"ground_friction",
		"stop_speed",
		"air_acceleration",
		"air_speed_cap",
		"max_step_height"
	]:
		report.parameters[key] = player.get(key)
	report["runs"] = {}
	for kind in ["pistol", "primary", "knife", "walk", "crouch", "diagonal"]:
		report.runs[kind] = await _run_speed(kind)
	report["jump"] = await _jump(false, false, false)
	report["crouch_jump"] = await _jump(true, false, false)
	report["running_jump"] = await _jump(false, true, false)
	report["release_on_jump"] = await _jump(false, true, true)
	report["solver"] = _solver()
	await _reset()
	player.call("apply_hitscan_damage", 1, player.global_position, 1.0)
	report["tagging"] = {"standing": player.call("resolve_move_speed", false)}
	player.set("is_crouching", true)
	report.tagging["crouching"] = player.call("resolve_move_speed", false)
	for action in actions:
		Input.action_release(action)
	player.queue_free()
	floor_body.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	var file := FileAccess.open(out, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	print("PLAYER_MOVEMENT_AUDIT_OK ", out)
	get_tree().quit()


func _reset(slot: int = 1) -> void:
	for action in actions:
		Input.action_release(action)
	GameState.current_weapon_slot = slot
	GameState.player_health = 100
	GameState.player_armor = 0
	player.call("reset_to_spawn")
	player.call("set_controls_enabled", true)
	for frame in range(10):
		await get_tree().physics_frame
	assert(player.is_on_floor())


func _run_speed(kind: String) -> Dictionary:
	await _reset(0 if kind == "primary" else (2 if kind == "knife" else 1))
	if kind in ["walk", "crouch"]:
		Input.action_press(kind)
	Input.action_press("move_forward")
	if kind == "diagonal":
		Input.action_press("move_right")
	for frame in range(rate / 2):
		await get_tree().physics_frame
	var start := player.global_position
	for frame in range(rate):
		await get_tree().physics_frame
	return {
		"speed": Vector2(player.velocity.x, player.velocity.z).length(),
		"distance_1s": start.distance_to(player.global_position)
	}


func _jump(crouch: bool, running: bool, release: bool) -> Dictionary:
	await _reset()
	if crouch:
		Input.action_press("crouch")
	if running:
		Input.action_press("move_forward")
	for frame in range(rate / 2):
		await get_tree().physics_frame
	var start := player.global_position
	if release:
		Input.action_release("move_forward")
	Input.action_press("jump")
	var apex := start.y
	var seen_air := false
	var launch := 0.0
	var first_air_speed := 0.0
	var frames := 0
	var first_frames: Array[Dictionary] = []
	for frame in range(rate * 3):
		await get_tree().physics_frame
		frames += 1
		if frame < 8:
			(
				first_frames
				. append(
					{
						"sample": frames,
						"grounded": player.is_on_floor(),
						"height": player.global_position.y - start.y,
						"vertical_speed": player.velocity.y,
						"horizontal_speed": Vector2(player.velocity.x, player.velocity.z).length(),
					}
				)
			)
		apex = maxf(apex, player.global_position.y)
		launch = maxf(launch, player.velocity.y)
		if not player.is_on_floor() and not seen_air:
			first_air_speed = Vector2(player.velocity.x, player.velocity.z).length()
		seen_air = seen_air or not player.is_on_floor()
		if seen_air and player.is_on_floor():
			break
	assert(seen_air and player.is_on_floor())
	var landed_at := player.global_position
	var bounced := false
	for frame in range(rate / 2):
		await get_tree().physics_frame
		bounced = bounced or not player.is_on_floor()
	return {
		"apex_rise": apex - start.y,
		"command_to_land_s": float(frames) / rate,
		"first_frames": first_frames,
		"launch_y": launch,
		"first_air_speed": first_air_speed,
		"distance": Vector2(landed_at.x - start.x, landed_at.z - start.z).length(),
		"held_jump_rejumped": bounced
	}


func _solver() -> Dictionary:
	var result := {}
	for kind in ["accelerate", "release", "counter"]:
		var velocity := Vector3.ZERO if kind == "accelerate" else Vector3(6.2, 0, 0)
		var direction := (
			Vector3.RIGHT
			if kind == "accelerate"
			else (Vector3.LEFT if kind == "counter" else Vector3.ZERO)
		)
		for frame in range(rate * 2):
			player.velocity = velocity
			velocity = player.call(
				"simulate_tactical_horizontal_velocity", velocity, direction, 6.2, true, 1.0 / rate
			)
			if (
				(kind == "accelerate" and velocity.x >= 6.2 * 0.95)
				or (kind == "release" and velocity.length() <= 0.05)
				or (kind == "counter" and velocity.x <= 0)
			):
				result[kind + "_s"] = float(frame + 1) / rate
				break
	player.velocity = Vector3(6.2, 0, 0)
	result["air_side_first_tick"] = (
		(
			player.call(
				"simulate_tactical_horizontal_velocity",
				player.velocity,
				Vector3.FORWARD,
				6.2,
				false,
				1.0 / rate
			)
			as Vector3
		)
		. z
	)
	result["air_overspeed_no_input"] = (
		(
			player.call(
				"simulate_tactical_horizontal_velocity",
				Vector3(8, 0, 0),
				Vector3.ZERO,
				6.2,
				false,
				1.0 / rate
			)
			as Vector3
		)
		. length()
	)
	result["air_overspeed_side_input"] = (
		(
			player.call(
				"simulate_tactical_horizontal_velocity",
				Vector3(8, 0, 0),
				Vector3.FORWARD,
				6.2,
				false,
				1.0 / rate
			)
			as Vector3
		)
		. length()
	)
	return result
