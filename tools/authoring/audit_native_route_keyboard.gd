extends "res://tools/authoring/audit_mirage_route_inputs.gd"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 3 and args[0] in ["discover", "replay"])
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	rate = int(args[3]) if args.size() > 3 else 60
	Engine.physics_ticks_per_second = rate
	# Headless's tiny backing window otherwise rescales injected mouse deltas.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(
		manifest.level
	)
	var source := String(data.runtime_collision_scene)
	assert(FileAccess.get_sha256(source) == manifest.identity.collision_sha256)
	assert(FileAccess.get_sha256(source + ".import") == manifest.identity.collision_import_sha256)
	assert(
		(
			FileAccess.get_sha256("res://data/levels/%s.json" % manifest.level)
			== manifest.identity.level_sha256
		)
	)
	assert(FileAccess.get_sha256(String(data.match_manifest)) == manifest.identity.layout_sha256)
	assert(Engine.get_version_info().hash == manifest.identity.engine_hash)
	stage = Node3D.new()
	root.add_child(stage)
	var geometry := (load(source) as PackedScene).instantiate()
	collision_root = geometry
	stage.add_child(geometry)
	var builder := (load("res://scenes/level/GrayboxLevel.tscn") as PackedScene).instantiate()
	builder.load_on_ready = false
	stage.add_child(builder)
	builder.call("_build_runtime_collision", geometry, true, true, source)
	for frame in range(5):
		await physics_frame
	space = stage.get_world_3d().direct_space_state
	var output := {
		"schema": 4,
		"formal_qualification": false,
		"level": manifest.level,
		"identity": manifest.identity,
		"manifest_sha256": FileAccess.get_sha256(args[1]),
		"physics_hz": rate,
		"feedback": args[0] == "discover",
		"results": [],
		"runtime_sha256": {},
		"input_map_sha256": FileAccess.get_sha256("res://project.godot")
	}
	for path in [
		"res://scripts/player/PlayerController.gd",
		"res://scripts/player/ClassicMovementRules.gd",
		"res://tools/authoring/NativeRoutePlayer.gd"
	]:
		output.runtime_sha256[path] = FileAccess.get_sha256(path)
	if args[0] == "discover":
		feedback_route.clear()
		for position in manifest.route_waypoints:
			feedback_route.append(Survey.vector(position))
		discovering = true
		var point: Dictionary = (
			manifest.cases.filter(func(p): return p.id == "run_up")[0].duplicate(true)
		)
		point.duration = 12.0
		for scheme in ["current", "legacy_16", "modern_cs"]:
			for mode in ["no_jump", "walk"]:
				output.results.append(await _trial(point, scheme, mode))
	else:
		assert(manifest.schema == 4 and manifest.formal_qualification == false)
		for point in manifest.cases:
			output.results.append(await _trial(point, point.scheme, point.trial_mode))
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	stage.queue_free()
	await process_frame
	print("NATIVE_ROUTE_KEYBOARD_WRITTEN ", args[2])
	quit(0)


func _trial_script() -> Script:
	return load("res://tools/authoring/NativeRoutePlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, _scheme: String, mode: String
) -> void:
	player.feedback = discovering
	player.feedback_walk = mode == "walk"
	player.waypoints = feedback_route
	# The real mouse handler runs, but the headless fixture does not capture the OS cursor.
	player.mouse_capture_enabled = true
	if not discovering:
		player.timeline.assign(point.native_timeline)


func _record(sample: Dictionary) -> void:
	super._record(sample)
	var row: Dictionary = samples[-1]
	row["native_command"] = trial_player.last_command.duplicate(true)
	row["yaw"] = trial_player.rotation.y
	row["mouse_events_seen"] = trial_player.mouse_events_seen
	row["key_events_seen"] = trial_player.key_events_seen
	row["last_mouse"] = trial_player.last_mouse.duplicate(true)
	row["jump_requested_time"] = sample.input.requested_jump_time
	row["input_event_usec"] = sample.input_event_usec
	row["consumed_usec"] = sample.consumed_usec


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var result: Dictionary = await super._trial(point, scheme, mode)
	# Base runner frees the player after recording. Release through Input before the next trial.
	for key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_CTRL, KEY_SHIFT]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = false
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	var clear := true
	for action in [
		"move_forward", "move_left", "move_backward", "move_right", "jump", "crouch", "walk"
	]:
		clear = clear and not Input.is_action_pressed(action)
	assert(clear)
	result["input_released"] = clear
	result["input_kind"] = "synthetic_key_mouse_InputMap_not_OS_or_human"
	result["feedback"] = discovering
	return result
