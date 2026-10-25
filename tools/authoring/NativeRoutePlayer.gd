extends "res://scripts/player/PlayerController.gd"
## Synthetic key/mouse events through InputMap and the shipped player sampler.
## Discovery feedback is disabled during frozen open-loop replay.

const KEYS := {
	"W": KEY_W,
	"A": KEY_A,
	"S": KEY_S,
	"D": KEY_D,
	"Space": KEY_SPACE,
	"Ctrl": KEY_CTRL,
	"Shift": KEY_SHIFT
}
var timeline: Array[Dictionary] = []
var active := false
var feedback := false
var feedback_walk := false
var waypoints: Array[Vector3] = []
var waypoint_index := 0
var tick := 0
var event_index := 0
var held: Array = []
var last_command := {"keys": [], "mouse_dx": 0.0}
var mouse_events_seen := 0
var key_events_seen := 0
var last_mouse := {}
var jump_command_time := -1.0


func _input(event: InputEvent) -> void:
	var yaw_before := rotation.y
	if active and event is InputEventMouseMotion:
		mouse_events_seen += 1
	if active and event is InputEventKey:
		key_events_seen += 1
	super._input(event)
	if active and event is InputEventMouseMotion:
		last_mouse = {
			"dx": event.relative.x,
			"before": yaw_before,
			"after": rotation.y,
			"sensitivity": mouse_sensitivity
		}


func _sample_movement_input() -> Dictionary:
	if not active:
		return super._sample_movement_input()
	var time := float(tick) / Engine.physics_ticks_per_second
	tick += 1
	var command := {"keys": held.duplicate(), "mouse_dx": 0.0}
	if feedback:
		command = _discover_command()
	else:
		while event_index < timeline.size() and float(timeline[event_index].at) <= time + 0.000001:
			var event := timeline[event_index]
			command.keys = event.keys.duplicate()
			command.mouse_dx += float(event.get("mouse_dx", 0.0))
			event_index += 1
	if "Space" in command.keys and "Space" not in held:
		jump_command_time = time
	_apply_command(command)
	last_command = command.duplicate(true)
	var sampled := super._sample_movement_input()
	sampled["sample_time"] = time
	sampled["requested_jump_time"] = jump_command_time if sampled.jump else -1.0
	return sampled


func _discover_command() -> Dictionary:
	while waypoint_index < waypoints.size():
		var difference := waypoints[waypoint_index] - global_position
		if Vector2(difference.x, difference.z).length() > 0.25 or absf(difference.y) > 0.4:
			break
		waypoint_index += 1
	if waypoint_index == waypoints.size():
		return {"keys": [], "mouse_dx": 0.0}
	var wish := waypoints[waypoint_index] - global_position
	var desired_yaw := atan2(-wish.x, -wish.z)
	var error := wrapf(desired_yaw - rotation.y, -PI, PI)
	var dx := roundf(clampf(-error / mouse_sensitivity, -120.0, 120.0))
	var keys: Array = ["W"] if absf(error) < deg_to_rad(30.0) else []
	if feedback_walk:
		keys.append("Shift")
	return {"keys": keys, "mouse_dx": dx}


func _apply_command(command: Dictionary) -> void:
	for name in KEYS:
		if (name in command.keys) == (name in held):
			continue
		var event := InputEventKey.new()
		event.keycode = KEYS[name]
		event.physical_keycode = KEYS[name]
		event.pressed = name in command.keys
		Input.parse_input_event(event)
	held = command.keys.duplicate()
	if not is_zero_approx(float(command.mouse_dx)):
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(command.mouse_dx, 0.0)
		Input.parse_input_event(motion)
	Input.flush_buffered_events()
