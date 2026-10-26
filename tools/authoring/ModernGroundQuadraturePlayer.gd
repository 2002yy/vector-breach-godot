extends "res://tools/authoring/QueueCadenceProbePlayer.gd"
## Diagnostic candidate only. Match ground displacement to bounded 120Hz integration.

var quadrature_enabled := false
var quadrature_sample := {}
var cached_end := Vector3.ZERO
var expected_motion_velocity := Vector3.ZERO
var cache_valid := false


func simulate_tactical_horizontal_velocity(
	current_velocity: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	grounded: bool,
	delta: float,
	acceleration_reference: float = -1.0
) -> Vector3:
	quadrature_sample = {"enabled": quadrature_enabled, "restored": false, "substeps": 0}
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
