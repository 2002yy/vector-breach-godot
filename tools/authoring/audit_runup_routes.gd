extends "res://tools/authoring/audit_runup_actions.gd"


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		var path := "res://tools/authoring/audit_runup_routes.gd"
		samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)
