extends Node

enum State {
	HOLD,
	PATROL,
	INVESTIGATE,
	ACQUIRE,
	ENGAGE,
	RELOAD,
}

var actor: CharacterBody3D
var enabled: bool = false
var state: State = State.HOLD
var move_speed: float = 4.35
var view_distance: float = 34.0
var field_of_view_degrees: float = 110.0
var reaction_time: float = 0.34
var aim_acquisition_time: float = 0.30
var aim_tracking_time: float = 0.16
var hearing_memory_seconds: float = 4.0
var magazine_size: int = 30
var ammo_in_mag: int = 30
var reload_duration: float = 2.35
var rifle_damage: int = 18
var burst_size: int = 3
var shot_interval: float = 0.095
var burst_cooldown: float = 0.45

var _route_points: Array[Vector3] = []
var _route_index: int = 0
var _route_direction: int = 1
var _navigation_points: Array[Vector3] = []
var _navigation_links: Array = []
var _navigation_path: Array[int] = []
var _navigation_path_index: int = 0
var _navigation_destination: Vector3 = Vector3.INF
var _repath_seconds: float = 0.0
var _active_navigation_link: Dictionary = {}
var _navigation_link_count: int = 0
var _last_progress_position: Vector3 = Vector3.ZERO
var _no_progress_seconds: float = 0.0
var _recovery_seconds: float = 0.0
var _recovery_direction: Vector3 = Vector3.ZERO
var _recovery_flip: bool = false
var _stuck_recoveries: int = 0
var _target: CharacterBody3D
var _last_known_position: Vector3 = Vector3.ZERO
var _heard_seconds: float = 999.0
var _visible_seconds: float = 0.0
var _shot_cooldown: float = 0.0
var _burst_pause: float = 0.0
var _shots_in_burst: int = 0
var _reload_seconds: float = 0.0
var _shot_count: int = 0
var _rng := RandomNumberGenerator.new()

func setup(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor
	_rng.seed = owner_actor.get_instance_id()

func configure(record: Dictionary) -> void:
	enabled = bool(record.get("aiEnabled", false))
	move_speed = clampf(float(record.get("aiMoveSpeed", move_speed)), 1.5, 6.2)
	view_distance = clampf(float(record.get("aiViewDistance", view_distance)), 8.0, 60.0)
	field_of_view_degrees = clampf(float(record.get("aiFovDegrees", field_of_view_degrees)), 40.0, 180.0)
	reaction_time = clampf(float(record.get("aiReactionTime", reaction_time)), 0.05, 1.5)
	aim_acquisition_time = clampf(float(record.get("aiAimAcquisitionTime", aim_acquisition_time)), 0.05, 1.2)
	rifle_damage = clampi(int(record.get("aiDamage", rifle_damage)), 1, 100)
	_route_points = _parse_route_points(record.get("routePoints", []))
	_parse_navigation_graph(record.get("navigationGraph", {}))
	_route_index = _nearest_route_index()
	_route_direction = -1 if String(actor.get("team")) == "CT" else 1
	ammo_in_mag = magazine_size
	_reset_runtime()

func tick(delta: float) -> void:
	if actor == null or not enabled or bool(actor.get("is_dead")):
		return
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)
	_burst_pause = maxf(0.0, _burst_pause - delta)
	_repath_seconds = maxf(0.0, _repath_seconds - delta)
	_heard_seconds += delta
	if not RoundManager.can_player_move():
		state = State.HOLD
		_stop(delta)
		return
	if state == State.RELOAD:
		_tick_reload(delta)
		return

	_target = _find_local_target()
	var visible := _target != null and _can_see(_target)
	if visible:
		_last_known_position = _target.global_position
		_visible_seconds += delta
		if _visible_seconds < reaction_time:
			state = State.ACQUIRE
			_aim_at(_target.global_position + Vector3.UP * 0.18, delta, aim_acquisition_time)
			_stop(delta)
		else:
			state = State.ENGAGE
			_tick_engage(delta)
		return
	_visible_seconds = 0.0

	if _heard_seconds <= hearing_memory_seconds:
		state = State.INVESTIGATE
		if actor.global_position.distance_to(_last_known_position) <= 1.0:
			_stop(delta)
		else:
			_move_toward(_last_known_position, delta)
		return
	state = State.PATROL if not _route_points.is_empty() else State.HOLD
	if state == State.PATROL:
		_tick_patrol(delta)
	else:
		_stop(delta)

