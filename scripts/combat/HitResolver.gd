extends RefCounted

static func resolve_hitscan(camera: Camera3D, max_range: float, collision_mask: int, exclude: Array = []) -> Dictionary:
	var from: Vector3 = camera.global_transform.origin
	var direction: Vector3 = -camera.global_transform.basis.z
	return resolve_direction(from, direction, max_range, collision_mask, exclude, camera.get_world_3d().direct_space_state)

static func resolve_direction(from: Vector3, direction: Vector3, max_range: float, collision_mask: int, exclude: Array, space_state: PhysicsDirectSpaceState3D) -> Dictionary:
	var to: Vector3 = from + (direction.normalized() * max_range)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.exclude = exclude
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return {
			"hit": false,
			"from": from,
			"to": to,
			"direction": direction.normalized()
		}

	return {
		"hit": true,
		"from": from,
		"to": to,
		"direction": direction.normalized(),
		"position": hit.get("position", to),
		"normal": hit.get("normal", Vector3.UP),
		"collider": hit.get("collider", null)
	}
