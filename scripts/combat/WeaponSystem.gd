extends Node

const HitResolver = preload("res://scripts/combat/HitResolver.gd")
const WeaponProfileScript = preload("res://scripts/combat/WeaponProfile.gd")

signal shot_resolved(result: Dictionary)
signal reload_started
signal reload_finished
signal weapon_switched(weapon_name: String, slot_index: int)

@export var weapon_profiles: Array[Resource] = []
@export var starting_weapon_index: int = 0

var _weapon_states: Array[Dictionary] = []
var _runtime_profiles: Array[Resource] = []
var _current_weapon_index: int = 0

func configure_default_loadout(emit_warnings: bool = true) -> void:
	_weapon_states.clear()
	_runtime_profiles.clear()
	for profile_variant in weapon_profiles:
		if not _is_weapon_profile(profile_variant):
			if emit_warnings:
				push_warning("WeaponSystem ignored a resource that is not a WeaponProfile.")
			continue
		var profile = profile_variant
		var configuration_errors: PackedStringArray = profile.get_configuration_errors()
		if not configuration_errors.is_empty():
			if emit_warnings:
				push_warning("WeaponSystem ignored invalid profile '%s': %s" % [profile.resource_path, "; ".join(configuration_errors)])
			continue
		_runtime_profiles.append(profile)
		_weapon_states.append({
			"ammo_in_mag": profile.magazine_size,
			"ammo_reserve": profile.reserve_ammo_on_spawn,
			"fire_cooldown": 0.0,
			"reload_timer": 0.0,
			"equip_timer": 0.0,
			"is_reloading": false,
			"is_equipping": false,
			"current_spread_degrees": profile.spread_min_degrees,
			"last_recoil_value": 0.0,
			"pattern_index": 0,
			"time_since_last_shot": profile.pattern_reset_delay
		})

	if _weapon_states.is_empty():
		GameState.sync_weapon_state("\u672a\u914d\u7f6e\u6b66\u5668", 0, 0, "", 0.0, 0.0, -1)
		return

	_current_weapon_index = clampi(starting_weapon_index, 0, _weapon_states.size() - 1)
	_sync_game_state("")

func tick(delta: float, fire_pressed: bool, fire_held: bool, player: CharacterBody3D) -> void:
	if _weapon_states.is_empty():
		return

	_tick_weapon_states(delta, player)

	var current_profile = _current_profile()
	if current_profile == null:
		return

	var should_fire: bool = fire_held if current_profile.auto_fire else fire_pressed
	if should_fire:
		try_fire(player)
	else:
		_sync_game_state("")

func request_reload() -> void:
	var current_profile = _current_profile()
	if current_profile == null:
		return

	var current_state: Dictionary = _current_state()
	if bool(current_state.get("is_reloading", false)):
		return
	if bool(current_state.get("is_equipping", false)):
		return
	if int(current_state.get("ammo_in_mag", 0)) >= current_profile.magazine_size:
		return
	if int(current_state.get("ammo_reserve", 0)) <= 0:
		return

	current_state["is_reloading"] = true
	current_state["reload_timer"] = current_profile.reload_duration
	_store_current_state(current_state)
	_sync_game_state("\u6362\u5f39\u4e2d")
	reload_started.emit()

func try_fire(player: CharacterBody3D) -> void:
	var current_profile = _current_profile()
	if current_profile == null:
		return

	var current_state: Dictionary = _current_state()
	if bool(current_state.get("is_reloading", false)):
		return
	if bool(current_state.get("is_equipping", false)):
		return
	if float(current_state.get("fire_cooldown", 0.0)) > 0.0:
		return
	if int(current_state.get("ammo_in_mag", 0)) <= 0:
		request_reload()
		return
	if not player.has_method("get_camera_node"):
		return

	var camera_variant: Variant = player.call("get_camera_node")
	if not (camera_variant is Camera3D):
		return

	var camera: Camera3D = camera_variant as Camera3D
	current_state["time_since_last_shot"] = 0.0
	current_state["ammo_in_mag"] = int(current_state.get("ammo_in_mag", 0)) - 1
	current_state["fire_cooldown"] = current_profile.fire_interval
	current_state = _apply_shot_spread_growth(player, current_profile, current_state)

	var shot_index: int = int(current_state.get("pattern_index", 0))
	var exclude: Array = [player.get_rid()]
	var shot_direction: Vector3 = _build_shot_direction(camera, player, current_profile, current_state, shot_index)
	var hit_result: Dictionary = HitResolver.resolve_direction(
		camera.global_transform.origin,
		shot_direction,
		current_profile.max_range,
		current_profile.hit_collision_mask,
		exclude,
		camera.get_world_3d().direct_space_state
	)
	current_state = _apply_recoil(player, current_profile, current_state, shot_index)
	current_state["pattern_index"] = shot_index + 1

	if bool(hit_result.get("hit", false)):
		var collider: Variant = hit_result.get("collider", null)
		if collider != null and collider.has_method("apply_hitscan_damage"):
			var damage_result: Variant = collider.call(
				"apply_hitscan_damage",
				current_profile.damage,
				hit_result.get("position", Vector3.ZERO)
			)
			if typeof(damage_result) == TYPE_DICTIONARY:
				var damage_dict: Dictionary = damage_result as Dictionary
				if bool(damage_dict.get("hit", false)):
					GameState.register_hit(bool(damage_dict.get("killed", false)))
					hit_result["damage_result"] = damage_dict
		else:
			hit_result["damage_result"] = {}

	hit_result["weapon_name"] = current_profile.display_name
	hit_result["weapon_slot"] = _current_weapon_index
	_store_current_state(current_state)
	shot_resolved.emit(hit_result)

	if int(current_state.get("ammo_in_mag", 0)) == 0 and int(current_state.get("ammo_reserve", 0)) > 0:
		request_reload()
	else:
		_sync_game_state("")

