extends Node

const Rules = preload("res://scripts/player/ClassicMovementRules.gd")
const TimelinePlayer = preload("res://scripts/tests/MovementTimelinePlayer.gd")
const PLAYER = preload("res://scenes/player/Player.tscn")
const WEAPONS = preload("res://scenes/combat/WeaponSystem.tscn")
const EQUIPMENT = preload("res://scripts/combat/TacticalEquipment.gd")
var failures: Array[String] = []
var traces: Array[Dictionary] = []
var report := {"timelines": [], "responses": []}
var rate := 60


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--rate" in args:
		rate = int(args[args.find("--rate") + 1])
	Engine.physics_ticks_per_second = rate
	_test_speed_contract()
	_test_air_projection()
	await _test_actual_weapon_transitions()
	for scheme in Rules.SCHEMES:
		for release in [false, true]:
			await _test_timeline(scheme, release)
		_test_response_curves(scheme)
	await _test_timeline("current", true, true)
	if "--out" in args:
		var file := FileAccess.open(args[args.find("--out") + 1], FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("CLASSIC_MOVEMENT_OK rate=%d groups=13" % rate)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _test_speed_contract() -> void:
	var current := {"run": 6.2, "walk": 3.2, "crouch": 2.2}
	for scheme in Rules.SCHEMES:
		for weapon in ["rifle", "sniper", "smg", "shotgun", "pistol", "knife"]:
			for scoped in [false, true]:
				for stance in ["run", "walk", "crouch"]:
					var state := {
						"weapon_id": weapon,
						"slot":
						(
							0
							if weapon in ["rifle", "sniper", "smg", "shotgun"]
							else (2 if weapon == "knife" else 1)
						),
						"scoped": scoped,
						"walking": stance == "walk",
						"crouching": stance == "crouch",
						"tagging": 1.0,
						"water": 1.0
					}
					var normal := Rules.speed_limit(scheme, state, current)
					state.tagging = 0.48
					_check(
						is_equal_approx(Rules.speed_limit(scheme, state, current), normal * 0.48),
						"tag bypass %s/%s/%s" % [scheme, weapon, stance]
					)
					state.water = 0.52
					_check(
						is_equal_approx(
							Rules.speed_limit(scheme, state, current), normal * 0.48 * 0.52
						),
						"water must compose with tagging"
					)
	var sniper := {
		"weapon_id": "sniper",
		"slot": 0,
		"scoped": true,
		"walking": false,
		"crouching": false,
		"tagging": 1.0,
		"water": 1.0
	}
	_check(
		is_equal_approx(Rules.speed_limit("modern_cs", sniper, current), 2.54),
		"modern scoped AWP must be 100 u/s"
	)
	_check(
		is_equal_approx(Rules.speed_limit("legacy_16", sniper, current), 3.81),
		"legacy scoped AWP must be 150 u/s"
	)
	_check(
		is_equal_approx(Rules.speed_limit("current", sniper, current), 5.828),
		"Current numeric baseline must remain"
	)


func _test_air_projection() -> void:
	for scheme in ["legacy_16", "modern_cs"]:
		var config := Rules.parameters(scheme)
		var velocity := Vector3(8, 0, 0)
		_check(
			Rules.air_step(velocity, Vector3.ZERO, 6.2, config, 1.0 / rate) == velocity,
			"air coast must preserve overspeed"
		)
		var turned := Rules.air_step(velocity, Vector3.FORWARD, 6.2, config, 1.0 / rate)
		_check(
			is_equal_approx(turned.x, 8.0) and turned.z < 0.0,
			"air side input must not clamp total speed"
		)
		for tick in range(rate):
			velocity = Rules.air_step(velocity, Vector3.FORWARD, 6.2, config, 1.0 / rate)
		_check(absf(velocity.z) <= 30.0 * Rules.UNIT + 0.0001, "air projection must respect cap")


func _fixture(with_weapons: bool = false) -> Node3D:
	GameState.reset_runtime_state()
	GameState.player_spawn = Vector3(0, 0.91, 0)
	RoundManager.set_warmup()
	var world := Node3D.new()
	add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	if with_weapons:
		var weapons := WEAPONS.instantiate()
		weapons.name = "WeaponSystem"
		world.add_child(weapons)
		weapons.configure_default_loadout()
	var player := PLAYER.instantiate()
	player.set_script(TimelinePlayer)
	player.name = "Player"
	world.add_child(player)
	return world


func _test_actual_weapon_transitions() -> void:
	var world := _fixture(true)
	var player = world.get_node("Player")
	var weapons = world.get_node("WeaponSystem")
	await get_tree().physics_frame
	_check(player.movement_scheme == "current", "fresh player must default to Current")
	_check(not player.set_movement_scheme("invalid"), "invalid scheme must be rejected")
	player.set_movement_scheme("modern_cs")
	weapons.purchase_weapon("sniper")
	weapons.toggle_scope(player)
	_check(
		is_equal_approx(player.resolve_final_move_speed(false), 2.54),
		"actual scope state must reach speed resolver"
	)
	player.apply_hitscan_damage(1, player.global_position, 1.0)
	_check(is_equal_approx(player.resolve_final_move_speed(false), 2.54 * 0.48), "scoped tagging")
	weapons.cancel_scope()
	_check(
		is_equal_approx(player.resolve_final_move_speed(false), 5.08 * 0.48),
		"unscoping must preserve tagging"
	)
	weapons.purchase_weapon("smg")
	_check(
		is_equal_approx(player.resolve_final_move_speed(false), 6.096 * 0.48),
		"switching guns must preserve tagging"
	)
	player.is_crouching = true
	_check(
		is_equal_approx(player.resolve_final_move_speed(true), 6.096 * 0.34 * 0.48),
		"crouch wins over walk and preserves tagging"
	)
	player.set_movement_scheme("current")
	_check(
		is_equal_approx(player.resolve_move_speed(false), 2.2 * 0.48),
		"Current crouch tag bug fixed"
	)
	var equipment := EQUIPMENT.new()
	world.add_child(equipment)
	player.is_crouching = false
	equipment.select_knife()
	_check(
		is_equal_approx(player.resolve_final_move_speed(false), 6.448 * 0.48),
		"Current knife must override the holstered gun context and preserve tagging"
	)
	player.set_movement_scheme("modern_cs")
	_check(
		is_equal_approx(player.resolve_final_move_speed(false), 6.35 * 0.48), "modern knife tagging"
	)
	equipment.select_c4()
	_check(is_equal_approx(player.resolve_final_move_speed(false), 6.35 * 0.48), "C4 tagging")
	equipment.purchase_grenade("he_grenade")
	equipment.select_next_grenade()
	_check(is_equal_approx(player.resolve_final_move_speed(false), 6.35 * 0.48), "grenade tagging")
	world.queue_free()
	await get_tree().process_frame


func _capture_step(sample: Dictionary) -> void:
	var position: Vector3 = sample.position
	var velocity: Vector3 = sample.velocity
	traces.append(
		{
			"time": sample.input.sample_time,
			"requested_jump_time": sample.input.requested_jump_time,
			"frame": sample.frame,
			"input_event_usec": sample.input_event_usec,
			"consumed_usec": sample.consumed_usec,
			"jumped": sample.jumped,
			"grounded_before": sample.grounded_before,
			"ground_solver": sample.ground_solver,
			"grounded_after": sample.grounded_after,
			"position": [position.x, position.y, position.z],
			"velocity": [velocity.x, velocity.y, velocity.z]
		}
	)


func _test_timeline(scheme: String, release: bool, native_input: bool = false) -> void:
	var world := _fixture()
	var player = world.get_node("Player")
	for tick in range(8):
		await get_tree().physics_frame
	player.set_movement_scheme(scheme)
	var timeline: Array[Dictionary] = [
		{"at": 0.0, "direction": Vector2(0, -1)},
		{"at": 0.5, "jump": true, "direction": Vector2.ZERO if release else Vector2(0, -1)},
		{"at": 0.6, "jump": false}
	]
	player.timeline = timeline
	player.native_input = native_input
	traces = []
	player.movement_step.connect(_capture_step)
	player.active = true
	player.set_controls_enabled(true)
	for tick in range(rate * 2):
		await get_tree().physics_frame
	player.active = false
	player.set_controls_enabled(false)
	var jumps := traces.filter(func(row): return row.jumped)
	_check(jumps.size() == 1, "one input must cause one jump %s" % scheme)
	if jumps.size() == 1:
		var jump: Dictionary = jumps[0]
		var allowed_delay := 1.0 / rate if native_input else 0.0
		_check(
			jump.time >= 0.5 - 0.000001 and jump.time <= 0.5 + allowed_delay + 0.000001,
			"jump consumption must match timeline or one native event-buffer tick"
		)
		_check(not jump.ground_solver and not jump.grounded_after, "takeoff must use air solver")
		if native_input:
			_check(
				jump.input_event_usec > 0 and jump.input_event_usec <= jump.consumed_usec,
				"native event timestamp must precede physics consumption"
			)
		var previous: Dictionary = traces[traces.find(jump) - 1]
		if release:
			_check(
				absf(jump.velocity[2] - previous.velocity[2]) < 0.0001,
				"release+jump must not apply ground friction"
			)
		var landed := traces.filter(func(row): return row.time > 0.5 and row.grounded_after)
		_check(not landed.is_empty(), "jump must land")
		var apex: Dictionary = traces[0]
		for row in traces:
			if row.position[1] > apex.position[1]:
				apex = row
		report.timelines.append(
			{
				"native_input": native_input,
				"scheme": scheme,
				"release": release,
				"rate": rate,
				"apex_time": apex.time,
				"apex_y": apex.position[1],
				"land_time": landed[0].time if not landed.is_empty() else -1.0,
				"trace": traces.duplicate(true)
			}
		)
	for action in ["move_forward", "jump", "crouch", "walk"]:
		Input.action_release(action)
	world.queue_free()
	await get_tree().process_frame


func _test_response_curves(scheme: String) -> void:
	var player = PLAYER.instantiate()
	player.set_movement_scheme(scheme)
	for kind in ["release", "reverse", "air_turn"]:
		var velocity := Vector3(6.2, 0, 0)
		var position := Vector3.ZERO
		var points: Array[Dictionary] = []
		var zero_time := -1.0
		var reverse_95_time := -1.0
		for tick in range(rate):
			var direction := (
				Vector3.ZERO
				if kind == "release"
				else (Vector3.LEFT if kind == "reverse" else Vector3.FORWARD)
			)
			player.velocity = velocity
			velocity = player.simulate_tactical_horizontal_velocity(
				velocity, direction, 6.2, kind != "air_turn", 1.0 / rate
			)
			position += velocity / rate
			var time := float(tick + 1) / rate
			if (
				zero_time < 0.0
				and (velocity.length() <= 0.05 if kind == "release" else velocity.x <= 0.0)
			):
				zero_time = time
			if reverse_95_time < 0.0 and velocity.x <= -6.2 * 0.95:
				reverse_95_time = time
			points.append(
				{
					"time": time,
					"velocity": [velocity.x, velocity.z],
					"position": [position.x, position.z]
				}
			)
		_check(velocity.is_finite(), "solver must remain finite")
		if kind != "air_turn":
			_check(zero_time > 0.0, "ground motion must stop or reverse")
		if kind == "reverse":
			_check(reverse_95_time > zero_time, "180-degree reversal needs post-stop acceleration")
		report.responses.append(
			{
				"scheme": scheme,
				"rate": rate,
				"kind": kind,
				"zero_time": zero_time,
				"reverse_95_time": reverse_95_time,
				"points": points
			}
		)
	player.free()
