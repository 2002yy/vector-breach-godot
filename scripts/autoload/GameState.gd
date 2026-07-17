extends Node

signal hud_state_changed(snapshot: Dictionary)

var current_level_id: String = "depot"
var current_level_name: String = "\u4ed3\u5e93\u7ad9"
var player_spawn: Vector3 = Vector3.ZERO
var player_spawn_yaw_radians: float = 0.0

var player_health: int = 100
var current_weapon_name: String = "\u6b65\u67aa"
var current_weapon_slot: int = 0
var ammo_in_mag: int = 30
var ammo_reserve: int = 90
var weapon_status_text: String = ""
var hit_count: int = 0
var kill_count: int = 0
var current_spread_degrees: float = 0.0
var recoil_display_value: float = 0.0
var graphics_preset: String = "prototype"
var menu_open: bool = true
var game_started: bool = false

func set_level(level_id: String, level_name: String = "") -> void:
	var changed := current_level_id != level_id
	current_level_id = level_id
	if not level_name.is_empty():
		changed = changed or current_level_name != level_name
		current_level_name = level_name
	if changed:
		_emit_hud_state_changed()

func reset_runtime_state() -> void:
	player_health = 100
	current_weapon_name = "\u6b65\u67aa"
	current_weapon_slot = 0
	ammo_in_mag = 30
	ammo_reserve = 90
	weapon_status_text = ""
	hit_count = 0
	kill_count = 0
	current_spread_degrees = 0.0
	recoil_display_value = 0.0
	_emit_hud_state_changed()

func set_graphics_preset(preset: String) -> void:
	graphics_preset = preset.to_lower()

func set_menu_state(opened: bool) -> void:
	if menu_open == opened:
		return
	menu_open = opened
	_emit_hud_state_changed()

func set_game_started(started: bool) -> void:
	if game_started == started:
		return
	game_started = started
	_emit_hud_state_changed()

func get_shape_build_options() -> Dictionary:
	match graphics_preset:
		"low":
			return {
				"graphics_preset": "low",
				"arena_bounds_enabled": true,
				"arena_floor_enabled": true,
				"ramp_segments": 3,
				"catwalk_support_visuals": false
			}
		"medium":
			return {
				"graphics_preset": "medium",
				"arena_bounds_enabled": true,
				"arena_floor_enabled": true,
				"ramp_segments": 4,
				"catwalk_support_visuals": true
			}
		_:
			return {
				"graphics_preset": "prototype",
				"arena_bounds_enabled": true,
				"arena_floor_enabled": true,
				"ramp_segments": 6,
				"catwalk_support_visuals": true
			}

func get_graphics_preset_label() -> String:
	match graphics_preset:
		"low":
			return "\u4f4e"
		"medium":
			return "\u4e2d"
		_:
			return "\u539f\u578b"

func get_hud_snapshot() -> Dictionary:
	return {
		"health": player_health,
		"weapon_name": current_weapon_name,
		"weapon_slot": current_weapon_slot,
		"ammo_in_mag": ammo_in_mag,
		"ammo_reserve": ammo_reserve,
		"weapon_status_text": weapon_status_text,
		"hit_count": hit_count,
		"kill_count": kill_count,
		"spread_degrees": current_spread_degrees,
		"recoil_display_value": recoil_display_value,
		"level_name": current_level_name,
		"game_started": game_started,
		"menu_open": menu_open,
		"round_state": RoundManager.get_state_name(),
		"round_label": RoundManager.get_state_label()
	}

func sync_weapon_state(weapon_name: String, next_ammo_in_mag: int, next_ammo_reserve: int, status_text: String = "", spread_degrees: float = 0.0, recoil_value: float = 0.0, slot_index: int = 0) -> void:
	var changed := (
		current_weapon_name != weapon_name
		or current_weapon_slot != slot_index
		or ammo_in_mag != next_ammo_in_mag
		or ammo_reserve != next_ammo_reserve
		or weapon_status_text != status_text
		or not is_equal_approx(current_spread_degrees, spread_degrees)
		or not is_equal_approx(recoil_display_value, recoil_value)
	)
	current_weapon_name = weapon_name
	current_weapon_slot = slot_index
	ammo_in_mag = next_ammo_in_mag
	ammo_reserve = next_ammo_reserve
	weapon_status_text = status_text
	current_spread_degrees = spread_degrees
	recoil_display_value = recoil_value
	if changed:
		_emit_hud_state_changed()

func register_hit(killed: bool) -> void:
	hit_count += 1
	if killed:
		kill_count += 1
	_emit_hud_state_changed()

func _emit_hud_state_changed() -> void:
	hud_state_changed.emit(get_hud_snapshot())
