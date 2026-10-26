extends Node
## An isolated authoring session. Never writes settings or grants acceptance.

const Survey = preload("res://tools/authoring/ClassicJumpSurvey.gd")
const SCHEMES := ["current", "legacy_16", "modern_cs"]
var manifest_path := ""
var output_path := ""
var smoke := false
var render_smoke := false
var manifest: Dictionary
var points: Array[Dictionary] = []
var case_index := 0
var scheme_index := 0
var player: CharacterBody3D
var world: Node3D
var label: Label
var attempts: Array[Dictionary] = []
var current_attempt := {}
var saved := false
var total_steps := 0
var ready_to_record := false
var smoke_ticks := 0
var goal_marker: MeshInstance3D
var observer_sha256 := ""


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	get_tree().auto_accept_quit = false
	observer_sha256 = FileAccess.get_sha256("res://tools/authoring/JumpPlaytestSession.gd")
	if (
		FileAccess.file_exists(output_path)
		or FileAccess.file_exists(output_path + ".png")
		or output_path == manifest_path
	):
		push_error("Refusing to overwrite existing receipt or source manifest")
		get_tree().quit(1)
		return
	manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	assert(manifest.formal_qualification == false and not manifest.cases.is_empty())
	for path in manifest.runtime_sha256:
		assert(FileAccess.get_sha256(path) == manifest.runtime_sha256[path])
	assert(FileAccess.get_sha256("res://project.godot") == manifest.input_map_sha256)
	assert(
		(
			FileAccess.get_sha256(manifest.identity.collision_path)
			== manifest.identity.collision_sha256
		)
	)
	assert(
		(
			FileAccess.get_sha256(manifest.identity.collision_path + ".import")
			== manifest.identity.collision_import_sha256
		)
	)
	assert(
		(
			FileAccess.get_sha256("res://data/levels/%s.json" % manifest.level)
			== manifest.identity.level_sha256
		)
	)
	assert(Engine.get_version_info().hash == manifest.identity.engine_hash)
	for point in manifest.cases:
		if point.trial_mode == "jump":
			points.append(point)
	assert(not points.is_empty())
	GameState.reset_runtime_state()
	RoundManager.set_warmup()
	world = Node3D.new()
	add_child(world)
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(
		manifest.level
	)
	assert(
		(
			FileAccess.get_sha256(
				String(data.get("match_manifest", "res://data/levels/match-local/dustline.json"))
			)
			== manifest.identity.layout_sha256
		)
	)
	var level = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.load_on_ready = false
	world.add_child(level)
	if smoke and not render_smoke:
		var geometry := (load(manifest.identity.collision_path) as PackedScene).instantiate()
		world.add_child(geometry)
		level.call(
			"_build_runtime_collision", geometry, true, true, manifest.identity.collision_path
		)
	else:
		assert(level.load_level(manifest.level))
		_add_original_lighting(data)
	player = load("res://scenes/player/Player.tscn").instantiate()
	GameState.player_spawn = Survey.vector(points[0].start)
	GameState.player_spawn_yaw_radians = float(points[0].yaw)
	world.add_child(player)
	player.movement_step.connect(_record)
	goal_marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.height = 0.025
	goal_marker.mesh = disc
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(1.0, 0.65, 0.08, 0.2)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	goal_marker.material_override = marker_material
	world.add_child(goal_marker)
	var target_label := Label3D.new()
	target_label.text = "首落目标 · 诊断标记"
	target_label.font_size = 24
	target_label.pixel_size = 0.0015
	target_label.position.y = 0.45
	target_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	goal_marker.add_child(target_label)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	canvas.add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 17)
	panel.add_child(label)
	_reset_attempt("session_start")
	player.set_controls_enabled(true)
	if not smoke:
		player.set_mouse_capture_enabled(true)
	ready_to_record = true


func _add_original_lighting(data: Dictionary) -> void:
	var template = load("res://scenes/Main.tscn").instantiate()
	var environment: WorldEnvironment = template.get_node("WorldEnvironment")
	var sun: DirectionalLight3D = template.get_node("Sun")
	environment.environment = environment.environment.duplicate(true)
	template.set("world_environment", environment)
	template.set("sun", sun)
	template.call("_capture_default_environment")
	template.call("_apply_level_environment", data)
	template.remove_child(environment)
	template.remove_child(sun)
	environment.owner = null
	sun.owner = null
	world.add_child(environment)
	world.add_child(sun)
	template.free()


func _input(event: InputEvent) -> void:
	if not ready_to_record or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			player.set_mouse_capture_enabled(false)
			player.set_controls_enabled(false)
		KEY_F4:
			player.set_controls_enabled(true)
			if not smoke:
				player.set_mouse_capture_enabled(true)
		KEY_F5:
			_reset_attempt("retry")
		KEY_F6:
			case_index = (case_index + 1) % points.size()
			_reset_attempt("next_case")
		KEY_F7:
			scheme_index = (scheme_index + 1) % SCHEMES.size()
			_reset_attempt("next_scheme")
		KEY_F8:
			_finish()


