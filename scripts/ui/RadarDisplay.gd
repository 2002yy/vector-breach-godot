extends Control

const BACKGROUND_COLOR := Color(0.015, 0.022, 0.024, 0.82)
const GRID_COLOR := Color(0.62, 0.68, 0.62, 0.14)
const BORDER_COLOR := Color(0.82, 0.73, 0.38, 0.9)
const BOUNDARY_COLOR := Color(0.9, 0.82, 0.54, 0.72)
const WALL_COLOR := Color(0.75, 0.78, 0.7, 0.68)
const COVER_COLOR := Color(0.54, 0.62, 0.57, 0.56)
const LEVEL_COLOR := Color(0.42, 0.59, 0.64, 0.48)
const PLAYER_COLOR := Color(0.35, 0.95, 0.42, 1.0)
const FRIENDLY_COLOR := Color(0.32, 0.72, 1.0, 1.0)
const ENEMY_COLOR := Color(1.0, 0.3, 0.25, 1.0)
const C4_COLOR := Color(1.0, 0.72, 0.12, 1.0)

var _snapshot: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	queue_redraw()

func get_debug_snapshot() -> Dictionary:
	var bounds: Vector2 = _snapshot.get("bounds", Vector2.ZERO)
	var radar_range := float(_snapshot.get("range_meters", 0.0))
	var full_area := 4.0 * bounds.x * bounds.y
	return {
		"bounds": bounds,
		"range_meters": radar_range,
		"player_position": _snapshot.get("player_position", Vector2.ZERO),
		"player_yaw": float(_snapshot.get("player_yaw", 0.0)),
		"target_count": (_snapshot.get("targets", []) as Array).size(),
		"feature_count": (_snapshot.get("features", []) as Array).size(),
		"player_count": (_snapshot.get("players", []) as Array).size(),
		"c4_state": String((_snapshot.get("c4", {}) as Dictionary).get("state", "")),
		"width_fraction": radar_range / bounds.x if bounds.x > 0.0 else 0.0,
		"height_fraction": radar_range / bounds.y if bounds.y > 0.0 else 0.0,
		"area_fraction": PI * radar_range * radar_range / full_area if full_area > 0.0 else 0.0,
	}

func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(8.0, minf(size.x, size.y) * 0.47)
	draw_circle(center, radius, BACKGROUND_COLOR)
	_draw_grid(center, radius)
	var radar_range := maxf(1.0, float(_snapshot.get("range_meters", 24.0)))
	var player_world: Vector2 = _snapshot.get("player_position", Vector2.ZERO)
	var yaw := float(_snapshot.get("player_yaw", 0.0))
	var bounds: Vector2 = _snapshot.get("bounds", Vector2.ZERO)
	_draw_map_boundary(bounds, player_world, center, radius, radar_range, yaw)
	for feature_variant in _snapshot.get("features", []):
		_draw_feature(feature_variant as Dictionary, player_world, center, radius, radar_range, yaw)
	for target_variant in _snapshot.get("targets", []):
		_draw_target(target_variant as Dictionary, player_world, center, radius, radar_range, yaw)
	for player_variant in _snapshot.get("players", []):
		_draw_player(player_variant as Dictionary, player_world, center, radius, radar_range, yaw)
	_draw_c4(_snapshot.get("c4", {}) as Dictionary, player_world, center, radius, radar_range, yaw)
	_draw_north(center, radius, yaw)
	var arrow := PackedVector2Array([
		center + Vector2(0.0, -9.0),
		center + Vector2(-5.5, 6.5),
		center + Vector2(0.0, 4.0),
		center + Vector2(5.5, 6.5),
	])
	draw_colored_polygon(arrow, PLAYER_COLOR)
	draw_circle(center, radius, BORDER_COLOR, false, 2.0, true)

func _draw_grid(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.5, GRID_COLOR, false, 1.0, true)
	draw_circle(center, radius, GRID_COLOR, false, 1.0, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), GRID_COLOR, 1.0, true)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), GRID_COLOR, 1.0, true)

func _draw_map_boundary(bounds: Vector2, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float) -> void:
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		return
	var corners := [
		Vector2(-bounds.x, -bounds.y),
		Vector2(bounds.x, -bounds.y),
		Vector2(bounds.x, bounds.y),
		Vector2(-bounds.x, bounds.y),
	]
	for index in range(corners.size()):
		_draw_world_line(corners[index], corners[(index + 1) % corners.size()], player_world, center, radius, radar_range, yaw, BOUNDARY_COLOR, 1.7)

func _draw_feature(feature: Dictionary, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float) -> void:
	var position := Vector2(float(feature.get("x", 0.0)), float(feature.get("z", 0.0)))
	var half_size := Vector2(float(feature.get("sx", 1.0)), float(feature.get("sz", 1.0))) * 0.5
	if position.distance_to(player_world) > radar_range + half_size.length():
		return
	var role := String(feature.get("role", "wall"))
	var color := WALL_COLOR
	var width := 1.25
	if role in ["cover", "obstacle"]:
		color = COVER_COLOR
		width = 1.0
	elif role in ["stair", "ramp", "catwalk", "floor"]:
		color = LEVEL_COLOR
		width = 1.0
	_draw_world_rect(position, half_size, player_world, center, radius, radar_range, yaw, color, width)

