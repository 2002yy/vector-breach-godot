extends RefCounted
## Candidate models, not claims of engine parity. Current remains the default.

const UNIT := 0.0254
const SCHEMES := ["current", "legacy_16", "modern_cs"]
const LEGACY_SPEEDS := {
	"rifle": [221.0, 221.0],
	"sniper": [210.0, 150.0],
	"smg": [250.0, 250.0],
	"shotgun": [230.0, 230.0],
	"pistol": [250.0, 250.0],
	"knife": [250.0, 250.0],
}
const MODERN_SPEEDS := {
	"rifle": [215.0, 215.0],
	"sniper": [200.0, 100.0],
	"smg": [240.0, 240.0],
	"shotgun": [220.0, 220.0],
	"pistol": [240.0, 240.0],
	"knife": [250.0, 250.0],
}


static func parameters(scheme: String) -> Dictionary:
	if scheme == "legacy_16":
		return {
			"acceleration": 10.0,
			"friction": 4.0,
			"stop_speed": 100.0 * UNIT,
			"air_acceleration": 10.0,
			"air_wish_cap": 30.0 * UNIT,
			"gravity": 800.0 * UNIT,
			"jump": sqrt(2.0 * 800.0 * 45.0) * UNIT,
			"walk_ratio": 0.52,
			"crouch_ratio": 0.333
		}
	return {
		"acceleration": 5.5,
		"friction": 5.2,
		"stop_speed": 80.0 * UNIT,
		"air_acceleration": 12.0,
		"air_wish_cap": 30.0 * UNIT,
		"gravity": 800.0 * UNIT,
		"jump": 301.99338 * UNIT,
		"walk_ratio": 0.52,
		"crouch_ratio": 0.34
	}


static func speed_limit(scheme: String, state: Dictionary, current: Dictionary) -> float:
	var base: float
	if scheme == "current":
		base = current.run
		if state.crouching:
			base = current.crouch
		elif state.walking:
			base = current.walk
		var slot := int(state.slot)
		base *= 0.94 if slot == 0 else (1.04 if slot == 2 else 1.0)
	else:
		var table: Dictionary = LEGACY_SPEEDS if scheme == "legacy_16" else MODERN_SPEEDS
		var pair: Array = table.get(state.weapon_id, [250.0, 250.0])
		base = float(pair[1 if state.scoped else 0]) * UNIT
		var config := parameters(scheme)
		if state.crouching:
			base *= float(config.crouch_ratio)
		elif state.walking:
			base *= float(config.walk_ratio)
	# Damage is actor state: apply it last, regardless of equipment or stance.
	return base * clampf(state.tagging, 0.0, 1.0) * maxf(state.water, 0.0)


static func ground_step(
	velocity: Vector3, direction: Vector3, wish_speed: float, config: Dictionary, delta: float
) -> Vector3:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed > 0.00001:
		var next := maxf(0.0, speed - maxf(speed, config.stop_speed) * config.friction * delta)
		horizontal *= next / speed
	return _accelerate(horizontal, direction, wish_speed, wish_speed, config.acceleration, delta)


static func air_step(
	velocity: Vector3, direction: Vector3, wish_speed: float, config: Dictionary, delta: float
) -> Vector3:
	# Cap the projection onto the requested direction, never total airborne speed.
	return _accelerate(
		Vector3(velocity.x, 0.0, velocity.z),
		direction,
		minf(wish_speed, config.air_wish_cap),
		wish_speed,
		config.air_acceleration,
		delta
	)


static func _accelerate(
	velocity: Vector3,
	direction: Vector3,
	projection_cap: float,
	wish_speed: float,
	acceleration: float,
	delta: float
) -> Vector3:
	if direction.length_squared() < 0.00001:
		return velocity
	var wish := direction.normalized()
	var available := projection_cap - velocity.dot(wish)
	if available <= 0.0:
		return velocity
	return velocity + wish * minf(available, acceleration * wish_speed * delta)
