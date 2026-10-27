extends SceneTree

var checks := 0
var samples := []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	assert(value, label)
	checks += 1


func _actor() -> CharacterBody3D:
	var player = load("res://tools/authoring/ModernVerticalQuadraturePlayer.gd").new()
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
	player.ablation = "no_snap"
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
	var endpoints := {}
	for rate in [60, 120]:
		Engine.physics_ticks_per_second = rate
		var player := _actor()
		player.position = Vector3(0, 10, 0)
		var impulse: float = player._movement_jump_impulse()
		var gravity_value: float = player._movement_gravity()
		player.velocity = Vector3(0, impulse, 0)
		for tick in rate / 3:
			await _step(player, rate)
		var duration: float = float(rate / 3) / rate
		_check(
			(
				absf(
					(
						player.position.y
						- (10 + impulse * duration - gravity_value * duration * duration / 2)
					)
				)
				< 0.0001
			),
			"actual free-flight position uses midpoint drift"
		)
		_check(
			absf(player.velocity.y - (impulse - gravity_value * duration)) < 0.0001,
			"persistent endpoint has full gravity"
		)
		_check(
			samples[-1].velocity == player.velocity,
			"observer sees persisted endpoint before record"
		)
		endpoints[rate] = player.position.y
		player.vertical_enabled = false
		await _step(player, rate)
		_check(not player.vertical_sample.enabled, "disabled candidate follows baseline")
		player.vertical_enabled = true
		player.set_movement_scheme("current")
		await _step(player, rate)
		_check(not player.vertical_sample.enabled, "Current never enters candidate")
		player.set_movement_scheme("modern_cs")
		player.set_movement_enabled(false)
		await _step(player, rate)
		_check(not player.vertical_sample.enabled, "disabled movement excludes candidate")
		player.set_controls_enabled(false)
		await _step(player, rate)
		_check(not player.vertical_sample.enabled, "disabled controls excludes candidate")
		player.free()
	_check(
		absf(endpoints[60] - endpoints[120]) < 0.0001, "same physical endpoint agrees across rates"
	)
	Engine.physics_ticks_per_second = 60
	var floor_body := _box(Vector3(0, -0.1, 0))
	var player := _actor()
	player.position = Vector3(0, 0.91, 0)
	for tick in 5:
		await _step(player, 60)
	_check(player.is_on_floor(), "actual capsule settles on floor")
	Input.action_press("jump")
	await _step(player, 60)
	Input.action_release("jump")
	_check(samples[-1].jumped, "actual production pipeline consumes grounded jump")
	_check(player.vertical_sample.phase == "postkick", "jump frame applies both half kicks")
	_check(
		(
			absf(
				(
					player.velocity.y
					- (player._movement_jump_impulse() - player._movement_gravity() / 60)
				)
			)
			< 0.0001
		),
		"jump endpoint is impulse minus full kick"
	)
	var ceiling := _box(Vector3(0, 2.15, 0))
	for tick in 10:
		await _step(player, 60)
	_check(player.position.y < 1.25, "ceiling contact blocks upward drift")
	_check(player.velocity.y <= 0.0, "ceiling does not restore upward endpoint")
	for tick in 40:
		await _step(player, 60)
	_check(
		player.is_on_floor() and absf(player.velocity.y) < 0.0001, "landing clears vertical motion"
	)
	player.free()
	floor_body.free()
	ceiling.free()
	player = _actor()
	player.position = Vector3(50, 1.5, 0)
	var water := _environment(player.position, "water")
	for tick in 3:
		await _step(player, 60)
	_check(player.is_in_water, "actual sensor detects water volume")
	_check(not player.vertical_sample.enabled, "water preserves baseline vertical rules")
	water.free()
	player.position = Vector3(100, 1.5, 0)
	var ladder := _environment(player.position, "ladder")
	for tick in 3:
		await _step(player, 60)
	_check(player.is_on_ladder, "actual sensor detects ladder volume")
	_check(not player.vertical_sample.enabled, "ladder preserves baseline vertical rules")
	player.free()
	ladder.free()
	Engine.physics_ticks_per_second = saved_rate
	print("MODERN_VERTICAL_QUADRATURE_OK checks=", checks)
	quit(0)
