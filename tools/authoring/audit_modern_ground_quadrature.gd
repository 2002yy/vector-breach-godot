extends "res://tools/authoring/audit_queue_cadence.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/ModernGroundQuadraturePlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, scheme: String, mode: String
) -> void:
	super._configure_trial_player(player, point, scheme, mode)
	player.quadrature_enabled = point.quadrature_enabled


func _record(sample: Dictionary) -> void:
	super._record(sample)
	samples[-1]["quadrature"] = trial_player.quadrature_sample.duplicate(true)
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/ModernGroundQuadraturePlayer.gd",
			"res://tools/authoring/audit_modern_ground_quadrature.gd"
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)
