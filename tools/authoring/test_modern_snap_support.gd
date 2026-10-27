extends SceneTree

var checks := 0
var samples := []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	assert(value, label)
	checks += 1


func _actor() -> CharacterBody3D:
	var player = load("res://tools/authoring/ModernSnapSupportPlayer.gd").new()
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	player.add_child(pivot)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = CapsuleShape3D.new()
	shape.shape.height = 1.8
	player.add_child(shape)
	var sensor := Area3D.new()
	sensor.name = "EnvironmentSensor"
	var sensor_shape := CollisionShape3D.new()
	sensor_shape.shape = SphereShape3D.new()
	sensor_shape.shape.radius = 0.4
	sensor.add_child(sensor_shape)
	player.add_child(sensor)
	root.add_child(player)
	player.set_physics_process(false)
	player._spawn_applied = true
	player.set_movement_scheme("modern_cs")
	player.set_controls_enabled(true)
	player.set_movement_enabled(true)
	player.vertical_enabled = true
	player.ablation = "baseline"
	player.movement_step.connect(func(sample: Dictionary): samples.append(sample.duplicate(true)))
	return player


func _box(position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(20, 0.2, 20)
	body.add_child(shape)
	root.add_child(body)
	body.position = position
	return body


func _step(player: CharacterBody3D, rate: int) -> void:
	await physics_frame
	player._physics_process(1.0 / rate)


func _environment(position: Vector3, kind: String) -> Area3D:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(5, 5, 5)
	area.add_child(shape)
	area.set_meta("environment_type", kind)
	area.set_meta("water_depth", 0.5)
	root.add_child(area)
	area.position = position
	return area


func _run() -> void:
	var saved_rate := Engine.physics_ticks_per_second
	var floor_body := _box(Vector3(0, -0.1, 0))
	for rate in [60, 120]:
		Engine.physics_ticks_per_second = rate
		for enabled in [false, true]:
			var player := _actor()
			player.support_enabled = enabled
			player.position = Vector3(0, 1.3, 0)
			player.velocity.y = -1.0
			await _step(player, rate)
			_check(
				absf(player.position.y - 0.9) < 0.001, "original snap still places capsule on floor"
			)
			_check(
				player.is_on_floor() == enabled,
				"engine support synchronized only when candidate enabled"
			)
			_check(
				player.landing_events == int(enabled),
				"same-frame landed event follows actual support"
			)
			_check(
				samples[-1].grounded_after == player.is_on_floor(),
				"observer sees engine support state"
			)
			if enabled:
				_check(player.get_floor_normal().y > 0.99, "walkable real floor normal established")
			for tick in 3:
				await _step(player, rate)
			_check(player.landing_events == 1, "settled landing event never duplicates")
			player.free()
		var unsupported := _actor()
		unsupported.support_enabled = true
		unsupported.position = Vector3(50, 1.3, 0)
		unsupported.velocity.y = -1
		await _step(unsupported, rate)
		_check(not unsupported.is_on_floor(), "no ground is never synthesized")
		_check(not unsupported.support_sample.attempted, "no original snap means no forced support")
		unsupported.free()
		var current := _actor()
		current.support_enabled = true
		current.set_movement_scheme("current")
		current.position = Vector3(0, 1.3, 0)
		current.velocity.y = -1
		await _step(current, rate)
		_check(not current.support_sample.attempted, "Current retains original snap state")
		current.free()
	floor_body.free()
	Engine.physics_ticks_per_second = saved_rate
	print("MODERN_SNAP_SUPPORT_OK checks=", checks)
	quit(0)