func switch_to_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _weapon_states.size():
		return
	if slot_index == _current_weapon_index:
		return

	var previous_state: Dictionary = _current_state()
	if bool(previous_state.get("is_reloading", false)):
		previous_state["is_reloading"] = false
		previous_state["reload_timer"] = 0.0
		_store_current_state(previous_state)

	_current_weapon_index = slot_index
	var current_profile = _current_profile()
	var current_state: Dictionary = _current_state()
	if current_profile != null:
		current_state = _begin_equip_state(current_profile, current_state)
		_store_current_state(current_state)
	_sync_game_state("")
	if current_profile != null:
		weapon_switched.emit(current_profile.display_name, slot_index)

func get_runtime_snapshot() -> Dictionary:
	var current_profile = _current_profile()
	var current_state: Dictionary = _current_state()
	if current_profile == null:
		return {}

	return {
		"weapon_name": current_profile.display_name,
		"ammo_in_mag": int(current_state.get("ammo_in_mag", 0)),
		"ammo_reserve": int(current_state.get("ammo_reserve", 0)),
		"is_reloading": bool(current_state.get("is_reloading", false)),
		"is_equipping": bool(current_state.get("is_equipping", false)),
		"spread_degrees": float(current_state.get("current_spread_degrees", current_profile.spread_min_degrees)),
		"recoil_value": float(current_state.get("last_recoil_value", 0.0)),
		"weapon_slot": _current_weapon_index
	}

func _tick_weapon_states(delta: float, player: CharacterBody3D) -> void:
	for index in range(_weapon_states.size()):
		var profile_variant: Variant = _runtime_profiles[index]
		if not _is_weapon_profile(profile_variant):
			continue
		var profile = profile_variant
		var state: Dictionary = _weapon_states[index]
		state["fire_cooldown"] = maxf(0.0, float(state.get("fire_cooldown", 0.0)) - delta)
		state["time_since_last_shot"] = float(state.get("time_since_last_shot", profile.pattern_reset_delay)) + delta

		if bool(state.get("is_equipping", false)):
			state["equip_timer"] = maxf(0.0, float(state.get("equip_timer", 0.0)) - delta)
			if float(state.get("equip_timer", 0.0)) == 0.0:
				state["is_equipping"] = false

		if bool(state.get("is_reloading", false)):
			state["reload_timer"] = maxf(0.0, float(state.get("reload_timer", 0.0)) - delta)
			if float(state.get("reload_timer", 0.0)) == 0.0:
				state = _finish_reload_state(profile, state)
				if index == _current_weapon_index:
					reload_finished.emit()

		if index == _current_weapon_index:
			state = _recover_spread(delta, player, profile, state)
		else:
			state["current_spread_degrees"] = maxf(
				profile.spread_min_degrees,
				float(state.get("current_spread_degrees", profile.spread_min_degrees)) - profile.spread_recover_per_second * delta
			)
			state["last_recoil_value"] = maxf(0.0, float(state.get("last_recoil_value", 0.0)) - delta * 6.0)
			if (
				float(state.get("time_since_last_shot", profile.pattern_reset_delay)) >= profile.pattern_reset_delay
				and float(state.get("current_spread_degrees", profile.spread_min_degrees)) <= profile.spread_min_degrees + 0.01
			):
				state["pattern_index"] = 0

		_weapon_states[index] = state

func _finish_reload_state(profile, state: Dictionary) -> Dictionary:
	var needed: int = profile.magazine_size - int(state.get("ammo_in_mag", 0))
	var reserve: int = int(state.get("ammo_reserve", 0))
	var loaded: int = mini(needed, reserve)
	state["ammo_in_mag"] = int(state.get("ammo_in_mag", 0)) + loaded
	state["ammo_reserve"] = reserve - loaded
	state["is_reloading"] = false
	state["reload_timer"] = 0.0
	return state

func _recover_spread(delta: float, player: CharacterBody3D, profile, state: Dictionary) -> Dictionary:
	var target_spread: float = _movement_spread_floor(player, profile)
	state["current_spread_degrees"] = maxf(
		target_spread,
		float(state.get("current_spread_degrees", profile.spread_min_degrees)) - profile.spread_recover_per_second * delta
	)
	state["last_recoil_value"] = maxf(0.0, float(state.get("last_recoil_value", 0.0)) - delta * 6.0)
	if (
		float(state.get("time_since_last_shot", profile.pattern_reset_delay)) >= profile.pattern_reset_delay
		and float(state.get("current_spread_degrees", profile.spread_min_degrees)) <= target_spread + 0.02
	):
		state["pattern_index"] = 0
	return state

