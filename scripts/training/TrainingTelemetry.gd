extends Node

## Session-only practice telemetry. It is intentionally observational: weapon,
## projectile and AI simulation continue to own their respective game rules.

var shots_fired := 0
var shots_hit := 0
var headshots := 0
var last_impact := Vector3.ZERO
var last_spray_index := -1
var grenades: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("training_telemetry")

func reset() -> void:
	shots_fired = 0
	shots_hit = 0
	headshots = 0
	last_impact = Vector3.ZERO
	last_spray_index = -1
	grenades.clear()

func record_shot(result: Dictionary) -> void:
	shots_fired += 1
	last_spray_index = int(result.get("spray_index", -1))
	if bool(result.get("hit", false)):
		last_impact = result.get("position", Vector3.ZERO) as Vector3
	var damage: Dictionary = result.get("damage_result", {}) as Dictionary
	if bool(damage.get("hit", false)):
		shots_hit += 1
		if bool(damage.get("headshot", false)):
			headshots += 1

func record_grenade(summary: Dictionary) -> void:
	grenades.append(summary.duplicate(true))
	if grenades.size() > 12:
		grenades.pop_front()

func get_snapshot() -> Dictionary:
	var accuracy := 0.0 if shots_fired == 0 else float(shots_hit) * 100.0 / float(shots_fired)
	var grenade_text := "暂无投掷记录"
	if not grenades.is_empty():
		var last: Dictionary = grenades.back() as Dictionary
		grenade_text = "%s  %.1fm / %.2fs" % [
			String(last.get("type", "grenade")),
			float(last.get("distance", 0.0)),
			float(last.get("flight_time", 0.0)),
		]
	return {
		"shots": shots_fired,
		"hits": shots_hit,
		"headshots": headshots,
		"accuracy": accuracy,
		"last_impact": last_impact,
		"last_spray_index": last_spray_index,
		"impact_text": "无命中" if last_impact == Vector3.ZERO else "(%.1f, %.1f, %.1f)" % [last_impact.x, last_impact.y, last_impact.z],
		"grenade_text": grenade_text,
	}
