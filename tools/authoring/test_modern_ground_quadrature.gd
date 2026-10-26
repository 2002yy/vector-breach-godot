extends SceneTree


func _initialize() -> void:
	var script := load("res://tools/authoring/ModernGroundQuadraturePlayer.gd")
	var player = script.new()
	player.movement_scheme = "modern_cs"
	player.quadrature_enabled = true
	var first: Vector3 = player.simulate_tactical_horizontal_velocity(
		Vector3.ZERO, Vector3.RIGHT, 1.85674, true, 1.0 / 60.0, 5.461
	)
	assert(absf(first.x - 0.331417083333) < 0.000001)
	assert(absf(player.cached_end.x - 0.412538333333) < 0.000001)
	var second: Vector3 = player.simulate_tactical_horizontal_velocity(
		first, Vector3.RIGHT, 1.85674, true, 1.0 / 60.0, 5.461
	)
	assert(player.quadrature_sample.restored)
	assert(absf(second.x - 0.655902083333) < 0.000001)
	var after_collision: Vector3 = player.simulate_tactical_horizontal_velocity(
		Vector3(0.01, 0, 0), Vector3.RIGHT, 1.85674, false, 1.0 / 60.0, 5.461
	)
	assert(player.quadrature_sample.cache_discarded and not player.quadrature_sample.restored)
	assert(after_collision.x < 0.76201 and not player.cache_valid)
	player.quadrature_enabled = false
	var disabled: Vector3 = player.simulate_tactical_horizontal_velocity(
		Vector3.ZERO, Vector3.RIGHT, 1.85674, true, 1.0 / 60.0, 5.461
	)
	assert(absf(disabled.x - 0.500591666667) < 0.000001)
	player.free()
	print("MODERN_GROUND_QUADRATURE_UNIT_OK 7 assertions")
	quit(0)
