extends SceneTree

var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	assert(value, label)
	checks += 1


func _seed(player: CharacterBody3D) -> Vector3:
	player.set_movement_scheme("modern_cs")
	player.quadrature_enabled = true
	player.cache_valid = false
	var motion: Vector3 = player.simulate_tactical_horizontal_velocity(
		Vector3.ZERO, Vector3.RIGHT, 1.85674, true, 1.0 / 60.0, 5.461
	)
	_check(player.cache_valid, "seed caches endpoint")
	_check(absf(motion.x - 0.331417083333) < 0.000001, "numeric kernel unchanged")
	return motion


func _run() -> void:
	var player = load("res://tools/authoring/ModernGroundQuadratureV2Player.gd").new()
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	player.add_child(pivot)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = CapsuleShape3D.new()
	player.add_child(shape)
	var sensor := Area3D.new()
	sensor.name = "EnvironmentSensor"
	player.add_child(sensor)
	player.set_physics_process(false)
	root.add_child(player)
	player.set_physics_process(false)
	var motion := _seed(player)
	player.quadrature_enabled = false
	player.quadrature_enabled = true
	_check(not player.cache_valid, "off/on clears without intermediate simulation")
	var air: Vector3 = player.simulate_tactical_horizontal_velocity(
		motion, Vector3.RIGHT, 1.85674, false, 1.0 / 60.0, 5.461
	)
	_check(not player.quadrature_sample.restored, "no stale endpoint after toggle")
	_check(absf(air.x - 0.702765083333) < 0.000001, "toggle cannot inject hidden momentum")
	motion = _seed(player)
	player.set_movement_scheme("current")
	player.set_movement_scheme("modern_cs")
	_check(not player.cache_valid, "scheme round trip clears without simulation")
	player.simulate_tactical_horizontal_velocity(
		motion, Vector3.RIGHT, 1.85674, false, 1.0 / 60.0, 5.461
	)
	_check(not player.quadrature_sample.restored, "no stale endpoint after scheme round trip")
	_seed(player)
	player.set_controls_enabled(false)
	player.set_controls_enabled(true)
	_check(not player.cache_valid, "control lifecycle clears cache")
	_seed(player)
	player.set_movement_enabled(false)
	player.set_movement_enabled(true)
	_check(not player.cache_valid, "movement lifecycle clears cache")
	_seed(player)
	var state := root.get_node("GameState")
	var saved: Vector3 = state.player_spawn
	state.player_spawn = Vector3(2, 3, 4)
	player._apply_spawn()
	state.player_spawn = saved
	_check(
		not player.cache_valid and player.cache_reset_reason == "spawn",
		"spawn clears hidden momentum"
	)
	_seed(player)
	var epoch: int = player.cache_epoch
	_check(not player.set_movement_scheme("invalid"), "invalid scheme rejected")
	_check(
		player.cache_epoch == epoch and player.cache_valid, "rejected scheme leaves state intact"
	)
	player.free()
	print("MODERN_QUADRATURE_LIFECYCLE_OK checks=", checks)
	quit(0)
