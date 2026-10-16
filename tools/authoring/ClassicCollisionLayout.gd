extends RefCounted

const STEP := 1.0
const CENTER_HEIGHT := 0.96
static var _cache: Dictionary = {}


# A local-only collision scan, shared by both visual versions. No Valve geometry
# or derived map coordinates are published to the repository.
static func build(
	space: PhysicsDirectSpaceState3D, data: Dictionary, exclude: Array[RID]
) -> Dictionary:
	var key := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	if _cache.has(key):
		return _cache[key].duplicate(true)
	var start: Array = data.get("start", [0, 0])
	var seed := Vector3(float(start[0]), float(data.get("startHeight", 3.82)), float(start[1]))
	var points: Array[Vector3] = []
	var links: Array = []
	var indices := {}
	var first := _floor_position(space, seed, exclude)
	if not first.is_finite():
		return {}
	points.append(first)
	indices[Vector2i.ZERO] = 0
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var cursor := 0
	while cursor < cells.size() and cells.size() < 12000:
		var cell := cells[cursor]
		var current := points[cursor]
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if absi(next.x) > 110 or absi(next.y) > 110:
				continue
			var neighbor := Vector3(first.x + next.x * STEP, current.y, first.z + next.y * STEP)
			if indices.has(next):
				neighbor = points[int(indices[next])]
			else:
				neighbor = _floor_position(space, neighbor, exclude)
			if not neighbor.is_finite() or absf(neighbor.y - current.y) > 1.25:
				continue
			if not _link_clear(space, current, neighbor, exclude):
				continue
			if not indices.has(next):
				indices[next] = points.size()
				points.append(neighbor)
				cells.append(next)
			var neighbor_index := int(indices[next])
			if cursor < neighbor_index:
				links.append({"from": cursor, "to": neighbor_index, "precise": true})
		cursor += 1
	return _assemble(data, points, links, first, key)


static func from_navigation(data: Dictionary, graph: Dictionary) -> Dictionary:
	var points: Array[Vector3] = []
	for point in graph.get("points", []):
		points.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
	var start: Array = data.get("start", [0, 0])
	if points.is_empty():
		return {}
	var seed := Vector3(float(start[0]), float(data.get("startHeight", 1)), float(start[1]))
	return _assemble(data, points, graph.get("links", []), _nearest(points, seed), "")


