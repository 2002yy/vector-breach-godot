extends "res://tools/authoring/LandingStageProbePlayer.gd"
## Causal counterfactual only: preserve all native keys, consume jump at this boundary.

var immediate_jump := false


func _sample_movement_input() -> Dictionary:
	var previously_pressed := "Space" in held
	var sampled := super._sample_movement_input()
	if active and immediate_jump:
		sampled.jump = "Space" in held and not previously_pressed
		sampled.requested_jump_time = jump_command_time if sampled.jump else -1.0
	return sampled
