extends RefCounted

const HIT_MULTIPLIERS := {
	"head": 4.0,
	"chest": 1.0,
	"stomach": 1.25,
	"arms": 1.0,
	"legs": 0.75,
}

static func resolve_hit_group(local_hit: Vector3) -> String:
	if local_hit.y >= 0.52:
		return "head"
	if local_hit.y <= -0.34:
		return "legs"
	if absf(local_hit.x) >= 0.32:
		return "arms"
	if local_hit.y <= -0.06:
		return "stomach"
	return "chest"

static func resolve_damage(
	base_damage: int,
	hit_group: String,
	armor: int,
	has_helmet: bool,
	armor_penetration: float
) -> Dictionary:
	var multiplier := float(HIT_MULTIPLIERS.get(hit_group, 1.0))
	var scaled_damage := maxi(1, int(round(float(base_damage) * multiplier)))
	var armored := armor > 0 and (
		hit_group in ["chest", "stomach", "arms"]
		or (hit_group == "head" and has_helmet)
	)
	var health_damage := scaled_damage
	var armor_damage := 0
	if armored:
		health_damage = maxi(1, int(round(float(scaled_damage) * clampf(armor_penetration, 0.0, 1.0))))
		armor_damage = mini(armor, maxi(1, int(round(float(scaled_damage - health_damage) * 0.5))))
	return {
		"hit_group": hit_group,
		"headshot": hit_group == "head",
		"armored": armored,
		"damage": health_damage,
		"armor_damage": armor_damage,
	}
