extends "res://tools/authoring/audit_runup_routes.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/SlidePathProbePlayer.gd")


func _record(sample: Dictionary) -> void:
	super._record(sample)
	samples[-1]["slide_path"] = trial_player.slide_path.duplicate(true)
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/SlidePathReceipt.gd",
			"res://tools/authoring/SlidePathProbePlayer.gd",
			"res://tools/authoring/audit_inferno_slide_path.gd",
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)