func notify_sound(world_position: Vector3, audible_radius: float, source_team: String) -> bool:
	if not enabled or source_team == String(actor.get("team")):
		return false
	if actor.global_position.distance_to(world_position) > audible_radius:
		return false
	_last_known_position = world_position
	_heard_seconds = 0.0
	return true

func get_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"state": State.keys()[state],
		"ammo": ammo_in_mag,
		"shots": _shot_count,
		"route_points": _route_points.size(),
		"navigation_nodes": _navigation_points.size(),
		"navigation_links": _navigation_link_count,
		"navigation_path_nodes": maxi(0, _navigation_path.size() - _navigation_path_index),
		"active_navigation_link": _active_navigation_link.duplicate(true),
		"stuck_seconds": _no_progress_seconds,
		"stuck_recoveries": _stuck_recoveries,
		"recovering": _recovery_seconds > 0.0,
		"last_known_position": _last_known_position,
		"heard_seconds": _heard_seconds,
		"target_visible_seconds": _visible_seconds,
	}

func reset_runtime() -> void:
	ammo_in_mag = magazine_size
	_reset_runtime()

func _reset_runtime() -> void:
	state = State.HOLD
	_target = null
	_last_known_position = actor.global_position if actor != null else Vector3.ZERO
	_heard_seconds = 999.0
	_visible_seconds = 0.0
	_shot_cooldown = 0.0
	_burst_pause = 0.0
	_shots_in_burst = 0
	_reload_seconds = 0.0
	_navigation_path.clear()
	_navigation_path_index = 0
	_navigation_destination = Vector3.INF
	_repath_seconds = 0.0
	_active_navigation_link.clear()
	_last_progress_position = actor.global_position if actor != null else Vector3.ZERO
	_no_progress_seconds = 0.0
	_recovery_seconds = 0.0
	_recovery_direction = Vector3.ZERO
	_recovery_flip = false
	_stuck_recoveries = 0

func _find_local_target() -> CharacterBody3D:
	var candidate := actor.get_tree().get_first_node_in_group("local_player")
	if candidate is CharacterBody3D and not bool(candidate.get("is_dead")) and String(actor.get("team")) != GameState.player_team:
		return candidate as CharacterBody3D
	return null

func _can_see(target: CharacterBody3D) -> bool:
	var eye := actor.call("get_eye_position") as Vector3
	var target_point := target.global_position + Vector3.UP * 0.18
	var delta := target_point - eye
	if delta.length() > view_distance or delta.length_squared() <= 0.001:
		return false
	var forward := -actor.global_transform.basis.z
	if forward.dot(delta.normalized()) < cos(deg_to_rad(field_of_view_degrees * 0.5)):
		return false
	if _segment_blocked_by_smoke(eye, target_point):
		return false
	# Cast slightly through the target. Godot can omit a body when the ray ends
	# inside its collision shape, which made close-range visibility unreliable.
	var query := PhysicsRayQueryParameters3D.create(eye, target_point + delta.normalized() * 0.75, 1)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider", null) == target

func _tick_engage(delta: float) -> void:
	if _target == null:
		return
	var target_point: Vector3 = _target.global_position + Vector3.UP * 0.18
	_aim_at(target_point, delta, aim_tracking_time)
	_stop(delta)
	if Vector2(actor.velocity.x, actor.velocity.z).length() > 0.42:
		return
	if ammo_in_mag <= 0:
		state = State.RELOAD
		_reload_seconds = reload_duration
		return
	var forward: Vector3 = -actor.global_transform.basis.z
	var eye_position := actor.call("get_eye_position") as Vector3
	var aim_direction: Vector3 = (target_point - eye_position).normalized()
	var planar_aim := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if forward.dot(planar_aim) < cos(deg_to_rad(3.2)):
		return
	if _shot_cooldown > 0.0 or _burst_pause > 0.0:
		return
	_fire_shot(target_point)

