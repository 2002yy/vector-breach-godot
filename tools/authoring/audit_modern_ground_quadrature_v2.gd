extends "res://tools/authoring/audit_modern_ground_quadrature.gd"


func _trial_script() -> Script:
	return load("res://tools/authoring/ModernGroundQuadratureV2Player.gd")


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		for path in [
			"res://tools/authoring/ModernGroundQuadratureV2Player.gd",
			"res://tools/authoring/audit_modern_ground_quadrature_v2.gd"
		]:
			samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)
