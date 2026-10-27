extends "res://tools/authoring/ModernVerticalQuadraturePlayer.gd"
## Author-only support synchronization after an actual custom floor snap.

var support_enabled := false
var support_sample := {}
var landing_events := 0


func _ready() -> void:
	landed.connect(
		func(_position: Vector3, _surface: String, _intensity: float): landing_events += 1
	)
	super._ready()


func _physics_process(delta: float) -> void:
	support_sample = {"enabled": support_enabled, "attempted": false}
	super._physics_process(delta)


func _snap_to_floor() -> void:
	var before := global_position
	var floor_before := is_on_floor()
	super._snap_to_floor()
	if (
		not support_enabled
		or not _vertical_active
		or not movement_enabled
		or is_on_ladder
		or is_in_water
		or global_position.distance_to(before) < 0.000001
	):
		return
	# Ask the engine to establish real capsule support. No synthetic grounded flag.
	apply_floor_snap()
	support_sample = {
		"enabled": true,
		"attempted": true,
		"position_before": [before.x, before.y, before.z],
		"position_after": [global_position.x, global_position.y, global_position.z],
		"grounded_before": floor_before,
		"grounded_after": is_on_floor(),
		"floor_normal": [get_floor_normal().x, get_floor_normal().y, get_floor_normal().z]
	}
	if not stages.is_empty() and stages[-1].stage == "snap":
		stages[-1].after = _snapshot()
