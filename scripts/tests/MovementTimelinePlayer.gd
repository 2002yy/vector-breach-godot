extends "res://scripts/player/PlayerController.gd"
## Physical-boundary input fixture; no asynchronous Input singleton mutation.

var timeline: Array[Dictionary] = []
var timeline_tick := 0
var event_index := 0
var active := false
var native_input := false
var native_held := {}
var held := {"direction": Vector2.ZERO, "jump": false, "crouch": false, "walk": false}


func _sample_movement_input() -> Dictionary:
	if not active:
		return super._sample_movement_input()
	var sample_time := float(timeline_tick) / Engine.physics_ticks_per_second
	timeline_tick += 1
	var old_jump: bool = held.jump
	var requested_time := -1.0
	while (
		event_index < timeline.size() and float(timeline[event_index].at) <= sample_time + 0.000001
	):
		var event := timeline[event_index]
		for key in ["direction", "jump", "crouch", "walk"]:
			if key in event:
				held[key] = event[key]
		if bool(event.get("jump", false)):
			requested_time = event.at
		event_index += 1
	var result := held.duplicate()
	result.jump = bool(held.jump) and not old_jump
	result["sample_time"] = sample_time
	result["requested_jump_time"] = requested_time
	if native_input:
		var actions := {
			"move_forward": held.direction.y < 0.0,
			"jump": held.jump,
			"crouch": held.crouch,
			"walk": held.walk,
		}
		for action in actions:
			if bool(actions[action]) != bool(native_held.get(action, false)):
				var event := InputEventAction.new()
				event.action = action
				event.pressed = actions[action]
				Input.parse_input_event(event)
				native_held[action] = actions[action]
		var sampled := super._sample_movement_input()
		sampled["sample_time"] = sample_time
		sampled["requested_jump_time"] = requested_time
		return sampled
	return result
