extends "res://tools/authoring/audit_landing_stages.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/QueuedKeyProbePlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, scheme: String, mode: String
) -> void:
	super._configure_trial_player(player, point, scheme, mode)
	player.queued_input = point.queued_input


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/QueuedKeyProbePlayer.gd",
			"res://tools/authoring/audit_queued_key.gd"
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var result: Dictionary = await super._trial(point, scheme, mode)
	result["queued_input"] = point.queued_input
	if point.queued_input:
		result.input_kind = "diagnostic_native_keys_queued_before_physics_not_OS"
	return result
