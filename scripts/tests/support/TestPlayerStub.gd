extends CharacterBody3D

var recoil_events: Array[Dictionary] = []

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

func get_camera_node() -> Camera3D:
	return camera

func apply_recoil_kick(pitch_radians: float, yaw_radians: float) -> void:
	recoil_events.append({
		"pitch": pitch_radians,
		"yaw": yaw_radians
	})
