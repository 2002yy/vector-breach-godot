extends SceneTree
## Tiny physical regression world; no map resources or production modifications.

var checks := 0


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
	shape.shape.radius = 0.4
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
	player.support_enabled = true
	player.ablation = "baseline"
	return player


func _box(position: Vector3, size: Vector3, tilt: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	root.add_child(body)
	body.position = position
	body.rotation.z = tilt
	return body


func _step(player: CharacterBody3D, rate: int) -> void:
	await physics_frame
	player._physics_process(1.0 / rate)


func _fallback(rate: int, mode: String) -> void:
	var receipts := []
	var volume: Area3D
	if mode in ["water", "ladder"]:
		volume = Area3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(5, 5, 5)
		volume.add_child(shape)
		volume.set_meta("environment_type", mode)
		volume.set_meta("water_depth", 0.5)
		root.add_child(volume)
	for enabled in [false, true]:
		var player := _actor()
		player.support_enabled = enabled
		player.position = Vector3(0, 1.3, 0)
		player.velocity.y = -1.0
		if mode in ["current", "legacy_16"]:
			_check(player.set_movement_scheme(mode), "fallback scheme accepted")
		elif mode == "controls":
			player.set_controls_enabled(false)
		await physics_frame
		await physics_frame
		for tick in 3:
			await _step(player, rate)
			_check(not player.support_sample.attempted, mode + " bypasses author support")
		if mode == "water":
			_check(player.is_in_water, "real sensor overlaps water")
		elif mode == "ladder":
			_check(player.is_on_ladder, "real sensor overlaps ladder")
		receipts.append(
			[player.position, player.velocity, player.is_on_floor(), player.landing_events]
		)
		player.free()
	_check(receipts[0] == receipts[1], mode + " physical fallback matches disabled candidate")
	if volume:
		volume.free()


func _run() -> void:
	var saved_rate := Engine.physics_ticks_per_second
	var floor_body := _box(Vector3(0, -0.1, 0), Vector3(10, 0.2, 10))
	var steep := _box(Vector3(30, -0.2, 0), Vector3(6, 0.2, 6), deg_to_rad(60))
	var ledge := _box(Vector3(60, -0.1, 0), Vector3(2, 0.2, 4))
	var roof := _box(Vector3(60, 1.5, 0), Vector3(3, 0.2, 4))
	for rate in [60, 120]:
		Engine.physics_ticks_per_second = rate
		var player := _actor()
		player.position = Vector3(30, 1.4, 0)
		player.velocity.y = -1.0
		await physics_frame
		var hit: Dictionary = player._raycast(Vector3(30, 3, 0), Vector3(30, -3, 0))
		_check(not hit.is_empty(), "steep rejection tests actual surface beneath capsule")
		_check(hit.normal.y > 0.4 and hit.normal.y < 0.6, "actual steep normal is 60 degrees")
		for tick in 4:
			await _step(player, rate)
			_check(not player.is_on_floor(), "60 degree surface cannot fabricate support")
		_check(player.landing_events == 0, "steep surface emits no landing")
		player.free()
		player = _actor()
		player.position = Vector3(60.7, 0.95, 0)
		player.velocity.y = -0.1
		player.is_crouching = true
		player._set_collision_height(1.2)
		for tick in 4:
			await _step(player, rate)
		_check(player.is_crouching, "release cannot stand beneath near-ledge roof")
		_check(not player._has_standing_clearance(), "standing capsule physically overlaps roof")
		_check(
			is_equal_approx(player.collision_shape.shape.height, 1.2),
			"crouched capsule remains 1.2m"
		)
		_check(player.is_on_floor(), "crouched capsule establishes real ledge support")
		_check(player.landing_events == 1, "crouched support lands exactly once")
		player.position.x = 62.2
		for tick in 4:
			await _step(player, rate)
		_check(not player.is_on_floor(), "walking beyond ledge loses support")
		_check(not player.is_crouching, "clear space permits standing after leaving roof")
		_check(
			is_equal_approx(player.collision_shape.shape.height, 1.8),
			"standing capsule restores 1.8m"
		)
		_check(player.landing_events == 1, "leaving ledge cannot duplicate landing")
		player.free()
		for mode in ["current", "legacy_16", "controls", "water", "ladder"]:
			await _fallback(rate, mode)
		player = _actor()
		player.support_enabled = false
		player.position = Vector3(0, 1.3, 0)
		player.velocity.y = -1.0
		await _step(player, rate)
		_check(not player.is_on_floor(), "disabled support retains original delayed floor state")
		player.support_enabled = true
		for tick in 4:
			await _step(player, rate)
		_check(
			player.is_on_floor() and player.landing_events == 1,
			"reenabling settles with one landing"
		)
		player.support_enabled = false
		await _step(player, rate)
		_check(
			player.is_on_floor() and player.landing_events == 1,
			"disabling while settled keeps real floor"
		)
		player.free()
	floor_body.free()
	steep.free()
	ledge.free()
	roof.free()
	Engine.physics_ticks_per_second = saved_rate
	print("SUPPORT_BOUNDARIES_OK checks=", checks)
	quit(0)
