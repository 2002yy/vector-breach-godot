extends "res://tools/authoring/audit_queue_cadence.gd"
## Read-only standing-body envelope, paired with actual native ingress traces.

var corridor_cache := {}


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		var path := "res://tools/authoring/audit_surface_ingress.gd"
		samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var key := JSON.stringify([point.start, point.target_feet])
	if not corridor_cache.has(key):
		corridor_cache[key] = Survey.body_corridor(
			space,
			Survey.vector(point.start) - Vector3.UP * 0.9,
			Survey.vector(point.target_feet),
			false
		)
	var result: Dictionary = await super._trial(point, scheme, mode)
	result["ingress_corridor"] = corridor_cache[key].duplicate(true)
	return result