func _reset_attempt(reason: String) -> void:
	if not current_attempt.is_empty():
		attempts.append(current_attempt)
	var point: Dictionary = points[case_index]
	GameState.player_spawn = Survey.vector(point.start)
	GameState.player_spawn_yaw_radians = float(point.yaw)
	player.reset_to_spawn()
	player.set_movement_scheme(SCHEMES[scheme_index])
	goal_marker.global_position = Survey.vector(point.target_feet) + Vector3.UP * 0.04
	var disc := goal_marker.mesh as CylinderMesh
	disc.top_radius = float(point.target_radius)
	disc.bottom_radius = float(point.target_radius)
	current_attempt = {
		"case": point.parent_case,
		"scheme": SCHEMES[scheme_index],
		"reason": reason,
		"human_review": "pending",
		"trace": []
	}
	label.text = (
		"\n".join(
			[
				"跳点观察 · %s",
				"%s · %s",
				"WASD / 鼠标 / 空格 / Ctrl / Shift",
				"F5 重试   F6 下一点   F7 切方案",
				"F8 保存并退出   Esc 释放鼠标   F4 继续",
				"观察用记录；不会自动判为人工验收通过"
			]
		)
		% [manifest.level, point.parent_case, SCHEMES[scheme_index]]
	)


func _record(sample: Dictionary) -> void:
	if not ready_to_record:
		return
	total_steps += 1
	if current_attempt.trace.size() < 7200:
		current_attempt.trace.append(
			{
				"physics_frame": sample.frame,
				"delta": sample.delta,
				"input_event_usec": sample.input_event_usec,
				"consumed_usec": sample.consumed_usec,
				"direction": [sample.input.direction.x, sample.input.direction.y],
				"jump_requested": sample.input.jump,
				"crouch_requested": sample.input.crouch,
				"walk_requested": sample.input.walk,
				"jumped": sample.jumped,
				"grounded_before": sample.grounded_before,
				"grounded": sample.grounded_after,
				"capsule_height": player.get_node("CollisionShape3D").shape.height,
				"position": Survey.array(sample.position),
				"velocity": Survey.array(sample.velocity)
			}
		)
	else:
		current_attempt["trace_truncated"] = true


func _physics_process(_delta: float) -> void:
	if not smoke or not ready_to_record or saved:
		return
	smoke_ticks += 1
	var posture := {
		30: [KEY_CTRL, true], 32: [KEY_CTRL, false], 34: [KEY_SHIFT, true], 36: [KEY_SHIFT, false]
	}
	if smoke_ticks in posture:
		var pose_event := InputEventKey.new()
		pose_event.keycode = posture[smoke_ticks][0]
		pose_event.physical_keycode = posture[smoke_ticks][0]
		pose_event.pressed = posture[smoke_ticks][1]
		Input.parse_input_event(pose_event)
		Input.flush_buffered_events()
	var actions := {5: KEY_F7, 10: KEY_F5, 15: KEY_F6, 20: KEY_ESCAPE, 25: KEY_F4, 40: KEY_F8}
	if smoke_ticks in actions:
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = actions[smoke_ticks]
			event.physical_keycode = actions[smoke_ticks]
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and ready_to_record:
		_finish()


func _finish() -> void:
	if saved or not ready_to_record:
		return
	ready_to_record = false
	player.set_controls_enabled(false)
	player.set_mouse_capture_enabled(false)
	if render_smoke:
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(output_path + ".png") == OK)
	assert(not FileAccess.file_exists(output_path))
	attempts.append(current_attempt)
	var receipt := {
		"schema": 1,
		"human_review": "pending",
		"formal_release_ready": false,
		"session_mode":
		(
			(
				"windowed_automated_render_smoke"
				if render_smoke
				else "headless_collision_logic_smoke"
			)
			if smoke
			else "windowed_manual_unreviewed"
		),
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"manifest_sha256": FileAccess.get_sha256(manifest_path),
		"engine_hash": Engine.get_version_info().hash,
		"identity": manifest.identity,
		"input_map_sha256": FileAccess.get_sha256("res://project.godot"),
		"runtime_sha256": manifest.runtime_sha256,
		"observer_sha256": observer_sha256,
		"attempts": attempts
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(receipt, "\t"))
	file.close()
	saved = true
	player.set_controls_enabled(false)
	player.set_mouse_capture_enabled(false)
	print("JUMP_PLAYTEST_RECEIPT_WRITTEN human_review=pending ", output_path)
	get_tree().quit(0)
