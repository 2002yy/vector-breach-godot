extends "res://tools/authoring/LandingStageProbePlayer.gd"
## Fixed-fps diagnostic producer: queue native events before the next physics sample.

var queued_input := false
var pending := false
var pending_command := {}


func _ready() -> void:
	super._ready()
	get_tree().process_frame.connect(_queue_next_input)


func _queue_next_input() -> void:
	if not active or not queued_input or is_queued_for_deletion():
		return
	var time := float(tick) / Engine.physics_ticks_per_second
	var command := {"keys": held.duplicate(), "mouse_dx": 0.0}
	while event_index < timeline.size() and float(timeline[event_index].at) <= time + 0.000001:
		command.keys = timeline[event_index].keys.duplicate()
		command.mouse_dx += float(timeline[event_index].get("mouse_dx", 0.0))
		event_index += 1
	if "Space" in command.keys and "Space" not in held:
		jump_command_time = time
	_apply_command(command)
	pending_command = command.duplicate(true)
	pending = true


func _sample_movement_input() -> Dictionary:
	var sampled := super._sample_movement_input()
	if active and queued_input and pending:
		last_command = pending_command.duplicate(true)
		pending = false
	return sampled
