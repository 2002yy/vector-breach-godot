extends "res://tools/authoring/QueuedKeyProbePlayer.gd"
## Observe actual engine process/physics counters, not a declared loop ratio.

var enforce_cadence := false
var rejection_path := ""
var last_process := -1
var last_cadence := {}


func _sample_movement_input() -> Dictionary:
	var sample_tick := tick
	var had_pending := pending
	var process_frame := Engine.get_process_frames()
	var index_before := event_index
	var sampled := super._sample_movement_input()
	if active:
		var delta := process_frame - last_process if last_process >= 0 else -1
		last_cadence = {
			"tick": sample_tick,
			"process_frame": process_frame,
			"physics_frame": Engine.get_physics_frames(),
			"process_delta": delta,
			"prequeued": had_pending,
			"inline_events": event_index - index_before,
			"violation": queued_input and sample_tick > 0 and (delta != 1 or not had_pending)
		}
		last_process = process_frame
	return sampled
