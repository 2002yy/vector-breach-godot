extends RefCounted
## Read-only survey. Derived coordinates belong in local evidence, not Git.


static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func floor_at(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at - Vector3.UP * 4.0, 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.95:
		return {}
	return hit


static func capsule_clear(space: PhysicsDirectSpaceState3D, feet: Vector3, height := 1.8) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform.origin = feet + Vector3.UP * (height * 0.5 + 0.025)
	return space.intersect_shape(query, 1).is_empty()


static func body_corridor(
	space: PhysicsDirectSpaceState3D, start: Vector3, goal: Vector3, crouched := false
) -> Dictionary:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.2 if crouched else 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.margin = 0.001
	var arcs: Array[Dictionary] = []
	var clear_count := 0
	var wall_count := 0
	for lift in [0.0, 0.8, 1.2, 1.7]:
		var segments: Array[Dictionary] = []
		var clear := true
		var wall := false
		var steps := maxi(32, int(ceil(start.distance_to(goal) / 0.05)))
		for step in range(steps):
			var t0 := float(step) / steps
			var t1 := float(step + 1) / steps
			var a: Vector3 = (
				start.lerp(goal, t0)
				+ Vector3.UP * (shape.height * 0.5 + 0.04 + 4.0 * lift * t0 * (1.0 - t0))
			)
			var b: Vector3 = (
				start.lerp(goal, t1)
				+ Vector3.UP * (shape.height * 0.5 + 0.04 + 4.0 * lift * t1 * (1.0 - t1))
			)
			query.transform.origin = a
			query.motion = b - a
			var initial_clear := space.intersect_shape(query, 1).is_empty()
			var fractions := space.cast_motion(query)
			var fraction: float = fractions[0]
			var row := {
				"from": array(a),
				"to": array(b),
				"initial_clear": initial_clear,
				"free_fraction": fraction,
				"normal": [0, 0, 0]
			}
			if not initial_clear or fraction < 0.999:
				query.transform.origin = a + (b - a) * minf(1.0, float(fractions[1]) + 0.02)
				var rest := space.get_rest_info(query)
				if not rest.is_empty():
					row.normal = array(rest.normal)
					var horizontal := (goal - start).normalized()
					wall = absf(rest.normal.y) < 0.3 and rest.normal.dot(horizontal) < -0.1
				clear = false
			segments.append(row)
			if not clear:
				break
		clear_count += 1 if clear else 0
		wall_count += 1 if wall and lift > 0.0 else 0
		arcs.append(
			{"lift": lift, "clear": clear, "wall": wall, "steps": steps, "segments": segments}
		)
	return {
		"capsule_radius": 0.4,
		"capsule_height": shape.height,
		"foot_clearance": 0.04,
		"clear_arcs": clear_count,
		"arcs": arcs,
		"status":
		(
			"geometric_corridor_found"
			if clear_count > 0
			else ("blocked_direct_route" if wall_count == 3 else "route_unproven")
		)
	}


static func _edge(
	space: PhysicsDirectSpaceState3D, feet: Vector3, direction: Vector3, index: int, distance: float
) -> Dictionary:
	var near := floor_at(
		space, feet + direction * (0.8 if distance < 2.0 else 1.0) - Vector3.UP * 0.2
	)
	var far := floor_at(space, feet + direction * distance - Vector3.UP * 0.2)
	if near.is_empty() or far.is_empty():
		return {}
	if absf(far.position.y - near.position.y) > 0.15 or not capsule_clear(space, far.position):
		return {}
	if absf(near.position.y - feet.y) < 0.5 or absf(near.position.y - feet.y) > 2.0:
		return {}
	var corridor := body_corridor(space, feet, far.position)
	return {
		"node": index,
		"feet": array(feet),
		"direction": array(direction),
		"target_feet": array(far.position),
		"height_change": near.position.y - feet.y,
		"near_feet": array(near.position),
		"corridor": corridor
	}


static func discover(space: PhysicsDirectSpaceState3D, layout: Dictionary) -> Dictionary:
	var points: Array = layout.navigationGraph.points
	var flat: Array[Dictionary] = []
	var rises: Array[Dictionary] = []
	var drops: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	# Deterministic geometry-only selection, before any scheme is executed.
	for index in range(0, points.size(), 3):
		var origin := vector(points[index])
		var ground := floor_at(space, origin - Vector3.UP * 1.8)
		if ground.is_empty() or absf(ground.position.y + 0.96 - origin.y) > 0.4:
			continue
		var feet: Vector3 = ground.position
		if not capsule_clear(space, feet):
			continue
		if flat.size() < 30:
			flat.append({"node": index, "feet": array(feet)})
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			for distance in [1.6, 3.0]:
				var record := _edge(space, feet, direction, index, distance)
				if record.is_empty():
					continue
				var change: float = record.height_change
				if absf(change) < 0.5 or absf(change) > 2.0:
					continue
				if record.corridor.clear_arcs == 0:
					if rejected.size() < 100:
						rejected.append(record)
					continue
				if change >= 0.5 and change <= 1.45 and rises.size() < 100:
					rises.append(record)
				elif change <= -0.5 and change >= -2.0 and drops.size() < 100:
					drops.append(record)
		if rises.size() >= 100 and drops.size() >= 100:
			break
	var critical: Array[Dictionary] = []
	for objective in layout.objectives:
		var goal := Vector3(objective.x, objective.y, objective.z)
		var nearest := 0
		for index in range(points.size()):
			if (
				vector(points[index]).distance_squared_to(goal)
				< vector(points[nearest]).distance_squared_to(goal)
			):
				nearest = index
		var ground := floor_at(space, vector(points[nearest]) - Vector3.UP * 1.8)
		if ground.is_empty() or not capsule_clear(space, ground.position):
			continue
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var clear := true
			for distance in [1.0, 2.0, 3.0, 4.0]:
				var hit := floor_at(
					space, ground.position - direction * distance - Vector3.UP * 0.2
				)
				if (
					hit.is_empty()
					or absf(hit.position.y - ground.position.y) > 0.15
					or not capsule_clear(space, hit.position)
				):
					clear = false
					break
			if clear:
				var corridor := body_corridor(
					space, ground.position - direction * 4.0, ground.position
				)
				if corridor.clear_arcs == 0:
					continue
				critical.append(
					{
						"node": nearest,
						"objective": objective.id,
						"feet": array(ground.position - direction * 4.0),
						"target_feet": array(ground.position),
						"direction": array(direction)
					}
				)
				break
	return {
		"flat": flat, "rises": rises, "drops": drops, "critical": critical, "rejected": rejected
	}


static func make_case(kind: String, record: Dictionary) -> Dictionary:
	var direction := vector(record.get("direction", [0, 0, -1]))
	var start := vector(record.feet) + Vector3.UP * 0.91
	var target := vector(record.get("target_feet", record.feet))
	var moving := kind != "ordinary"
	var crouching := kind == "crouch_jump"
	var jump_time := 0.1 if moving else 0.25
	if kind == "run_up":
		start -= direction * 1.2
		jump_time = 0.35
	return {
		"id": kind,
		"kind": kind,
		"source_nav_node": record.node,
		"start": array(start),
		"yaw": atan2(-direction.x, -direction.z),
		"target_feet": array(target),
		"target_radius": 1.6 if moving else 0.35,
		"target_height_tolerance": 0.18,
		"duration": 2.0,
		"geometry": record,
		"timeline":
		[
			{"at": 0.0, "direction": [0, -1] if moving else [0, 0], "crouch": crouching},
			{"at": jump_time, "jump": true},
			{"at": jump_time + 0.1, "jump": false},
			{"at": 1.5, "direction": [0, 0]},
		]
	}
