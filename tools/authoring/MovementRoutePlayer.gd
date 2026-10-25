extends "res://scripts/tests/MovementTimelinePlayer.gd"
## Discovery feedback only. Captured inputs must be frozen and replayed separately.

var feedback := false
var feedback_walk := false
var waypoints: Array[Vector3] = []
var waypoint_index := 0


func _sample_movement_input() -> Dictionary:
	if not active or not feedback:
		return super._sample_movement_input()
	var time := float(timeline_tick) / Engine.physics_ticks_per_second
	timeline_tick += 1
	while waypoint_index < waypoints.size():
		var difference := waypoints[waypoint_index] - global_position
		if Vector2(difference.x, difference.z).length() > 0.16 or absf(difference.y) > 0.35:
			break
		waypoint_index += 1
	var direction := Vector2.ZERO
	if waypoint_index < waypoints.size():
		var wish := waypoints[waypoint_index] - global_position
		wish.y = 0.0
		var local := global_basis.inverse() * wish.normalized()
		direction = Vector2(local.x, local.z)
	return {
		"direction": direction,
		"jump": false,
		"walk": feedback_walk,
		"crouch": false,
		"sample_time": time,
		"requested_jump_time": -1.0
	}
