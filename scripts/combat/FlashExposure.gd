extends RefCounted
## Shared exposure for players and bots; retains the project's existing falloff.


static func intensity(origin: Vector3, eye: Vector3, forward: Vector3) -> float:
	var offset := origin - eye
	if offset.length() > 18.0:
		return 0.0
	var facing := clampf(forward.normalized().dot(offset.normalized()), -1.0, 1.0)
	return clampf((1.0 - offset.length() / 18.0) * lerpf(0.25, 1.0, maxf(facing, 0.0)), 0.0, 1.0)


static func duration(exposure: float) -> float:
	return lerpf(0.5, 3.4, exposure)