func _movement_spread_floor(player: CharacterBody3D, profile) -> float:
	var spread_floor: float = profile.spread_min_degrees
	var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if horizontal_speed > 0.18:
		spread_floor += profile.spread_move_penalty_degrees
	if not player.is_on_floor():
		spread_floor += profile.spread_air_penalty_degrees
	return spread_floor

func _apply_shot_spread_growth(player: CharacterBody3D, profile, state: Dictionary) -> Dictionary:
	var movement_floor: float = _movement_spread_floor(player, profile)
	var next_spread: float = maxf(
		movement_floor,
		float(state.get("current_spread_degrees", profile.spread_min_degrees)) + profile.spread_shot_increment_degrees
	)
	state["current_spread_degrees"] = minf(profile.spread_max_degrees, next_spread)
	return state

func _build_shot_direction(camera: Camera3D, player: CharacterBody3D, profile, state: Dictionary, shot_index: int) -> Vector3:
	var basis: Basis = camera.global_transform.basis
	var direction: Vector3 = -basis.z
	var shot_pattern: Vector2 = profile.get_shot_pattern_for_shot(shot_index)
	var inaccuracy_offset: Vector2 = _build_inaccuracy_offset(player, profile, state, shot_index)
	var yaw_offset_deg: float = shot_pattern.x + inaccuracy_offset.x
	var pitch_offset_deg: float = shot_pattern.y + inaccuracy_offset.y
	direction = direction.rotated(basis.y.normalized(), deg_to_rad(yaw_offset_deg))
	direction = direction.rotated(basis.x.normalized(), deg_to_rad(pitch_offset_deg))
	return direction.normalized()

func _build_inaccuracy_offset(player: CharacterBody3D, profile, state: Dictionary, shot_index: int) -> Vector2:
	var current_spread: float = float(state.get("current_spread_degrees", profile.spread_min_degrees))
	var extra_spread: float = maxf(0.0, current_spread - profile.spread_min_degrees)
	if extra_spread <= 0.001:
		return Vector2.ZERO
	if player != null and not player.is_on_floor():
		extra_spread = maxf(extra_spread, profile.spread_air_penalty_degrees)
	var spread_direction: Vector2 = profile.get_spread_direction_for_shot(shot_index)
	return spread_direction * extra_spread

func _apply_recoil(player: CharacterBody3D, profile, state: Dictionary, shot_index: int) -> Dictionary:
	var recoil_pattern: Vector2 = profile.get_recoil_pattern_for_shot(shot_index)
	var pitch_kick: float = deg_to_rad(abs(recoil_pattern.y) * profile.camera_pitch_multiplier)
	var yaw_kick: float = deg_to_rad(recoil_pattern.x * profile.camera_yaw_multiplier)
	state["last_recoil_value"] = pitch_kick
	if player.has_method("apply_recoil_kick"):
		player.call("apply_recoil_kick", pitch_kick, yaw_kick)
	return state

func _begin_equip_state(profile, state: Dictionary) -> Dictionary:
	state["is_equipping"] = profile.equip_duration > 0.0
	state["equip_timer"] = maxf(0.0, profile.equip_duration)
	return state

func _sync_game_state(status_text: String) -> void:
	var current_profile = _current_profile()
	var current_state: Dictionary = _current_state()
	if current_profile == null:
		return

	var resolved_status: String = status_text
	if resolved_status.is_empty():
		if bool(current_state.get("is_reloading", false)):
			resolved_status = "\u6362\u5f39\u4e2d"
		elif bool(current_state.get("is_equipping", false)):
			resolved_status = "\u5207\u67aa\u4e2d"

	GameState.sync_weapon_state(
		current_profile.display_name,
		int(current_state.get("ammo_in_mag", 0)),
		int(current_state.get("ammo_reserve", 0)),
		resolved_status,
		float(current_state.get("current_spread_degrees", current_profile.spread_min_degrees)),
		float(current_state.get("last_recoil_value", 0.0)),
		_current_weapon_index
	)

func _current_profile():
	if _current_weapon_index < 0 or _current_weapon_index >= _runtime_profiles.size():
		return null
	var profile_variant: Variant = _runtime_profiles[_current_weapon_index]
	if _is_weapon_profile(profile_variant):
		return profile_variant
	return null

func _is_weapon_profile(profile_variant: Variant) -> bool:
	if not (profile_variant is Resource):
		return false
	return (profile_variant as Resource).get_script() == WeaponProfileScript

func _current_state() -> Dictionary:
	if _current_weapon_index < 0 or _current_weapon_index >= _weapon_states.size():
		return {}
	return _weapon_states[_current_weapon_index]

func _store_current_state(state: Dictionary) -> void:
	if _current_weapon_index < 0 or _current_weapon_index >= _weapon_states.size():
		return
	_weapon_states[_current_weapon_index] = state
