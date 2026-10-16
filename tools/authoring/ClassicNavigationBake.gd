extends RefCounted


# Offline only. Bake the explicitly selected collision resource, never visuals.
# Keep portals as waypoints so each graph edge stays inside a convex polygon.
static func build(level: Node3D) -> Dictionary:
	var data: Dictionary = level.call("get_current_level_data")
	var collision := level.get_node_or_null("VisualRoot/LevelCollisionSource")
	if collision == null:
		return {}
	var source := NavigationMeshSourceGeometryData3D.new()
	_collect(collision, source)
	var nav := NavigationMesh.new()
	nav.cell_size = 0.1
	nav.cell_height = 0.05
	nav.agent_height = 1.8
	nav.agent_radius = 0.4
	nav.agent_max_climb = 0.4
	nav.agent_max_slope = 46
	nav.region_min_size = 1.0
	nav.region_merge_size = 5.0
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	var vertices := nav.get_vertices()
	var points: Array = []
	var links: Array = []
	var edges := {}
	for index in range(nav.get_polygon_count()):
		var polygon := nav.get_polygon(index)
		var center := Vector3.ZERO
		for vertex in polygon:
			center += vertices[vertex]
		center = center / polygon.size() + Vector3.UP * 0.96
		points.append([center.x, center.y, center.z])
	for index in range(nav.get_polygon_count()):
		var polygon := nav.get_polygon(index)
		for side in range(polygon.size()):
			var a := vertices[polygon[side]]
			var b := vertices[polygon[(side + 1) % polygon.size()]]
			var aa := Vector3i((a * 1000).round())
			var bb := Vector3i((b * 1000).round())
			var key := str(aa) + ":" + str(bb) if aa < bb else str(bb) + ":" + str(aa)
			if not edges.has(key):
				edges[key] = index
				continue
			var portal := (a + b) * 0.5 + Vector3.UP * 0.96
			var portal_index := points.size()
			points.append([portal.x, portal.y, portal.z])
			links.append({"from": index, "to": portal_index, "precise": true})
			links.append({"from": int(edges[key]), "to": portal_index, "precise": true})
	if points.is_empty():
		return {}
	var start: Array = data.get("start", [0, 0])
	var seed := Vector3(float(start[0]), float(data.get("startHeight", 1)), float(start[1]))
	var first := 0
	for index in range(points.size()):
		if (
			_vector(points[index]).distance_squared_to(seed)
			< _vector(points[first]).distance_squared_to(seed)
		):
			first = index
	var neighbors := {}
	for link in links:
		for pair in [[link.from, link.to], [link.to, link.from]]:
			if not neighbors.has(pair[0]):
				neighbors[pair[0]] = []
			neighbors[pair[0]].append(pair[1])
	var reached := {first: 0}
	var queue: Array = [first]
	var cursor := 0
	while cursor < queue.size():
		for next in neighbors.get(queue[cursor], []):
			if not reached.has(next):
				reached[next] = queue.size()
				queue.append(next)
		cursor += 1
	var connected_points: Array = []
	var connected_links: Array = []
	for index in queue:
		connected_points.append(points[index])
	for link in links:
		if reached.has(link.from) and reached.has(link.to):
			connected_links.append(
				{
					"from": reached[link.from],
					"to": reached[link.to],
					"precise": true,
					"arrivalRadius": 0.22
				}
			)
	return {"points": connected_points, "links": connected_links}


static func _vector(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))


static func _collect(node: Node, source: NavigationMeshSourceGeometryData3D) -> void:
	if node is MeshInstance3D:
		source.add_mesh(node.mesh, node.global_transform)
	for child in node.get_children():
		_collect(child, source)
