extends "res://tools/authoring/audit_native_route_keyboard.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/LandingStageProbePlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, scheme: String, mode: String
) -> void:
	super._configure_trial_player(player, point, scheme, mode)
	assert(point.ablation in ["baseline", "no_pre", "no_try", "no_snap"])
	for path in point.probe_sha256:
		assert(FileAccess.get_sha256(path) == point.probe_sha256[path])
	player.ablation = point.ablation


func _record(sample: Dictionary) -> void:
	super._record(sample)
	samples[-1]["stages"] = trial_player.stages.duplicate(true)
	if samples.size() == 1:
		var hashes := {}
		for path in [
			"res://tools/authoring/LandingStageProbePlayer.gd",
			"res://tools/authoring/audit_landing_stages.gd"
		]:
			hashes[path] = FileAccess.get_sha256(path)
		samples[-1]["probe_sha256"] = hashes
