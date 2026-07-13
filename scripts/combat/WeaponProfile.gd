extends Resource
class_name WeaponProfile

@export var weapon_id: String = "rifle"
@export var display_name: String = "\u6b65\u67aa"
@export var slot_index: int = 0
@export var damage: int = 34
@export var magazine_size: int = 30
@export var reserve_ammo_on_spawn: int = 90
@export var fire_interval: float = 0.11
@export var reload_duration: float = 2.2
@export var max_range: float = 180.0
@export var hit_collision_mask: int = 1
@export var auto_fire: bool = true
@export var spread_min_degrees: float = 0.35
@export var spread_max_degrees: float = 3.2
@export var spread_move_penalty_degrees: float = 1.2
@export var spread_air_penalty_degrees: float = 2.2
@export var spread_shot_increment_degrees: float = 0.45
@export var spread_recover_per_second: float = 3.6
@export var pattern_reset_delay: float = 0.35
@export var equip_duration: float = 0.32
@export var camera_pitch_multiplier: float = 0.32
@export var camera_yaw_multiplier: float = 0.4
@export var recoil_pattern_degrees: Array = []
@export var shot_pattern_degrees: Array = []
@export var spread_pattern_directions: Array = []

func get_recoil_pattern_for_shot(shot_index: int) -> Vector2:
	if recoil_pattern_degrees.is_empty():
		return Vector2.ZERO
	var clamped_index: int = mini(shot_index, recoil_pattern_degrees.size() - 1)
	var value: Variant = recoil_pattern_degrees[clamped_index]
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO

func get_shot_pattern_for_shot(shot_index: int) -> Vector2:
	if shot_pattern_degrees.is_empty():
		return get_recoil_pattern_for_shot(shot_index)
	var clamped_index: int = mini(shot_index, shot_pattern_degrees.size() - 1)
	var value: Variant = shot_pattern_degrees[clamped_index]
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO

func get_spread_direction_for_shot(shot_index: int) -> Vector2:
	if spread_pattern_directions.is_empty():
		return Vector2.ZERO
	var cycle_index: int = posmod(shot_index, spread_pattern_directions.size())
	var value: Variant = spread_pattern_directions[cycle_index]
	if value is Vector2:
		return value as Vector2
	return Vector2.ZERO

func get_configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if weapon_id.strip_edges().is_empty():
		errors.append("weapon_id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if magazine_size <= 0:
		errors.append("magazine_size must be greater than zero")
	if reserve_ammo_on_spawn < 0:
		errors.append("reserve_ammo_on_spawn must not be negative")
	if fire_interval <= 0.0:
		errors.append("fire_interval must be greater than zero")
	if reload_duration < 0.0:
		errors.append("reload_duration must not be negative")
	if max_range <= 0.0:
		errors.append("max_range must be greater than zero")
	if spread_min_degrees < 0.0 or spread_max_degrees < spread_min_degrees:
		errors.append("spread range is invalid")
	return errors
