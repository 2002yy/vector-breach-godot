class_name BotNavigationModel
extends RefCounted

var points: Array[Vector3] = []
var links: Array = []
var link_count: int = 0


func configure(graph_variant: Variant) -> void:
	points.clear()
	links.clear()
	link_count = 0
	if not graph_variant is Dictionary:
		return
	var graph := graph_variant as Dictionary
	points = parse_points(graph.get("points", []))
	links.resize(points.size())
	for index in range(links.size()):
		links[index] = []
	for link_variant in graph.get("links", []):
		var from_index := -1
		var to_index := -1
		var attributes: Dictionary = {}
		if link_variant is Array:
			var link := link_variant as Array
			if link.size() < 2:
				continue
			from_index = int(link[0])
			to_index = int(link[1])
		elif link_variant is Dictionary:
			var link := link_variant as Dictionary
			from_index = int(link.get("from", -1))
			to_index = int(link.get("to", -1))
			attributes = link.duplicate(true)
		else:
			continue
		if (
			from_index < 0 or from_index >= links.size()
			or to_index < 0 or to_index >= links.size()
			or from_index == to_index
		):
			continue
		links[from_index].append(_normalize_link(to_index, attributes))
		links[to_index].append(_normalize_link(from_index, attributes))
		link_count += 1


func nearest_index(world_position: Vector3) -> int:
	if points.is_empty():
		return -1
	var best_index := 0
	var best_distance := INF
	for index in range(points.size()):
		var distance := world_position.distance_squared_to(points[index])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func find_path(start_index: int, goal_index: int, danger_events: Array[Dictionary]) -> Array[int]:
	var empty_path: Array[int] = []
	if start_index < 0 or goal_index < 0:
		return empty_path
	if start_index == goal_index:
		return [start_index]
	var open: Array[int] = [start_index]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_index: 0.0}
	var f_score: Dictionary = {
		start_index: points[start_index].distance_to(points[goal_index])
	}
	while not open.is_empty():
		var current := open[0]
		var current_score := float(f_score.get(current, INF))
		for candidate in open:
			var candidate_score := float(f_score.get(candidate, INF))
			if candidate_score < current_score:
				current = candidate
				current_score = candidate_score
		if current == goal_index:
			var path: Array[int] = [current]
			while came_from.has(current):
				current = int(came_from[current])
				path.push_front(current)
			return path
		open.erase(current)
		for neighbor_variant in links[current]:
			var neighbor_record: Dictionary = neighbor_variant as Dictionary
			var neighbor := int(neighbor_record.get("to", -1))
			if neighbor < 0 or neighbor >= points.size():
				continue
			var tentative := float(g_score.get(current, INF)) + edge_cost(
				current, neighbor, neighbor_record, danger_events
			)
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + points[neighbor].distance_to(points[goal_index])
			if not open.has(neighbor):
				open.append(neighbor)
	return empty_path


func find_link(from_index: int, to_index: int, danger_events: Array[Dictionary]) -> Dictionary:
	if from_index < 0 or from_index >= links.size():
		return {}
	var best_link: Dictionary = {}
	var best_cost := INF
	for link_variant in links[from_index]:
		var link: Dictionary = link_variant as Dictionary
		if int(link.get("to", -1)) != to_index:
			continue
		var cost := edge_cost(from_index, to_index, link, danger_events)
		if cost < best_cost:
			best_cost = cost
			best_link = link.duplicate(true)
	return best_link


func links_at(index: int) -> Array:
	if index < 0 or index >= links.size():
		return []
	return links[index]


func edge_cost(
	from_index: int,
	to_index: int,
	link: Dictionary,
	danger_events: Array[Dictionary]
) -> float:
	var distance := points[from_index].distance_to(points[to_index])
	var dynamic_danger := 0.0
	if not danger_events.is_empty():
		var midpoint := (points[from_index] + points[to_index]) * 0.5
		for event_variant in danger_events:
			var event := event_variant as Dictionary
			var event_position := event.get("position", Vector3.ZERO) as Vector3
			var radius := maxf(1.0, float(event.get("radius", 8.0)))
			var event_distance := midpoint.distance_to(event_position)
			if event_distance <= radius:
				dynamic_danger = maxf(
					dynamic_danger,
					float(event.get("intensity", 0.0)) * (1.0 - event_distance / radius)
				)
	var danger_multiplier := 1.0 + clampf(float(link.get("danger", 0.0)), 0.0, 1.0) * 1.6 + dynamic_danger * 2.2
	var cover_multiplier := 1.0 - clampf(float(link.get("cover", 0.0)), 0.0, 1.0) * 0.24
	var traversal_multiplier := clampf(float(link.get("costMultiplier", 1.0)), 0.25, 4.0)
	if bool(link.get("crouch", false)):
		traversal_multiplier += 0.35
	if bool(link.get("ladder", false)):
		traversal_multiplier += 0.45
	return distance * danger_multiplier * cover_multiplier * traversal_multiplier


static func parse_points(points_variant: Variant) -> Array[Vector3]:
	var parsed: Array[Vector3] = []
	if not points_variant is Array:
		return parsed
	for point_variant in points_variant as Array:
		if not point_variant is Array:
			continue
		var point := point_variant as Array
		if point.size() >= 3:
			parsed.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		elif point.size() >= 2:
			parsed.append(Vector3(float(point[0]), 1.15, float(point[1])))
	return parsed


func _normalize_link(to_index: int, attributes: Dictionary) -> Dictionary:
	return {
		"to": to_index,
		"route": String(attributes.get("route", "")),
		"danger": clampf(float(attributes.get("danger", 0.0)), 0.0, 1.0),
		"cover": clampf(float(attributes.get("cover", 0.0)), 0.0, 1.0),
		"costMultiplier": clampf(float(attributes.get("costMultiplier", 1.0)), 0.25, 4.0),
		"precise": bool(attributes.get("precise", false)),
		"crouch": bool(attributes.get("crouch", false)),
		"ladder": bool(attributes.get("ladder", false)),
	}
