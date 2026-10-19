extends RefCounted

const PRIMARY := ["rifle", "sniper", "smg", "shotgun"]
const KILL_REWARDS := {"knife": 1500, "smg": 600, "shotgun": 900, "sniper": 100}
const PRICES := {
	"rifle": 2700,
	"pistol": 500,
	"sniper": 4750,
	"smg": 1500,
	"shotgun": 1850,
	"armor": 650,
	"helmet": 350,
	"armor_helmet": 1000,
	"defuse_kit": 400,
	"he_grenade": 300,
	"flash_grenade": 200,
	"smoke_grenade": 300,
	"fire_grenade": 500,
}
const NAMES := {
	"rifle": "步枪", "pistol": "手枪", "sniper": "狙击枪", "smg": "冲锋枪", "shotgun": "霰弹枪", "knife": "战术刀"
}


static func profile(weapon_id: String) -> Resource:
	if weapon_id == "pistol":
		return preload("res://data/weapons/pistol.tres")
	if weapon_id not in PRIMARY:
		return null
	var result = preload("res://data/weapons/rifle.tres").duplicate()
	result.weapon_id = weapon_id
	result.display_name = NAMES[weapon_id]
	match weapon_id:
		"sniper":
			result.damage = 110
			result.magazine_size = 5
			result.reserve_ammo_on_spawn = 20
			result.auto_fire = false
			result.fire_interval = 1.3
			result.reload_duration = 3.4
			result.max_range = 250.0
			result.spread_min_degrees = 0.08
			result.spread_max_degrees = 6.5
			result.spread_move_penalty_degrees = 3.5
			result.spread_shot_increment_degrees = 3.0
			result.armor_penetration = 0.85
			result.max_penetrations = 2
		"smg":
			result.damage = 24
			result.reserve_ammo_on_spawn = 120
			result.fire_interval = 0.075
			result.reload_duration = 2.0
			result.max_range = 90.0
			result.range_modifier = 0.90
			result.armor_penetration = 0.55
			result.spread_move_penalty_degrees = 0.7
			result.spread_shot_increment_degrees = 0.24
		"shotgun":
			result.damage = 9
			result.magazine_size = 8
			result.reserve_ammo_on_spawn = 32
			result.auto_fire = false
			result.fire_interval = 0.85
			result.reload_duration = 3.0
			result.max_range = 35.0
			result.range_modifier = 0.75
			result.armor_penetration = 0.55
			result.max_penetrations = 0
			result.pellets = 7
			result.pellet_spread_degrees = 3.0
	return result


static func pellet_direction(direction: Vector3, pellet: int, count: int, spread: float) -> Vector3:
	if pellet == 0 or count <= 1:
		return direction
	var right := direction.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	var up := right.cross(direction).normalized()
	var angle := TAU * float(pellet - 1) / float(count - 1)
	return (
		(direction + (right * cos(angle) + up * sin(angle)) * tan(deg_to_rad(spread))).normalized()
	)