func _fire_shot(target_point: Vector3) -> void:
	ammo_in_mag -= 1
	_shot_count += 1
	_shots_in_burst += 1
	_shot_cooldown = shot_interval
	var origin := actor.call("get_eye_position") as Vector3
	var direction: Vector3 = (target_point - origin).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(direction).normalized()
	var error_scale := 0.0045 + float(_shots_in_burst - 1) * 0.0025
	direction = (direction + right * _rng.randf_range(-error_scale, error_scale) + up * _rng.randf_range(-error_scale, error_scale)).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * view_distance, 1)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var damage_result: Dictionary = {}
	if not hit.is_empty():
		var collider: Variant = hit.get("collider", null)
		if collider != null and collider.has_method("apply_hitscan_damage"):
			var collider_team := ""
			if collider is Node and (collider as Node).is_in_group("combat_actors"):
				collider_team = String((collider as Node).get("team"))
			elif collider is Node and (collider as Node).is_in_group("local_player"):
				collider_team = GameState.player_team
			var same_team := not collider_team.is_empty() and collider_team == String(actor.get("team"))
			if not same_team:
				damage_result = collider.call("apply_hitscan_damage", rifle_damage, hit.get("position", Vector3.ZERO), 0.77, false) as Dictionary
	actor.call("emit_ai_shot", {
		"hit": bool(damage_result.get("hit", false)),
		"position": hit.get("position", origin + direction * view_distance),
		"damage_result": damage_result,
		"weapon_slot": 0,
		"weapon_name": "AI步枪",
		"shooter_team": String(actor.get("team")),
	}, origin)
	if _shots_in_burst >= burst_size:
		_shots_in_burst = 0
		_burst_pause = burst_cooldown

func _tick_reload(delta: float) -> void:
	_stop(delta)
	_reload_seconds = maxf(0.0, _reload_seconds - delta)
	if _reload_seconds == 0.0:
		ammo_in_mag = magazine_size
		state = State.ACQUIRE

func _tick_patrol(delta: float) -> void:
	if _route_points.is_empty():
		_stop(delta)
		return
	var destination := _route_points[_route_index]
	if actor.global_position.distance_to(destination) <= 1.0:
		_route_index += _route_direction
		if _route_index < 0 or _route_index >= _route_points.size():
			_route_direction *= -1
			_route_index = clampi(_route_index, 0, _route_points.size() - 1)
		destination = _route_points[_route_index]
	_move_toward(destination, delta)

func _move_toward(destination: Vector3, delta: float) -> void:
	var steering_target := _resolve_navigation_target(destination)
	var planar := steering_target - actor.global_position
	planar.y = 0.0
	if planar.length_squared() <= 0.01:
		_stop(delta)
		return
	var desired_direction := planar.normalized()
	_update_navigation_progress(delta, desired_direction)
	var direction := desired_direction
	if _recovery_seconds > 0.0:
		_recovery_seconds = maxf(0.0, _recovery_seconds - delta)
		direction = _choose_open_recovery_direction(_recovery_direction, desired_direction)
	elif actor.test_move(actor.global_transform, direction * 0.45):
		var left := direction.rotated(Vector3.UP, PI * 0.5)
		var right := direction.rotated(Vector3.UP, -PI * 0.5)
		if not actor.test_move(actor.global_transform, left * 0.45):
			direction = left
		elif not actor.test_move(actor.global_transform, right * 0.45):
			direction = right
	var precise := bool(_active_navigation_link.get("precise", false))
	var crouch := bool(_active_navigation_link.get("crouch", false))
	var movement_scale := 0.54 if crouch else (0.72 if precise else 1.0)
	actor.call("set_ai_crouching", crouch)
	_aim_at(actor.global_position + direction, delta, 0.18)
	actor.call("apply_ai_navigation", direction, move_speed * movement_scale, steering_target.y, delta)

