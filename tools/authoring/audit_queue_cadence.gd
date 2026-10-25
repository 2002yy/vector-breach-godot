extends "res://tools/authoring/audit_queued_key.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/QueueCadenceProbePlayer.gd")


func _configure_trial_player(
	player: CharacterBody3D, point: Dictionary, scheme: String, mode: String
) -> void:
	super._configure_trial_player(player, point, scheme, mode)
	player.enforce_cadence = point.enforce_cadence
	player.rejection_path = point.rejection_path
	assert(not point.enforce_cadence or not FileAccess.file_exists(point.rejection_path))


func _record(sample: Dictionary) -> void:
	super._record(sample)
	samples[-1]["cadence"] = trial_player.last_cadence.duplicate(true)
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/QueueCadenceProbePlayer.gd",
			"res://tools/authoring/audit_queue_cadence.gd"
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)
	if trial_player.enforce_cadence and trial_player.last_cadence.violation:
		var file := FileAccess.open(trial_player.rejection_path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(
			JSON.stringify(
				{
					"accepted": false,
					"reason": "process_physics_cadence_mismatch",
					"observed": trial_player.last_cadence,
					"probe_sha256": samples[0].probe_sha256
				},
				"\t"
			)
		)
		file.close()
		printerr("QUEUED_CADENCE_REJECTED observed=", trial_player.last_cadence)
		quit(2)
