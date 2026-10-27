extends RefCounted
## Exact capsule queries: no excluded bodies, no radius/height reduction.


static func vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func contact(rest: Dictionary) -> Dictionary:
	if rest.is_empty():
		return {"classification": "unknown"}
	var normal: Vector3 = rest.normal
	var collider := instance_from_id(rest.collider_id) as Node
	return {
		"classification": "support" if normal.y >= cos(deg_to_rad(45.0)) else "wall_or_ceiling",
		"normal": [normal.x, normal.y, normal.z],
		"body": String(collider.get_path()) if collider != null else "",
		"shape": rest.shape,
	}


static func sweep(
	space: PhysicsDirectSpaceState3D, segment: Dictionary, radius: float
) -> Dictionary:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = segment.height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	q.margin = 0.001
	q.transform.origin = vec(segment.from) + vec(segment.local_offset)
	var start := space.intersect_shape(q, 128)
	var start_rest := contact(space.get_rest_info(q))
	q.motion = vec(segment.to) - vec(segment.from)
	var fractions := space.cast_motion(q)
	var impact := {"classification": "none"}
	if fractions[0] < 1.0:
		q.transform.origin += q.motion * minf(1.0, fractions[1] + 0.0001)
		q.motion = Vector3.ZERO
		impact = contact(space.get_rest_info(q))
	q.motion = Vector3.ZERO
	q.transform.origin = vec(segment.to) + vec(segment.local_offset)
	var finish := space.intersect_shape(q, 128)
	var end_rest := contact(space.get_rest_info(q))
	var clear: bool = start.is_empty() and finish.is_empty() and fractions[0] >= 0.999999
	return {
		"segment": segment,
		"initial_overlaps": start.size(),
		"endpoint_overlaps": finish.size(),
		"overlap_limit_reached": start.size() == 128 or finish.size() == 128,
		"start_contact": start_rest,
		"end_contact": end_rest,
		"impact_contact": impact,
		"free_fraction": fractions[0],
		"unsafe_fraction": fractions[1],
		"query_clear": clear,
		"clearance_proven": clear and segment.recovery_depth == 0.0,
		"query_count": 5 + int(fractions[0] < 1.0),
	}
