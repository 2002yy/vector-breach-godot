extends "res://tools/authoring/audit_landing_stages.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/JumpEdgeProbePlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, scheme: String, mode: String
) -> void:
	super._configure_trial_player(player, point, scheme, mode)
	player.immediate_jump = point.immediate_jump


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/JumpEdgeProbePlayer.gd",
			"res://tools/authoring/audit_jump_edge.gd"
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var result: Dictionary = await super._trial(point, scheme, mode)
	result["immediate_jump"] = point.immediate_jump
	if point.immediate_jump:
		result.input_kind = "diagnostic_immediate_jump_not_native_edge_or_human"
	return result
