extends RefCounted
## Detect motion inside a small area even when every individual step is nonzero.

var attempts := 0
var stalled_seconds := 0.0
var _anchor := Vector3.INF
var _goal := Vector3.INF


func reset() -> void:
	attempts = 0
	stalled_seconds = 0.0
	_anchor = Vector3.INF
	_goal = Vector3.INF


func observe(position: Vector3, goal: Vector3, delta: float) -> bool:
	if not _anchor.is_finite():
		_anchor = position
		stalled_seconds = 0.0
		attempts = 0
	# New radio reports can change the goal every second while the actor stays
	# blocked. A new intention is not proof of physical route progress.
	_goal = goal
	if position.distance_to(_anchor) >= 1.5:
		_anchor = position
		stalled_seconds = 0.0
		attempts = 0
		return false
	stalled_seconds += delta
	if stalled_seconds < 5.0:
		return false
	attempts += 1
	stalled_seconds = 0.0
	return true
