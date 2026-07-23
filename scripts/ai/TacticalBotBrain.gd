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
	_route_index = _nearest_route_index()
	_route_direction = -1 if String(actor.get("team")) == "CT" else 1
	ammo_in_mag = magazine_size
	_reset_runtime()

func tick(delta: float) -> void:
	if actor == null or not enabled or bool(actor.get("is_dead")):
		return
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)
	_burst_pause = maxf(0.0, _burst_pause - delta)
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
	var planar := destination - actor.global_position
	planar.y = 0.0
	if planar.length_squared() <= 0.01:
		_stop(delta)
		return
	var direction := planar.normalized()
	if actor.test_move(actor.global_transform, direction * 0.45):
		var left := direction.rotated(Vector3.UP, PI * 0.5)
		var right := direction.rotated(Vector3.UP, -PI * 0.5)
		direction = left if not actor.test_move(actor.global_transform, left * 0.45) else right
	_aim_at(actor.global_position + direction, delta, 0.18)
	actor.call("apply_ai_navigation", direction, move_speed, destination.y, delta)

func _stop(delta: float) -> void:
	actor.velocity.x = move_toward(actor.velocity.x, 0.0, 22.0 * delta)
	actor.velocity.z = move_toward(actor.velocity.z, 0.0, 22.0 * delta)

func _aim_at(target_position: Vector3, delta: float, duration: float) -> void:
	var direction := target_position - actor.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	actor.rotation.y = lerp_angle(actor.rotation.y, desired_yaw, clampf(delta / maxf(duration, 0.01), 0.0, 1.0))

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
