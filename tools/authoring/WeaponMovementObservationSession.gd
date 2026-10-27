extends "res://tools/authoring/CurrentMovementObservationSession.gd"
## Author-only real equipment context. Never replaces production movement rules.

signal physics_clock_ready

var weapons: Node
var equipment: Node
var weapon_title := ""
var base_camera_fov := 75.0
var seen_weapon_states := {}
var saw_actual_jump := false
var peak_horizontal_speed := 0.0
var requested_rate := 60
var clock_started := false
var clock_ready := false
var clock_stable_ticks := 0
var startup_deltas: Array[float] = []


func _start() -> void:
	clock_started = true
	await physics_clock_ready
	super._start()
	if not ready_to_record:
		return
	base_camera_fov = player.get_camera_node().fov
	weapons = load("res://scenes/combat/WeaponSystem.tscn").instantiate()
	weapons.name = "WeaponSystem"
	world.add_child(weapons)
	equipment = load("res://scripts/combat/TacticalEquipment.gd").new()
	equipment.name = "TacticalEquipment"
	world.add_child(equipment)
	weapons.configure_default_loadout()
	_select_observation_weapon("sniper")
	weapon_title = label.text + "\n作者装备：1 AWP / 2 AK / 3 刀；右键真实开关镜；不含实战射击验收"
	label.text = weapon_title


func _reset_attempt(reason: String) -> void:
	if is_instance_valid(weapons):
		weapons.cancel_scope()
		_select_observation_weapon("sniper")
	super._reset_attempt(reason)
	current_attempt["physics_timing"] = {
		"requested_rate": requested_rate,
		"startup_frames_without_player": startup_deltas.size(),
		"startup_deltas": startup_deltas.duplicate(),
		"stable_ticks_before_player": clock_stable_ticks,
	}
	weapon_title = label.text + "\n作者装备：1 AWP / 2 AK / 3 刀；右键真实开关镜；不含实战射击验收"
	label.text = weapon_title


func _select_observation_weapon(weapon_id: String) -> void:
	weapons.cancel_scope()
	if weapon_id == "knife":
		equipment.select_knife()
	else:
		equipment.select_firearm()
		assert(weapons.purchase_weapon(weapon_id))
		weapons.refresh_equipped_hud()


func _input(event: InputEvent) -> void:
	if ready_to_record and is_instance_valid(weapons) and player.controls_enabled:
		if event.is_action_pressed("fire_secondary") and equipment.equipped == "firearm":
			weapons.toggle_scope(player)
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1:
					_select_observation_weapon("sniper")
				KEY_2:
					_select_observation_weapon("rifle")
				KEY_3:
					_select_observation_weapon("knife")
	super._input(event)


func _record(sample: Dictionary) -> void:
	if not _valid_physics_delta(float(sample.delta)):
		return
	super._record(sample)
	if not ready_to_record or not is_instance_valid(weapons) or current_attempt.trace.is_empty():
		return
	var context: Dictionary = weapons.get_movement_context()
	if GameState.current_weapon_slot == 2:
		context = {"weapon_id": "knife", "slot": 2, "scoped": false}
	(
		context
		. merge(
			{
				"speed_limit": player.resolve_final_move_speed(bool(sample.input.walk)),
				"horizontal_speed": Vector2(sample.velocity.x, sample.velocity.z).length(),
				"camera_fov": player.get_camera_node().fov,
				"camera_base_fov": base_camera_fov,
				"equipped": String(equipment.equipped),
				"walking": bool(sample.input.walk),
				"crouching": bool(player.is_crouching),
			}
		)
	)
	current_attempt.trace[-1]["weapon_context"] = context
	saw_actual_jump = saw_actual_jump or bool(sample.jumped)
	peak_horizontal_speed = maxf(peak_horizontal_speed, float(context.horizontal_speed))
	var state_key := (
		"%s/%s/%s/%s" % [context.weapon_id, context.scoped, context.walking, context.crouching]
	)
	seen_weapon_states[state_key] = true
	label.text = (
		weapon_title
		+ (
			"\n实际：%s / scoped=%s / 上限 %.3fm/s / 当前 %.3fm/s / FOV %.1f"
			% [
				context.weapon_id,
				context.scoped,
				context.speed_limit,
				context.horizontal_speed,
				context.camera_fov
			]
		)
	)


