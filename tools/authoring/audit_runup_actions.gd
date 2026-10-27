extends "res://tools/authoring/audit_queue_cadence.gd"

var corridor_cache := {}


func _record(sample: Dictionary) -> void:
	super._record(sample)
	if samples.size() == 1:
		var path := "res://tools/authoring/audit_runup_actions.gd"
		samples[-1].probe_sha256[path] = FileAccess.get_sha256(path)


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var result: Dictionary = await super._trial(point, scheme, mode)
	if mode == "jump":
		var key := JSON.stringify([point.start, point.target_feet])
		if not corridor_cache.has(key):
			corridor_cache[key] = Survey.body_corridor(
				space,
				Survey.vector(point.start) - Vector3.UP * 0.9,
				Survey.vector(point.target_feet),
				false
			)
		result["ingress_corridor"] = corridor_cache[key].duplicate(true)
	return result
