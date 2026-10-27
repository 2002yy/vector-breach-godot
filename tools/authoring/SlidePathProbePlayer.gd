extends "res://tools/authoring/QueueCadenceProbePlayer.gd"
## Capture before helper moves/teleports can obscure the central slide's endpoint.

const Receipt = preload("res://tools/authoring/SlidePathReceipt.gd")
var slide_path := {}


func _sample_movement_input() -> Dictionary:
	slide_path = {}
	return super._sample_movement_input()


func _capture(stage: String) -> void:
	if active and slide_path.is_empty():
		slide_path = Receipt.capture(self, stage)


func _try_step_up(position_before: Vector3, motion: Vector3) -> void:
	_capture("before_post_step")
	super._try_step_up(position_before, motion)


func _snap_to_floor() -> void:
	_capture("before_snap")
	super._snap_to_floor()


func _update_camera_motion(delta: float, move_dir: Vector3) -> void:
	_capture("before_camera")
	super._update_camera_motion(delta, move_dir)