func _draw_target(target: Dictionary, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float) -> void:
	var position := Vector2(float(target.get("x", 0.0)), float(target.get("z", 0.0)))
	var delta := position - player_world
	var label := String(target.get("label", "T"))
	var color := Color(0.95, 0.66, 0.2, 0.95) if label == "A" else Color(0.3, 0.72, 0.95, 0.95)
	if delta.length() <= radar_range:
		var half_size := Vector2(float(target.get("sx", 2.0)), float(target.get("sz", 2.0))) * 0.5
		_draw_world_rect(position, half_size, player_world, center, radius, radar_range, yaw, color, 1.6)
	var local_point := _transform_delta(delta, center, radius, radar_range, yaw)
	if delta.length() > radar_range:
		local_point = center + (local_point - center).normalized() * radius * 0.86
		color.a = 0.72
	draw_circle(local_point, 7.0, Color(color, 0.16))
	draw_circle(local_point, 7.0, color, false, 1.3, true)
	draw_string(ThemeDB.fallback_font, local_point + Vector2(-3.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)

func _draw_north(center: Vector2, radius: float, yaw: float) -> void:
	var north_point := center + Vector2(0.0, -radius * 0.82).rotated(yaw)
	var color := Color(0.92, 0.88, 0.68, 0.9)
	draw_circle(north_point, 3.0, color)
	draw_string(ThemeDB.fallback_font, north_point + Vector2(5.0, 4.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, color)

func _draw_player(record: Dictionary, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float) -> void:
	if bool(record.get("local", false)):
		return
	var friendly := String(record.get("team", "")) == String(_snapshot.get("local_team", "T"))
	if not friendly and not bool(record.get("spotted", false)):
		return
	var position := Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0)))
	var delta := position - player_world
	if delta.length() > radar_range:
		return
	var point := _transform_delta(delta, center, radius, radar_range, yaw)
	var color := FRIENDLY_COLOR if friendly else ENEMY_COLOR
	if not bool(record.get("alive", true)):
		draw_line(point + Vector2(-4, -4), point + Vector2(4, 4), color, 2.0)
		draw_line(point + Vector2(4, -4), point + Vector2(-4, 4), color, 2.0)
		return
	var direction := float(record.get("yaw", 0.0)) + yaw
	var arrow := PackedVector2Array([point + Vector2(0, -6).rotated(direction), point + Vector2(-4, 4).rotated(direction), point + Vector2(4, 4).rotated(direction)])
	draw_colored_polygon(arrow, color)
	var height_delta := float(record.get("y", 0.0)) - float(_snapshot.get("player_height", 0.0))
	if absf(height_delta) > 1.5:
		draw_string(ThemeDB.fallback_font, point + Vector2(5, 4), "↑" if height_delta > 0.0 else "↓", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)

func _draw_c4(record: Dictionary, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float) -> void:
	var state := String(record.get("state", ""))
	if state.is_empty() or state == "carried":
		return
	var position := Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0)))
	var delta := position - player_world
	var point := _transform_delta(delta, center, radius, radar_range, yaw)
	if delta.length() > radar_range:
		point = center + (point - center).normalized() * radius * 0.83
	var color := C4_COLOR if state == "dropped" else Color(1.0, 0.24, 0.12, 1.0)
	draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), color, true)
	draw_string(ThemeDB.fallback_font, point + Vector2(6, 4), "C4", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

func _draw_world_rect(position: Vector2, half_size: Vector2, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float, color: Color, width: float) -> void:
	var corners := [
		position + Vector2(-half_size.x, -half_size.y),
		position + Vector2(half_size.x, -half_size.y),
		position + Vector2(half_size.x, half_size.y),
		position + Vector2(-half_size.x, half_size.y),
	]
	for index in range(corners.size()):
		_draw_world_line(corners[index], corners[(index + 1) % corners.size()], player_world, center, radius, radar_range, yaw, color, width)

func _draw_world_line(world_from: Vector2, world_to: Vector2, player_world: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float, color: Color, width: float) -> void:
	var from := _transform_delta(world_from - player_world, center, radius, radar_range, yaw)
	var to := _transform_delta(world_to - player_world, center, radius, radar_range, yaw)
	var clipped := _clip_line_to_circle(from, to, center, radius - 2.0)
	if clipped.size() == 2:
		draw_line(clipped[0], clipped[1], color, width, true)

func _transform_delta(delta: Vector2, center: Vector2, radius: float, radar_range: float, yaw: float) -> Vector2:
	return center + delta.rotated(yaw) * (radius / radar_range)

func _clip_line_to_circle(from: Vector2, to: Vector2, center: Vector2, radius: float) -> PackedVector2Array:
	var from_inside := from.distance_squared_to(center) <= radius * radius
	var to_inside := to.distance_squared_to(center) <= radius * radius
	if from_inside and to_inside:
		return PackedVector2Array([from, to])
	var direction := to - from
	var a := direction.dot(direction)
	if a <= 0.000001:
		return PackedVector2Array()
	var offset := from - center
	var b := 2.0 * offset.dot(direction)
	var c := offset.dot(offset) - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return PackedVector2Array()
	var root := sqrt(discriminant)
	var first := (-b - root) / (2.0 * a)
	var second := (-b + root) / (2.0 * a)
	var start_t := maxf(0.0, minf(first, second))
	var end_t := minf(1.0, maxf(first, second))
	if start_t > end_t:
		return PackedVector2Array()
	return PackedVector2Array([from + direction * start_t, from + direction * end_t])
