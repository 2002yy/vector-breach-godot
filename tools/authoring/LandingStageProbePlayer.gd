extends "res://tools/authoring/NativeRoutePlayer.gd"
## Authoring-only observation/ablation. No shipped player rule is replaced.

var ablation := "baseline"
var stages: Array[Dictionary] = []


func _sample_movement_input() -> Dictionary:
	stages.clear()
	return super._sample_movement_input()


func _snapshot() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"grounded": is_on_floor(),
		"floor_normal": [get_floor_normal().x, get_floor_normal().y, get_floor_normal().z]
	}


func _record_stage(name: String, before: Dictionary, enabled: bool) -> void:
	if active:
		stages.append({"stage": name, "enabled": enabled, "before": before, "after": _snapshot()})


func _pre_step_up(motion: Vector3) -> void:
	var before := _snapshot()
	if ablation != "no_pre":
		super._pre_step_up(motion)
	_record_stage("pre_step", before, ablation != "no_pre")


func _try_step_up(position_before: Vector3, motion: Vector3) -> void:
	var before := _snapshot()
	if ablation != "no_try":
		super._try_step_up(position_before, motion)
	_record_stage("post_step", before, ablation != "no_try")


func _snap_to_floor() -> void:
	var before := _snapshot()
	if ablation != "no_snap":
		super._snap_to_floor()
	_record_stage("snap", before, ablation != "no_snap")