static func _assemble(data: Dictionary, points: Array[Vector3], links: Array, first: Vector3, key: String) -> Dictionary:
	var landmarks: Array = (data.get("landmarks", []) as Array).filter(
		func(record: Dictionary) -> bool:
			return String(record.get("name", "")) in ["site-a", "site-b"]
	)
	landmarks.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"])
	)
	if landmarks.size() < 2:
		return {}
	var objectives: Array = []
	for index in range(2):
		var landmark: Dictionary = landmarks[index]
		var target := _nearest(
			points, Vector3(float(landmark["x"]), float(landmark["y"]), float(landmark["z"]))
		)
		if (
			Vector2(target.x, target.z).distance_to(
				Vector2(float(landmark["x"]), float(landmark["z"]))
			)
			> 6.0
		):
			push_error(
				(
					"Classic collision graph cannot reach objective "
					+ str(index)
					+ " nodes="
					+ str(points.size())
					+ " nearest="
					+ str(target)
				)
			)
			return {}
		objectives.append(
			{
				"id": "site-a" if index == 0 else "site-b",
				"label": "A" if index == 0 else "B",
				"x": target.x,
				"y": target.y,
				"z": target.z,
				"sx": 8.0,
				"sz": 8.0
			}
		)
	var site_a: Dictionary = objectives[0]
	var site_b: Dictionary = objectives[1]
	var ct_center := _nearest(
		points,
		Vector3(
			float(site_a["x"]), float(site_b["y"]), (float(site_a["z"]) + float(site_b["z"])) * 0.5
		)
	)
	var spawn_hints: Dictionary = data.get("spawnHints", {})
	if spawn_hints.has("CT"):
		var hint: Array = spawn_hints.CT
		var requested := Vector3(float(hint[0]), float(hint[1]), float(hint[2]))
		ct_center = _nearest(points, requested)
		if Vector2(ct_center.x, ct_center.z).distance_to(Vector2(requested.x, requested.z)) > 6.0:
			push_error("Classic navigation cannot reach authored CT spawn")
			return {}
	var spawns := {"T": _spawn_cluster(points, first), "CT": _spawn_cluster(points, ct_center)}
	var actors: Array = []
	for team in ["T", "CT"]:
		if (spawns[team] as Array).size() != 5:
			return {}
		for index in range(5):
			var position: Array = spawns[team][index]
			actors.append(
				{
					"name": ("进攻队员" if team == "T" else "防守队员") + str(index + 1),
					"team": team,
					"x": position[0],
					"y": position[1],
					"z": position[2],
					"weapon": "pistol",
					"armor": 0,
					"aiEnabled": true,
					"aiMoney": 800,
					"aiViewDistance": 65.0
				}
			)
	var graph_points: Array = []
	for point in points:
		graph_points.append([point.x, point.y, point.z])
	var layout := {
		"navigationGraph": {"points": graph_points, "links": links},
		"objectives": objectives,
		"matchSpawns": spawns,
		"teamActors": actors.filter(func(record: Dictionary) -> bool: return record["team"] == "T"),
		"combatTargets":
		actors.filter(func(record: Dictionary) -> bool: return record["team"] == "CT"),
		"teamSize": 5
	}
	_cache[key] = layout
	print(
		(
			"CLASSIC_LAYOUT="
			+ JSON.stringify(
				{
					"nodes": points.size(),
					"links": links.size(),
					"objectives": objectives,
					"spawns": spawns
				}
			)
		)
	)
	return layout.duplicate(true)


static func _floor_position(
	space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array[RID]
) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.7, point - Vector3.UP * 3.0, 1, exclude
	)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.65:
		return Vector3.INF
	var position: Vector3 = hit["position"] + Vector3.UP * CENTER_HEIGHT
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.06)
	query.collision_mask = 1
	query.exclude = exclude
	return position if space.intersect_shape(query, 1).is_empty() else Vector3.INF


static func _link_clear(
	space: PhysicsDirectSpaceState3D, start: Vector3, finish: Vector3, exclude: Array[RID]
) -> bool:
	for offset in [
		Vector3.ZERO, Vector3.UP * 0.65, Vector3(0.32, 0.0, 0.32), Vector3(-0.32, 0.0, -0.32)
	]:
		if not (
			space
			. intersect_ray(
				PhysicsRayQueryParameters3D.create(start + offset, finish + offset, 1, exclude)
			)
			. is_empty()
		):
			return false
	for fraction in [0.25, 0.5, 0.75]:
		var sampled := _floor_position(space, start.lerp(finish, fraction), exclude)
		if not sampled.is_finite() or absf(sampled.y - start.lerp(finish, fraction).y) > 0.65:
			return false
	return true


static func _nearest(points: Array[Vector3], hint: Vector3) -> Vector3:
	var nearest := points[0]
	for point in points:
		if point.distance_squared_to(hint) < nearest.distance_squared_to(hint):
			nearest = point
	return nearest


static func _spawn_cluster(points: Array[Vector3], center: Vector3) -> Array:
	var candidates := points.duplicate()
	candidates.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			return a.distance_squared_to(center) < b.distance_squared_to(center)
	)
	var selected: Array = []
	for point in candidates:
		if point.distance_to(center) > 7.0:
			break
		var overlaps := false
		for existing in selected:
			if point.distance_to(Vector3(existing[0], existing[1], existing[2])) < 0.95:
				overlaps = true
				break
		if overlaps:
			continue
		selected.append([point.x, point.y, point.z])
		if selected.size() == 5:
			break
	return selected
