extends RefCounted
## Full-body path queries. Contact is never silently treated as clearance.


static func vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func sweep(space: PhysicsDirectSpaceState3D, poses: Array, radius: float) -> Dictionary:
	var segments: Array[Dictionary] = []
	var clear := true
	var query_count := 0
	for index in range(poses.size() - 1):
		var a: Dictionary = poses[index]
		var b: Dictionary = poses[index + 1]
		var shape := CapsuleShape3D.new()
		shape.radius = radius
		shape.height = maxf(a.height, b.height)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.margin = 0.001
		query.transform.origin = vec(a.position)
		var initial := space.intersect_shape(query, 32)
		query_count += 1
		query.motion = vec(b.position) - vec(a.position)
		var fractions := space.cast_motion(query)
		query_count += 1
		var normal := Vector3.ZERO
		if fractions[0] < 1.0:
			query.transform.origin = (
				vec(a.position) + query.motion * minf(1.0, fractions[1] + 0.0001)
			)
			var rest := space.get_rest_info(query)
			query_count += 1
			if not rest.is_empty():
				normal = rest.normal
		query.motion = Vector3.ZERO
		query.transform.origin = vec(b.position)
		var endpoint := space.intersect_shape(query, 32)
		query_count += 1
		var transition: bool = absf(a.height - b.height) > 0.00001
		var segment_clear: bool = (
			initial.is_empty()
			and endpoint.is_empty()
			and fractions[0] >= 0.999999
			and not transition
		)
		segments.append(
			{
				"from": a.position,
				"to": b.position,
				"height": shape.height,
				"initial_overlaps": initial.size(),
				"endpoint_overlaps": endpoint.size(),
				"free_fraction": fractions[0],
				"normal": [normal.x, normal.y, normal.z],
				"support_contact": normal.y >= cos(deg_to_rad(45.0)),
				"height_transition": transition,
				"clear": segment_clear
			}
		)
		clear = clear and segment_clear
	return {"clear": clear, "segments": segments, "query_count": query_count}