func _stop(delta: float) -> void:
	if actor != null and actor.has_method("set_ai_crouching"):
		actor.call("set_ai_crouching", false)
	actor.velocity.x = move_toward(actor.velocity.x, 0.0, 22.0 * delta)
	actor.velocity.z = move_toward(actor.velocity.z, 0.0, 22.0 * delta)
	_last_progress_position = actor.global_position
	_no_progress_seconds = 0.0
	_recovery_seconds = 0.0

func _aim_at(target_position: Vector3, delta: float, duration: float) -> void:
	var direction := target_position - actor.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	actor.rotation.y = lerp_angle(actor.rotation.y, desired_yaw, clampf(delta / maxf(duration, 0.01), 0.0, 1.0))

func _resolve_navigation_target(destination: Vector3) -> Vector3:
	if _navigation_points.is_empty() or actor.global_position.distance_to(destination) <= 2.2:
		_active_navigation_link.clear()
		return destination
	var destination_changed := (
		not _navigation_destination.is_finite()
		or _navigation_destination.distance_to(destination) > 1.8
	)
	if destination_changed or _repath_seconds <= 0.0 or _navigation_path.is_empty():
		_navigation_destination = destination
		_navigation_path = _find_navigation_path(
			_nearest_navigation_index(actor.global_position),
			_nearest_navigation_index(destination)
		)
		_navigation_path_index = 0
		_repath_seconds = 0.65
	while _navigation_path_index < _navigation_path.size():
		var point := _navigation_points[_navigation_path[_navigation_path_index]]
		var arrival_radius := 0.55 if bool(_active_navigation_link.get("precise", false)) else 1.05
		if actor.global_position.distance_to(point) > arrival_radius:
			if _navigation_path_index > 0:
				_active_navigation_link = _find_navigation_link(
					_navigation_path[_navigation_path_index - 1],
					_navigation_path[_navigation_path_index]
				)
			return point
		_navigation_path_index += 1
	_active_navigation_link.clear()
	return destination

func _find_navigation_path(start_index: int, goal_index: int) -> Array[int]:
	var empty_path: Array[int] = []
	if start_index < 0 or goal_index < 0:
		return empty_path
	if start_index == goal_index:
		return [start_index]
	var open: Array[int] = [start_index]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_index: 0.0}
	var f_score: Dictionary = {
		start_index: _navigation_points[start_index].distance_to(_navigation_points[goal_index])
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
		for neighbor_variant in _navigation_links[current]:
			var neighbor_record: Dictionary = neighbor_variant as Dictionary
			var neighbor := int(neighbor_record.get("to", -1))
			if neighbor < 0 or neighbor >= _navigation_points.size():
				continue
			var tentative := float(g_score.get(current, INF)) + _navigation_edge_cost(current, neighbor, neighbor_record)
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _navigation_points[neighbor].distance_to(_navigation_points[goal_index])
			if not open.has(neighbor):
				open.append(neighbor)
	return empty_path

func _nearest_navigation_index(world_position: Vector3) -> int:
	if _navigation_points.is_empty():
		return -1
	var best_index := 0
	var best_distance := INF
	for index in range(_navigation_points.size()):
		var distance := world_position.distance_squared_to(_navigation_points[index])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _parse_navigation_graph(graph_variant: Variant) -> void:
	_navigation_points.clear()
	_navigation_links.clear()
	_navigation_link_count = 0
	if not graph_variant is Dictionary:
		return
	var graph := graph_variant as Dictionary
	_navigation_points = _parse_route_points(graph.get("points", []))
	_navigation_links.resize(_navigation_points.size())
	for index in range(_navigation_links.size()):
		_navigation_links[index] = []
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
			from_index < 0 or from_index >= _navigation_links.size()
			or to_index < 0 or to_index >= _navigation_links.size()
			or from_index == to_index
		):
			continue
		_navigation_links[from_index].append(_normalize_navigation_link(to_index, attributes))
		_navigation_links[to_index].append(_normalize_navigation_link(from_index, attributes))
		_navigation_link_count += 1

