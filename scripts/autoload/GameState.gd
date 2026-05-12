extends Node

var current_level_id: String = "test-collision-room"
var current_level_name: String = "\u6d4b\u8bd5\u78b0\u649e\u623f"
var player_spawn: Vector3 = Vector3.ZERO

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
	current_level_id = level_id
	if not level_name.is_empty():
		current_level_name = level_name

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

func set_graphics_preset(preset: String) -> void:
	graphics_preset = preset.to_lower()

func set_menu_state(opened: bool) -> void:
	menu_open = opened

func set_game_started(started: bool) -> void:
	game_started = started

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
		"round_label": RoundManager.get_state_label()
	}

func sync_weapon_state(weapon_name: String, next_ammo_in_mag: int, next_ammo_reserve: int, status_text: String = "", spread_degrees: float = 0.0, recoil_value: float = 0.0, slot_index: int = 0) -> void:
	current_weapon_name = weapon_name
	current_weapon_slot = slot_index
	ammo_in_mag = next_ammo_in_mag
	ammo_reserve = next_ammo_reserve
	weapon_status_text = status_text
	current_spread_degrees = spread_degrees
	recoil_display_value = recoil_value

func register_hit(killed: bool) -> void:
	hit_count += 1
	if killed:
		kill_count += 1
