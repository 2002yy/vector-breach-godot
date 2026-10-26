extends "res://tools/authoring/audit_surface_ingress.gd"
## Read-only approach envelope; the same actor continues through ingress.

var approach_cache := {}


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		var path := "res://tools/authoring/audit_navigation_ingress.gd"
		samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var key := JSON.stringify([point.start, point.approach_feet])
	if not approach_cache.has(key):
		approach_cache[key] = Survey.body_corridor(
			space,
			Survey.vector(point.start) - Vector3.UP * 0.9,
			Survey.vector(point.approach_feet),
			false
		)
	var result: Dictionary = await super._trial(point, scheme, mode)
	result["approach_corridor"] = approach_cache[key].duplicate(true)
	return result