func _normalize_navigation_link(to_index: int, attributes: Dictionary) -> Dictionary:
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

func _navigation_edge_cost(from_index: int, to_index: int, link: Dictionary) -> float:
	var distance := _navigation_points[from_index].distance_to(_navigation_points[to_index])
	var danger_multiplier := 1.0 + clampf(float(link.get("danger", 0.0)), 0.0, 1.0) * 1.6
	var cover_multiplier := 1.0 - clampf(float(link.get("cover", 0.0)), 0.0, 1.0) * 0.24
	var traversal_multiplier := clampf(float(link.get("costMultiplier", 1.0)), 0.25, 4.0)
	if bool(link.get("crouch", false)):
		traversal_multiplier += 0.35
	if bool(link.get("ladder", false)):
		traversal_multiplier += 0.45
	return distance * danger_multiplier * cover_multiplier * traversal_multiplier

func _find_navigation_link(from_index: int, to_index: int) -> Dictionary:
	if from_index < 0 or from_index >= _navigation_links.size():
		return {}
	var best_link: Dictionary = {}
	var best_cost := INF
	for link_variant in _navigation_links[from_index]:
		var link: Dictionary = link_variant as Dictionary
		if int(link.get("to", -1)) != to_index:
			continue
		var cost := _navigation_edge_cost(from_index, to_index, link)
		if cost < best_cost:
			best_cost = cost
			best_link = link.duplicate(true)
	return best_link

func _update_navigation_progress(delta: float, desired_direction: Vector3) -> void:
	var traveled := Vector2(
		actor.global_position.x - _last_progress_position.x,
		actor.global_position.z - _last_progress_position.z
	).length()
	if traveled >= 0.18:
		_last_progress_position = actor.global_position
		_no_progress_seconds = 0.0
		return
	_no_progress_seconds += delta
	if _no_progress_seconds < 0.75 or _recovery_seconds > 0.0:
		return
	_recovery_flip = not _recovery_flip
	var side_angle := PI * 0.5 if _recovery_flip else -PI * 0.5
	var lateral := desired_direction.rotated(Vector3.UP, side_angle)
	_recovery_direction = (-desired_direction + lateral * 0.65).normalized()
	_recovery_seconds = 0.68
	_stuck_recoveries += 1
	_no_progress_seconds = 0.0
	_last_progress_position = actor.global_position
	_navigation_path.clear()
	_navigation_path_index = 0
	_repath_seconds = 0.0

func _choose_open_recovery_direction(preferred: Vector3, desired_direction: Vector3) -> Vector3:
	var candidates := [
		preferred,
		-desired_direction,
		desired_direction.rotated(Vector3.UP, PI * 0.5),
		desired_direction.rotated(Vector3.UP, -PI * 0.5),
	]
	for candidate_variant in candidates:
		var candidate := candidate_variant as Vector3
		if not actor.test_move(actor.global_transform, candidate * 0.45):
			return candidate
	return preferred

func _parse_route_points(points_variant: Variant) -> Array[Vector3]:
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

func _nearest_route_index() -> int:
	if actor == null or _route_points.is_empty():
		return 0
	var best_index := 0
	var best_distance := INF
	for index in range(_route_points.size()):
		var distance := actor.global_position.distance_squared_to(_route_points[index])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _segment_blocked_by_smoke(from: Vector3, to: Vector3) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false
	for smoke in actor.get_tree().get_nodes_in_group("smoke_volumes"):
		if smoke is Node3D:
			var t := clampf(((smoke as Node3D).global_position - from).dot(segment) / length_squared, 0.0, 1.0)
			if (from + segment * t).distance_to((smoke as Node3D).global_position) <= 3.1:
				return true
	return false
