extends "res://tools/authoring/audit_modern_vertical_quadrature.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/ModernSnapSupportPlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, scheme: String, mode: String
) -> void:
	super._configure_trial_player(player, point, scheme, mode)
	player.support_enabled = point.support_enabled


func _record(sample: Dictionary) -> void:
	super._record(sample)
	samples[-1]["support"] = trial_player.support_sample.duplicate(true)
	samples[-1]["landing_events"] = trial_player.landing_events
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/ModernSnapSupportPlayer.gd",
			"res://tools/authoring/audit_modern_snap_support.gd"
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)
