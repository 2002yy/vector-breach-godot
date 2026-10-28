extends RefCounted
## Share weapon/stance/tag/water limits without replacing navigation steering.

const Rules = preload("res://scripts/player/ClassicMovementRules.gd")
const PlayerDefinition = preload("res://scripts/player/PlayerController.gd")
static var _cached_defaults: Dictionary = {}


static func current_defaults() -> Dictionary:
	# The production Player.tscn currently has no overrides for these exports.
	# Read the defaults rather than maintaining a second AI movement table.
	if _cached_defaults.is_empty():
		var definition: Script = PlayerDefinition
		_cached_defaults = {
			"run": definition.get_property_default_value(&"run_speed"),
			"walk": definition.get_property_default_value(&"quiet_walk_speed"),
			"crouch": definition.get_property_default_value(&"crouch_speed"),
			"water_shallow":
			definition.get_property_default_value(&"shallow_water_speed_multiplier"),
			"water_deep": definition.get_property_default_value(&"deep_water_speed_multiplier"),
		}
	return _cached_defaults.duplicate()


static func water_multiplier(depth: float, in_water: bool) -> float:
	if not in_water:
		return 1.0
	var defaults := current_defaults()
	return float(defaults.water_deep if depth >= 1.2 else defaults.water_shallow)


static func navigation_limit(scheme: String, state: Dictionary, navigation_cap: float) -> float:
	var before_actor := state.duplicate()
	before_actor.tagging = 1.0
	before_actor.water = 1.0
	var defaults := current_defaults()
	var weapon_pose_limit: float = Rules.speed_limit(scheme, before_actor, defaults)
	if weapon_pose_limit <= 0.0:
		return 0.0
	var actor_limit: float = Rules.speed_limit(scheme, state, defaults)
	# Tag/water apply after the navigation cap too, so precise/slow routes cannot
	# bypass damage slowdown. Their factors come from the shared rules, not a copy.
	return minf(maxf(navigation_cap, 0.0), weapon_pose_limit) * actor_limit / weapon_pose_limit