func _physics_process(delta: float) -> void:
	if clock_started and not clock_ready:
		if Engine.physics_ticks_per_second != requested_rate:
			push_error("Requested physics rate changed during startup")
			get_tree().quit(1)
			return
		startup_deltas.append(delta)
		if absf(delta - 1.0 / requested_rate) <= 0.000000001:
			clock_stable_ticks += 1
		else:
			clock_stable_ticks = 0
		if clock_stable_ticks >= 3:
			clock_ready = true
			physics_clock_ready.emit()
		elif startup_deltas.size() >= 120:
			push_error("Physics startup clock did not stabilize")
			get_tree().quit(1)
		return
	if not ready_to_record or saved or not is_instance_valid(weapons):
		return
	if not _valid_physics_delta(delta):
		return
	equipment.tick(delta)
	if equipment.equipped == "firearm":
		weapons.tick(delta, false, false, player)
	if not smoke:
		return
	smoke_ticks += 1
	# All three postures see real AWP unscoped/scoped contexts. No manual injection.
	var events := {
		2: [KEY_W, true],
		10: [MOUSE_BUTTON_RIGHT, true],
		20: [MOUSE_BUTTON_RIGHT, true],
		24: [KEY_SHIFT, true],
		34: [MOUSE_BUTTON_RIGHT, true],
		44: [MOUSE_BUTTON_RIGHT, true],
		48: [KEY_SHIFT, false],
		50: [KEY_CTRL, true],
		60: [MOUSE_BUTTON_RIGHT, true],
		70: [MOUSE_BUTTON_RIGHT, true],
		74: [KEY_CTRL, false],
		80: [KEY_2, true],
		90: [KEY_3, true],
		100: [KEY_1, true],
		110: [KEY_W, false],
		115: [KEY_F5, true],
		135: [KEY_SPACE, true],
		136: [KEY_SPACE, false],
		195: [KEY_F6, true],
		200: [KEY_ESCAPE, true],
		205: [KEY_F4, true],
		220: [KEY_F8, true]
	}
	if smoke_ticks in events:
		_emit_observation_input(int(events[smoke_ticks][0]), bool(events[smoke_ticks][1]))


func _emit_observation_input(code: int, pressed: bool) -> void:
	if code == MOUSE_BUTTON_RIGHT:
		for down in [true, false]:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_RIGHT
			mouse.pressed = down
			Input.parse_input_event(mouse)
	else:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		if code in [KEY_1, KEY_2, KEY_3, KEY_F5, KEY_F6, KEY_ESCAPE, KEY_F4, KEY_F8]:
			var release := event.duplicate() as InputEventKey
			release.pressed = false
			Input.parse_input_event(release)
	Input.flush_buffered_events()


func _finish() -> void:
	if smoke:
		for crouching in [false, true]:
			for scoped in [false, true]:
				if not _require_smoke_state("sniper/%s/false/%s" % [scoped, crouching]):
					return
		for scoped in [false, true]:
			if not _require_smoke_state("sniper/%s/true/false" % scoped):
				return
		for state in ["rifle/false/false/false", "knife/false/false/false"]:
			if not _require_smoke_state(state):
				return
		if not saw_actual_jump or peak_horizontal_speed <= 0.01:
			push_error("Weapon smoke missing actual movement or actual jump")
			get_tree().quit(1)
			return
	super._finish()


func _require_smoke_state(state: String) -> bool:
	if not seen_weapon_states.has(state):
		push_error("Weapon smoke missing context: " + state)
		get_tree().quit(1)
		return false
	return true


func _valid_physics_delta(delta: float) -> bool:
	if (
		Engine.physics_ticks_per_second != requested_rate
		or absf(delta - 1.0 / requested_rate) > 0.000000001
	):
		push_error("Physics rate/delta changed after author startup warmup")
		get_tree().quit(1)
		return false
	return true
