extends "res://tools/authoring/QueueCadenceProbePlayer.gd"
## Versioned author candidate: discard hidden momentum across lifecycle transitions.

var quadrature_enabled := false:
	set(value):
		if quadrature_enabled != value:
			_clear_quadrature_cache("candidate_toggle")
		quadrature_enabled = value
var quadrature_sample := {}
var cached_end := Vector3.ZERO
var expected_motion_velocity := Vector3.ZERO
var cache_valid := false
var cache_epoch := 0
var cache_reset_reason := "initial"


func _clear_quadrature_cache(reason: String) -> void:
	cache_valid = false
	cached_end = Vector3.ZERO
	expected_motion_velocity = Vector3.ZERO
	cache_epoch += 1
	cache_reset_reason = reason


func set_movement_scheme(scheme: String) -> bool:
	var previous := movement_scheme
	var accepted := super.set_movement_scheme(scheme)
	if accepted and previous != movement_scheme:
		_clear_quadrature_cache("movement_scheme")
	return accepted


func set_controls_enabled(enabled: bool) -> void:
	if not enabled:
		_clear_quadrature_cache("controls_disabled")
	super.set_controls_enabled(enabled)


func set_movement_enabled(enabled: bool) -> void:
	super.set_movement_enabled(enabled)
	if not movement_enabled:
		_clear_quadrature_cache("movement_disabled")


func _apply_spawn() -> void:
	_clear_quadrature_cache("spawn")
	super._apply_spawn()


func simulate_tactical_horizontal_velocity(
	current_velocity: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	grounded: bool,
	delta: float,
	acceleration_reference: float = -1.0
) -> Vector3:
	quadrature_sample = {"enabled": quadrature_enabled, "restored": false, "substeps": 0}
	quadrature_sample["cache_epoch"] = cache_epoch
	quadrature_sample["cache_reset_reason"] = cache_reset_reason
	if not quadrature_enabled or movement_scheme != "modern_cs":
		cache_valid = false
		return super.simulate_tactical_horizontal_velocity(
			current_velocity, wish_direction, wish_speed, grounded, delta, acceleration_reference
		)
	var restored := cache_valid and current_velocity.distance_to(expected_motion_velocity) < 0.00001
	quadrature_sample["cache_discarded"] = cache_valid and not restored
	if restored:
		current_velocity = cached_end
	quadrature_sample.restored = restored
	cache_valid = false
	if not grounded:
		return super.simulate_tactical_horizontal_velocity(
			current_velocity, wish_direction, wish_speed, grounded, delta, acceleration_reference
		)
	var count := maxi(1, int(ceil(delta * 120.0 - 0.000001)))
	var step := delta / count
	var integrated := current_velocity
	var sum := Vector3.ZERO
	var reference := wish_speed if acceleration_reference < 0.0 else acceleration_reference
	for index in count:
		integrated = MovementRules.ground_step(
			integrated,
			wish_direction,
			wish_speed,
			MovementRules.parameters("modern_cs"),
			step,
			reference
		)
		sum += integrated
	cached_end = integrated
	expected_motion_velocity = sum / count
	cache_valid = true
	quadrature_sample.substeps = count
	quadrature_sample["end_velocity"] = [cached_end.x, cached_end.y, cached_end.z]
	quadrature_sample["motion_velocity"] = [
		expected_motion_velocity.x, expected_motion_velocity.y, expected_motion_velocity.z
	]
	return expected_motion_velocity
