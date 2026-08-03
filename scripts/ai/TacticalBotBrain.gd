extends Node

const GrenadeProjectile = preload("res://scripts/combat/GrenadeProjectile.gd")
const BotNavigationModel = preload("res://scripts/ai/BotNavigationModel.gd")

enum State {
	HOLD,
	PATROL,
	INVESTIGATE,
	ACQUIRE,
	ENGAGE,
	RELOAD,
	OBJECTIVE,
	HOLD_ANGLE,
	RETREAT,
}

const WEAPON_PROFILES := {
	"rifle": {
		"label": "AI步枪",
		"slot": 0,
		"damage": 18,
		"magazine": 30,
		"reserve": 90,
		"fire_interval": 0.095,
		"reload": 2.35,
		"burst": 3,
		"max_spray": 8,
		"max_range": 180.0,
		"melee_range": 0.0,
		"equip": 0.34,
	},
	"pistol": {
		"label": "AI手枪",
		"slot": 1,
		"damage": 12,
		"magazine": 12,
		"reserve": 24,
		"fire_interval": 0.18,
		"reload": 1.5,
		"burst": 1,
		"max_spray": 2,
		"max_range": 48.0,
		"melee_range": 0.0,
		"equip": 0.26,
	},
	"knife": {
		"label": "战术刀",
		"slot": 2,
		"damage": 55,
		"magazine": -1,
		"reserve": 0,
		"fire_interval": 0.42,
		"reload": 0.0,
		"burst": 1,
		"max_spray": 1,
		"max_range": 2.4,
		"melee_range": 2.4,
		"equip": 0.22,
	},
}

var actor: CharacterBody3D
var enabled: bool = false
var state: State = State.HOLD
var move_speed: float = 4.35
var view_distance: float = 34.0
var field_of_view_degrees: float = 110.0
var reaction_time: float = 0.34
var aim_acquisition_time: float = 0.30
var aim_tracking_time: float = 0.16
var hearing_memory_seconds: float = 4.0
var magazine_size: int = 30
var ammo_in_mag: int = 30
var reload_duration: float = 2.35
var rifle_damage: int = 18
var burst_size: int = 3
var shot_interval: float = 0.095
var burst_cooldown: float = 0.45
var primary_weapon_id: String = "rifle"
var secondary_weapon_id: String = "pistol"
var has_knife: bool = true
var retreat_health_ratio: float = 0.35
var hold_angle_seconds: float = 1.25
var dodge_interval: float = 0.9
var dodge_duration: float = 0.22
var crouch_during_combat_chance: float = 0.34
var tap_range_meters: float = 22.0
var spray_range_meters: float = 8.0
var melee_switch_range_meters: float = 2.4
var melee_commit_range_meters: float = 3.4
var dodge_min_range_meters: float = 3.5
var dodge_max_range_meters: float = 18.0
var damage_memory_seconds: float = 3.2
var danger_memory_seconds: float = 5.0
var ai_money: int = 800
var recoil_compensation: float = 0.006
var grenade_counts: Dictionary = {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0}
var economy_mode: String = "force"
var save_gun_enabled: bool = true
var team_money: int = -1
var team_loss_streak: int = 0

var _route_points: Array[Vector3] = []
var _route_index: int = 0
var _route_direction: int = 1
var _navigation: BotNavigationModel = BotNavigationModel.new()
var _navigation_path: Array[int] = []
var _navigation_path_index: int = 0
var _navigation_destination: Vector3 = Vector3.INF
var _repath_seconds: float = 0.0
var _active_navigation_link: Dictionary = {}
var _last_progress_position: Vector3 = Vector3.ZERO
var _no_progress_seconds: float = 0.0
var _recovery_seconds: float = 0.0
var _recovery_direction: Vector3 = Vector3.ZERO
var _recovery_flip: bool = false
var _stuck_recoveries: int = 0
var _target: CharacterBody3D
var _last_known_position: Vector3 = Vector3.ZERO
var _heard_seconds: float = 999.0
var _visible_seconds: float = 0.0
var _shot_cooldown: float = 0.0
var _burst_pause: float = 0.0
var _shots_in_burst: int = 0
var _reload_seconds: float = 0.0
var _shot_count: int = 0
var _rng := RandomNumberGenerator.new()
var _weapon_ammo: Dictionary = {}
var _weapon_reserve: Dictionary = {}
var _weapon_owned: Dictionary = {}
var _current_weapon_id: String = "rifle"
var _equip_seconds: float = 0.0
var _burst_size: int = 3
var _next_burst_pause: float = 0.45
var _spray_decision: String = "burst"
var _dodge_timer: float = 0.0
var _dodge_active: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _dodge_count: int = 0
var _dodge_flip: bool = false
var _crouch_timer: float = 0.0
var _crouch_active: float = 0.0
var _crouch_count: int = 0
var _hold_angle_timer: float = 0.0
var _retreat_seconds: float = 0.0
var _retreat_target: Vector3 = Vector3.ZERO
var _lost_sight_seconds: float = 999.0
var _damage_seconds: float = 999.0
var _damage_count: int = 0
var _damage_position: Vector3 = Vector3.ZERO
var _danger_events: Array[Dictionary] = []
var objective_role: String = ""
var objective_target: Vector3 = Vector3.INF
var plant_site_label: String = ""
var bomb_carrier: bool = false
var has_defuse_kit: bool = false
var combat_enabled: bool = true
var plant_radius_meters: float = 3.0
var defuse_radius_meters: float = 2.0
var _c4_device: Node3D
var _c4_known_position: Vector3 = Vector3.INF
var _c4_known_state: String = ""
var _bomb_interacting: bool = false
var _bomb_interaction_type: String = ""
var _teammate_reports: Array[Dictionary] = []
var _spot_emitted_target: int = 0
var _grenade_cooldown: float = 0.0
var _purchased_this_round: bool = false
var _smoke_thrown_for_objective: bool = false
var _flash_thrown_for_target: int = 0
var _he_thrown_for_target: int = 0
var _recoil_compensated_shots: int = 0
var save_gun_active: bool = false

const RECOIL_COMPENSATION_PATTERN := [
	0.0, 0.004, 0.009, 0.015, 0.022, 0.03, 0.038, 0.046, 0.052, 0.056,
	0.058, 0.058, 0.057, 0.055, 0.052, 0.049, 0.046, 0.043, 0.041, 0.04,
]

func setup(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor
	_rng.seed = owner_actor.get_instance_id()

func configure(record: Dictionary) -> void:
	enabled = bool(record.get("aiEnabled", false))
	move_speed = clampf(float(record.get("aiMoveSpeed", move_speed)), 1.5, 6.2)
	view_distance = clampf(float(record.get("aiViewDistance", view_distance)), 8.0, 60.0)
	field_of_view_degrees = clampf(float(record.get("aiFovDegrees", field_of_view_degrees)), 40.0, 180.0)
	reaction_time = clampf(float(record.get("aiReactionTime", reaction_time)), 0.05, 1.5)
	aim_acquisition_time = clampf(float(record.get("aiAimAcquisitionTime", aim_acquisition_time)), 0.05, 1.2)
	rifle_damage = clampi(int(record.get("aiDamage", rifle_damage)), 1, 100)
	primary_weapon_id = String(record.get("aiPrimaryWeapon", primary_weapon_id))
	secondary_weapon_id = String(record.get("aiSecondaryWeapon", secondary_weapon_id))
	has_knife = bool(record.get("aiHasKnife", has_knife))
	retreat_health_ratio = clampf(float(record.get("aiRetreatHealthRatio", retreat_health_ratio)), 0.1, 0.9)
	hold_angle_seconds = clampf(float(record.get("aiHoldAngleSeconds", hold_angle_seconds)), 0.2, 5.0)
	damage_memory_seconds = clampf(float(record.get("aiDamageMemorySeconds", damage_memory_seconds)), 0.5, 8.0)
	crouch_during_combat_chance = clampf(float(record.get("aiCrouchChance", crouch_during_combat_chance)), 0.0, 1.0)
	has_defuse_kit = bool(record.get("defuseKit", has_defuse_kit))
	combat_enabled = bool(record.get("aiCombatEnabled", combat_enabled))
	ai_money = clampi(int(record.get("aiMoney", ai_money)), 0, 16000)
	recoil_compensation = clampf(float(record.get("aiRecoilCompensation", recoil_compensation)), 0.0, 0.05)
	_route_points = BotNavigationModel.parse_points(record.get("routePoints", []))
	_navigation.configure(record.get("navigationGraph", {}))
	_route_index = _nearest_route_index()
	_route_direction = -1 if String(actor.get("team")) == "CT" else 1
	_reset_weapon_ammo()
	_reset_runtime()
	_apply_configured_grenades(record)
	var saved_mag := int(record.get("weaponAmmoMag", -1))
	var saved_reserve := int(record.get("weaponAmmoReserve", -1))
	if saved_mag >= 0 and _weapon_ammo.has(primary_weapon_id):
		_weapon_ammo[primary_weapon_id] = clampi(saved_mag, 0, int(WEAPON_PROFILES[primary_weapon_id].get("magazine", 30)))
		if _current_weapon_id == primary_weapon_id:
			ammo_in_mag = int(_weapon_ammo[primary_weapon_id])
	if saved_reserve >= 0 and _weapon_reserve.has(primary_weapon_id):
		_weapon_reserve[primary_weapon_id] = maxi(0, saved_reserve)

func tick(delta: float) -> void:
	if actor == null or not enabled or bool(actor.get("is_dead")):
		return
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)
	_burst_pause = maxf(0.0, _burst_pause - delta)
	_grenade_cooldown = maxf(0.0, _grenade_cooldown - delta)
	_repath_seconds = maxf(0.0, _repath_seconds - delta)
	_heard_seconds += delta
	_damage_seconds += delta
	_lost_sight_seconds += delta
	_tick_danger_memory(delta)
	_tick_teammate_reports(delta)
	_refresh_c4_knowledge()
	if not RoundManager.can_player_move():
		if RoundManager.can_buy():
			_tick_freeze_purchase()
		state = State.HOLD
		_stop(delta)
		return
	_try_pickup_weapon_nearby()
	if state == State.RELOAD:
		_tick_reload(delta)
		return
	if state == State.RETREAT:
		_tick_retreat(delta)
		return
	if _bomb_interacting:
		_tick_bomb_interaction(delta)
		return

	_target = _find_local_target()
	var visible := _target != null and _can_see(_target)
	if visible:
		_lost_sight_seconds = 0.0
		_last_known_position = _target.global_position
		_visible_seconds += delta
		_hold_angle_timer = hold_angle_seconds
		if _target != null and _visible_seconds >= reaction_time and _spot_emitted_target != _target.get_instance_id():
			_spot_emitted_target = _target.get_instance_id()
			var enemy_team := GameState.player_team
			if _target.is_in_group("combat_actors"):
				enemy_team = String(_target.get("team"))
			actor.call("emit_ai_spot", _target.global_position, enemy_team)
		if _visible_seconds < reaction_time:
			state = State.ACQUIRE
			_aim_at(_target.global_position + Vector3.UP * 0.18, delta, aim_acquisition_time)
			_stop(delta)
		else:
			state = State.ENGAGE
			_tick_engage(delta)
		return
	_visible_seconds = 0.0
	_spot_emitted_target = 0

	if _hold_angle_timer > 0.0:
		state = State.HOLD_ANGLE
		_tick_hold_angle(delta)
		return

	if _should_run_bomb_objective():
		state = State.OBJECTIVE
		_tick_bomb_objective(delta)
		return

	if _should_save_gun():
		_begin_save_gun(delta)
		return

	if not _teammate_reports.is_empty() and _heard_seconds > hearing_memory_seconds:
		state = State.INVESTIGATE
		var report_position := _nearest_teammate_report()
		if actor.global_position.distance_to(report_position) <= 1.0:
			_stop(delta)
		else:
			_move_toward(report_position, delta)
		return

	if _heard_seconds <= hearing_memory_seconds:
		state = State.INVESTIGATE
		if actor.global_position.distance_to(_last_known_position) <= 1.0:
			_stop(delta)
		else:
			_move_toward(_last_known_position, delta)
		return
	state = State.PATROL if not _route_points.is_empty() else State.HOLD
	if state == State.PATROL:
		_tick_patrol(delta)
	else:
		_stop(delta)

func notify_sound(world_position: Vector3, audible_radius: float, source_team: String) -> bool:
	if not enabled or source_team == String(actor.get("team")):
		return false
	if actor.global_position.distance_to(world_position) > audible_radius:
		return false
	_last_known_position = world_position
	_heard_seconds = 0.0
	record_dynamic_danger(world_position, 0.55)
	return true

func notify_damage(hit_position: Vector3, source_team: String, source_position: Vector3 = Vector3.INF) -> void:
	if actor == null or not enabled:
		return
	_damage_count += 1
	_damage_seconds = 0.0
	_damage_position = hit_position
	if source_team.is_empty() or source_team == String(actor.get("team")):
		return
	_last_known_position = source_position if source_position.is_finite() else hit_position
	_heard_seconds = 0.0
	_hold_angle_timer = maxf(_hold_angle_timer, hold_angle_seconds)
	record_dynamic_danger(_last_known_position, 0.9)

func record_dynamic_danger(world_position: Vector3, intensity: float = 0.7) -> void:
	if actor == null:
		return
	_danger_events.append({
		"position": world_position,
		"intensity": clampf(intensity, 0.0, 1.0),
		"radius": 9.0,
		"remaining": danger_memory_seconds,
	})
	if _danger_events.size() > 8:
		_danger_events.pop_front()

func configure_objective(role: String, target: Vector3, site_label: String = "", carrier: bool = false) -> void:
	objective_role = role
	objective_target = target
	plant_site_label = site_label
	bomb_carrier = carrier

func set_team_economy(team_money_value: int, loss_streak_value: int) -> void:
	team_money = maxi(0, team_money_value)
	team_loss_streak = maxi(0, loss_streak_value)
	if team_money >= 9000:
		economy_mode = "force"
	elif team_money >= 4500:
		economy_mode = "half"
	else:
		economy_mode = "eco"

func set_c4_device(device: Node3D) -> void:
	_c4_device = device
	_refresh_c4_knowledge()

func set_defuse_kit(has_kit: bool) -> void:
	has_defuse_kit = has_kit

func set_ai_combat_enabled(enabled_combat: bool) -> void:
	combat_enabled = enabled_combat

func notify_teammate_report(world_position: Vector3, enemy_team: String) -> void:
	if actor == null or not enabled:
		return
	_teammate_reports.append({"position": world_position, "remaining": 4.5})
	if _teammate_reports.size() > 6:
		_teammate_reports.pop_front()

func get_objective_snapshot() -> Dictionary:
	return {
		"role": objective_role,
		"target": objective_target,
		"site": plant_site_label,
		"carrier": bomb_carrier,
		"interacting": _bomb_interacting,
		"interaction_type": _bomb_interaction_type,
		"defuse_kit": has_defuse_kit,
		"teammate_reports": _teammate_reports.size(),
	}

func get_weapon_pickup_record() -> Dictionary:
	return {
		"weapon_id": _current_weapon_id,
		"slot_index": int(WEAPON_PROFILES.get(_current_weapon_id, {}).get("slot", 0)),
		"ammo_in_mag": ammo_in_mag,
		"ammo_reserve": int(_weapon_reserve.get(_current_weapon_id, 0)),
	}

func get_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"state": State.keys()[state],
		"ammo": ammo_in_mag,
		"ammo_reserve": int(_weapon_reserve.get(_current_weapon_id, 0)),
		"shots": _shot_count,
		"weapon_id": _current_weapon_id,
		"weapon_slot": int(WEAPON_PROFILES.get(_current_weapon_id, {}).get("slot", 0)),
		"burst_size": _burst_size,
		"spray_decision": _spray_decision,
		"route_points": _route_points.size(),
		"navigation_nodes": _navigation.points.size(),
		"navigation_links": _navigation.link_count,
		"navigation_path_nodes": maxi(0, _navigation_path.size() - _navigation_path_index),
		"active_navigation_link": _active_navigation_link.duplicate(true),
		"stuck_seconds": _no_progress_seconds,
		"stuck_recoveries": _stuck_recoveries,
		"recovering": _recovery_seconds > 0.0,
		"last_known_position": _last_known_position,
		"heard_seconds": _heard_seconds,
		"target_visible_seconds": _visible_seconds,
		"damage_count": _damage_count,
		"damage_seconds": _damage_seconds,
		"damage_position": _damage_position,
		"hold_angle_seconds": _hold_angle_timer,
		"dodges": _dodge_count,
		"crouches": _crouch_count,
		"retreating": _retreat_seconds > 0.0,
		"danger_events": _danger_events.size(),
		"equip_seconds": _equip_seconds,
		"objective_role": objective_role,
		"objective_target": objective_target,
		"bomb_carrier": bomb_carrier,
		"defuse_kit": has_defuse_kit,
		"bomb_interacting": _bomb_interacting,
		"teammate_reports": _teammate_reports.size(),
		"money": ai_money,
		"grenades": grenade_counts.duplicate(true),
		"recoil_compensation": recoil_compensation,
		"recoil_compensated_shots": _recoil_compensated_shots,
		"grenade_cooldown": _grenade_cooldown,
		"economy_mode": economy_mode,
		"saving_gun": save_gun_active,
		"team_money": team_money,
		"team_loss_streak": team_loss_streak,
	}

func reset_runtime() -> void:
	ammo_in_mag = magazine_size
	_reset_runtime()

func _reset_runtime() -> void:
	state = State.HOLD
	_target = null
	_last_known_position = actor.global_position if actor != null else Vector3.ZERO
	_heard_seconds = 999.0
	_visible_seconds = 0.0
	_shot_cooldown = 0.0
	_burst_pause = 0.0
	_shots_in_burst = 0
	_reload_seconds = 0.0
	_navigation_path.clear()
	_navigation_path_index = 0
	_navigation_destination = Vector3.INF
	_repath_seconds = 0.0
	_active_navigation_link.clear()
	_last_progress_position = actor.global_position if actor != null else Vector3.ZERO
	_no_progress_seconds = 0.0
	_recovery_seconds = 0.0
	_recovery_direction = Vector3.ZERO
	_recovery_flip = false
	_stuck_recoveries = 0
	_reset_weapon_ammo()
	_equip_seconds = 0.0
	_burst_size = 3
	_spray_decision = "burst"
	_dodge_timer = 0.0
	_dodge_active = 0.0
	_dodge_direction = Vector3.ZERO
	_dodge_count = 0
	_dodge_flip = false
	_crouch_timer = 0.0
	_crouch_active = 0.0
	_crouch_count = 0
	_hold_angle_timer = 0.0
	_retreat_seconds = 0.0
	_retreat_target = Vector3.ZERO
	_lost_sight_seconds = 999.0
	_damage_seconds = 999.0
	_damage_count = 0
	_damage_position = Vector3.ZERO
	_danger_events.clear()
	objective_role = ""
	objective_target = Vector3.INF
	plant_site_label = ""
	bomb_carrier = false
	_c4_known_position = Vector3.INF
	_c4_known_state = ""
	_bomb_interacting = false
	_bomb_interaction_type = ""
	_teammate_reports.clear()
	_spot_emitted_target = 0
	grenade_counts = {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0}
	_grenade_cooldown = 0.0
	_purchased_this_round = false
	_smoke_thrown_for_objective = false
	_flash_thrown_for_target = 0
	_he_thrown_for_target = 0
	_recoil_compensated_shots = 0
	economy_mode = "force"
	save_gun_active = false
	team_money = -1
	team_loss_streak = 0

func _find_local_target() -> CharacterBody3D:
	if not combat_enabled:
		return null
	var my_team := String(actor.get("team"))
	var best_target: CharacterBody3D = null
	var best_distance := INF
	var candidate := actor.get_tree().get_first_node_in_group("local_player")
	if candidate is CharacterBody3D and not bool(candidate.get("is_dead")) and my_team != GameState.player_team:
		best_target = candidate as CharacterBody3D
		best_distance = actor.global_position.distance_squared_to(candidate.global_position)
	for candidate_variant in actor.get_tree().get_nodes_in_group("combat_actors"):
		if not candidate_variant is CharacterBody3D:
			continue
		var combatant := candidate_variant as CharacterBody3D
		if combatant == actor or bool(combatant.get("is_dead")) or String(combatant.get("team")) == my_team:
			continue
		var distance := actor.global_position.distance_squared_to(combatant.global_position)
		if distance < best_distance:
			best_target = combatant
			best_distance = distance
	return best_target

func _can_see(target: CharacterBody3D) -> bool:
	var eye := actor.call("get_eye_position") as Vector3
	var target_point := target.global_position + Vector3.UP * 0.18
	var delta := target_point - eye
	if delta.length() > view_distance or delta.length_squared() <= 0.001:
		return false
	var forward := -actor.global_transform.basis.z
	if forward.dot(delta.normalized()) < cos(deg_to_rad(field_of_view_degrees * 0.5)):
		return false
	if _segment_blocked_by_smoke(eye, target_point):
		return false
	# Cast slightly through the target. Godot can omit a body when the ray ends
	# inside its collision shape, which made close-range visibility unreliable.
	var query := PhysicsRayQueryParameters3D.create(eye, target_point + delta.normalized() * 0.75, 1)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider", null) == target

func _tick_engage(delta: float) -> void:
	if _target == null:
		return
	var health_ratio := float(int(actor.get("current_health"))) / maxf(float(int(actor.get("max_health"))), 1.0)
	if health_ratio <= retreat_health_ratio:
		state = State.RETREAT
		_retreat_seconds = 1.2
		_retreat_target = _pick_retreat_target(_target.global_position)
		return
	var target_point: Vector3 = _target.global_position + Vector3.UP * 0.18
	var distance := actor.global_position.distance_to(_target.global_position)
	_aim_at(target_point, delta, aim_tracking_time)
	var plan := _resolve_combat_plan(distance)
	_burst_size = int(plan.get("size", 3))
	_next_burst_pause = float(plan.get("pause", 0.45))
	_update_combat_stance(delta)
	_update_dodge(delta)
	_update_weapon_selection(distance)
	_maybe_throw_combat_grenade(_target)
	if _current_weapon_id == "knife":
		_dodge_active = 0.0
		_dodge_timer = maxf(_dodge_timer, dodge_interval + _rng.randf_range(0.0, 0.55))
		_stop(delta)
		actor.call("set_ai_crouching", _crouch_active > 0.0)
	else:
		if _dodge_active > 0.0:
			_strafe_dodge(delta)
		else:
			_stop(delta)
			actor.call("set_ai_crouching", _crouch_active > 0.0)
	if _equip_seconds > 0.0:
		_equip_seconds = maxf(0.0, _equip_seconds - delta)
		return
	if Vector2(actor.velocity.x, actor.velocity.z).length() > 0.42:
		return
	if _current_weapon_id != "knife" and ammo_in_mag <= 0:
		if _weapon_has_ammo(secondary_weapon_id) and secondary_weapon_id != _current_weapon_id:
			_switch_to_weapon(secondary_weapon_id)
			return
		state = State.RELOAD
		_reload_seconds = float(_current_profile().get("reload", reload_duration))
		return
	var forward: Vector3 = -actor.global_transform.basis.z
	var eye_position := actor.call("get_eye_position") as Vector3
	var aim_direction: Vector3 = (target_point - eye_position).normalized()
	var planar_aim := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if forward.dot(planar_aim) < cos(deg_to_rad(3.2)):
		return
	if _shot_cooldown > 0.0 or _burst_pause > 0.0:
		return
	_fire_shot(target_point)

func _fire_shot(target_point: Vector3) -> void:
	var profile := _current_profile()
	var weapon_name := String(profile.get("label", "AI步枪"))
	var weapon_slot := int(profile.get("slot", 0))
	var max_range := float(profile.get("max_range", view_distance))
	if _current_weapon_id == "knife":
		_fire_melee(target_point, profile, weapon_name, weapon_slot)
		return
	ammo_in_mag = maxi(0, ammo_in_mag - 1)
	_weapon_ammo[_current_weapon_id] = ammo_in_mag
	_shot_count += 1
	_shots_in_burst += 1
	_shot_cooldown = float(profile.get("fire_interval", shot_interval))
	var origin := actor.call("get_eye_position") as Vector3
	var direction: Vector3 = (target_point - origin).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(direction).normalized()
	if recoil_compensation > 0.0 and _shots_in_burst > 1:
		var pattern_index := mini(_shots_in_burst - 1, RECOIL_COMPENSATION_PATTERN.size() - 1)
		var compensation_drop: float = float(RECOIL_COMPENSATION_PATTERN[pattern_index]) * (recoil_compensation / 0.006)
		direction = (direction + Vector3.DOWN * compensation_drop).normalized()
		_recoil_compensated_shots += 1
	var error_scale := 0.0045 + float(_shots_in_burst - 1) * 0.0025
	direction = (direction + right * _rng.randf_range(-error_scale, error_scale) + up * _rng.randf_range(-error_scale, error_scale)).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range, 1)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var damage_result: Dictionary = {}
	if not hit.is_empty():
		var collider: Variant = hit.get("collider", null)
		if collider != null and collider.has_method("apply_hitscan_damage"):
			var collider_team := ""
			if collider is Node and (collider as Node).is_in_group("combat_actors"):
				collider_team = String((collider as Node).get("team"))
			elif collider is Node and (collider as Node).is_in_group("local_player"):
				collider_team = GameState.player_team
			var same_team := not collider_team.is_empty() and collider_team == String(actor.get("team"))
			if not same_team:
				damage_result = collider.call(
					"apply_hitscan_damage",
					int(profile.get("damage", rifle_damage)),
					hit.get("position", Vector3.ZERO),
					0.77,
					false,
					String(actor.get("team")),
					origin
				) as Dictionary
	actor.call("emit_ai_shot", {
		"hit": bool(damage_result.get("hit", false)),
		"position": hit.get("position", origin + direction * max_range),
		"damage_result": damage_result,
		"weapon_slot": weapon_slot,
		"weapon_name": weapon_name,
		"shooter_name": String(actor.get("display_name")),
		"shooter_team": String(actor.get("team")),
	}, origin)
	record_dynamic_danger(origin, 0.4)
	if _shots_in_burst >= _burst_size:
		_shots_in_burst = 0
		_burst_pause = _next_burst_pause

func _tick_reload(delta: float) -> void:
	_stop(delta)
	_reload_seconds = maxf(0.0, _reload_seconds - delta)
	if _reload_seconds == 0.0:
		var profile := _current_profile()
		var magazine := int(profile.get("magazine", magazine_size))
		var reserve := int(_weapon_reserve.get(_current_weapon_id, 0))
		var loaded := mini(magazine - ammo_in_mag, reserve)
		ammo_in_mag += maxi(0, loaded)
		_weapon_reserve[_current_weapon_id] = maxi(0, reserve - loaded)
		_weapon_ammo[_current_weapon_id] = ammo_in_mag
		state = State.ACQUIRE

func _tick_hold_angle(delta: float) -> void:
	_stop(delta)
	_aim_at(_last_known_position, delta, aim_tracking_time)
	_hold_angle_timer = maxf(0.0, _hold_angle_timer - delta)
	if _hold_angle_timer <= 0.0:
		state = State.HOLD

func _tick_retreat(delta: float) -> void:
	_retreat_seconds = maxf(0.0, _retreat_seconds - delta)
	if _target != null:
		_aim_at(_target.global_position + Vector3.UP * 0.18, delta, aim_tracking_time)
	if _retreat_seconds <= 0.0:
		state = State.HOLD
		_stop(delta)
		return
	if actor.global_position.distance_to(_retreat_target) <= 1.2:
		_stop(delta)
	else:
		_move_toward(_retreat_target, delta)
	if (
		_target != null
		and ammo_in_mag > 0
		and _shot_cooldown <= 0.0
		and _burst_pause <= 0.0
		and Vector2(actor.velocity.x, actor.velocity.z).length() <= 0.42
	):
		_fire_shot(_target.global_position + Vector3.UP * 0.18)

func _should_save_gun() -> bool:
	if not save_gun_enabled or economy_mode != "eco" or RoundManager.state != RoundManager.RoundState.LIVE:
		return false
	if int(actor.get("current_health")) > 45:
		return false
	var team_name := String(actor.get("team"))
	if team_name == "T" and bomb_carrier:
		return false
	if team_name == "CT" and RoundManager.state == RoundManager.RoundState.BOMB_PLANTED:
		return false
	return true

func _begin_save_gun(delta: float) -> void:
	save_gun_active = true
	state = State.RETREAT
	_retreat_seconds = maxf(_retreat_seconds, 2.0)
	if not _retreat_target.is_finite() or actor.global_position.distance_to(_retreat_target) <= 1.5:
		_retreat_target = _pick_save_gun_target()
	_tick_retreat(delta)

func _pick_save_gun_target() -> Vector3:
	var backward := actor.global_transform.basis.z * 5.0
	backward.y = 0.0
	return actor.global_position + backward

func _should_run_bomb_objective() -> bool:
	if objective_role.is_empty() or not objective_target.is_finite():
		return false
	var team_name := String(actor.get("team"))
	if team_name == "T":
		return RoundManager.state in [RoundManager.RoundState.LIVE] and objective_role in ["plant", "support", "diversion"]
	if team_name == "CT":
		return RoundManager.state in [RoundManager.RoundState.LIVE, RoundManager.RoundState.BOMB_PLANTED] and objective_role in ["defend_site", "retake", "defuse"]
	return false

func _tick_bomb_objective(delta: float) -> void:
	var team_name := String(actor.get("team"))
	if team_name == "T":
		_tick_t_side_objective(delta)
	else:
		_tick_ct_side_objective(delta)

func _tick_t_side_objective(delta: float) -> void:
	if not bomb_carrier and RoundManager.bomb_carried == false and _try_pick_up_c4():
		bomb_carrier = true
		RoundManager.bomb_carried = true
	_maybe_throw_objective_smoke()
	if not bomb_carrier:
		_move_to_or_hold(delta, objective_target)
		return
	if not objective_target.is_finite():
		_stop(delta)
		return
	_move_to_or_hold(delta, objective_target)
	if (
		actor.global_position.distance_to(objective_target) <= plant_radius_meters
		and not RoundManager.is_objective_interacting()
		and RoundManager.bomb_carried
	):
		_begin_plant()

func _tick_ct_side_objective(delta: float) -> void:
	var bomb_planted := RoundManager.state == RoundManager.RoundState.BOMB_PLANTED
	if bomb_planted:
		var destination := _c4_known_position if _c4_known_position.is_finite() else objective_target
		_move_to_or_hold(delta, destination)
		if (
			_c4_device != null
			and is_instance_valid(_c4_device)
			and actor.global_position.distance_to(_c4_device.global_position) <= defuse_radius_meters
			and not RoundManager.is_objective_interacting()
		):
			_begin_defuse()
	else:
		_move_to_or_hold(delta, objective_target)

func _move_to_or_hold(delta: float, destination: Vector3) -> void:
	if not destination.is_finite():
		_stop(delta)
		return
	if actor.global_position.distance_to(destination) <= 1.2:
		_stop(delta)
		_aim_at(destination, delta, 0.25)
	else:
		_move_toward(destination, delta)

func _try_pick_up_c4() -> bool:
	if _c4_device == null or not is_instance_valid(_c4_device):
		return false
	if not bool(_c4_device.call("can_pick_up", actor.global_position, "T")):
		return false
	return bool(_c4_device.call("pick_up", "T"))

func _begin_plant() -> void:
	if _c4_device == null or not is_instance_valid(_c4_device):
		return
	if not RoundManager.begin_plant(plant_site_label, "T", "ai"):
		return
	_bomb_interacting = true
	_bomb_interaction_type = "plant"

func _begin_defuse() -> void:
	if _c4_device == null or not is_instance_valid(_c4_device):
		return
	if not RoundManager.begin_defuse("CT", has_defuse_kit, "ai"):
		return
	_bomb_interacting = true
	_bomb_interaction_type = "defuse"

func _tick_bomb_interaction(delta: float) -> void:
	_stop(delta)
	if not RoundManager.is_objective_interacting():
		_bomb_interacting = false
		_bomb_interaction_type = ""
		return
	var still_valid := false
	if _bomb_interaction_type == "plant":
		still_valid = actor.global_position.distance_to(objective_target) <= plant_radius_meters and RoundManager.bomb_carried
	elif _bomb_interaction_type == "defuse":
		still_valid = (
			_c4_device != null
			and is_instance_valid(_c4_device)
			and actor.global_position.distance_to(_c4_device.global_position) <= defuse_radius_meters
		)
	var completed := RoundManager.tick_objective_interaction(delta, still_valid)
	if completed:
		if _bomb_interaction_type == "plant" and _c4_device != null and is_instance_valid(_c4_device):
			_c4_device.call("plant_at", actor.global_position - Vector3(0.0, 0.82, 0.0), plant_site_label)
			bomb_carrier = false
			RoundManager.bomb_carried = false
		elif _bomb_interaction_type == "defuse" and _c4_device != null and is_instance_valid(_c4_device):
			_c4_device.call("set_carried", "CT")
		_bomb_interacting = false
		_bomb_interaction_type = ""
	elif not still_valid:
		RoundManager.cancel_objective_interaction()
		_bomb_interacting = false
		_bomb_interaction_type = ""

func _refresh_c4_knowledge() -> void:
	if _c4_device == null or not is_instance_valid(_c4_device):
		return
	var device_state := String(_c4_device.get("device_state"))
	_c4_known_state = device_state
	if device_state in ["planted", "dropped"]:
		_c4_known_position = _c4_device.global_position

func _tick_freeze_purchase() -> void:
	if _purchased_this_round:
		return
	_purchased_this_round = true
	var economy_money := ai_money if team_money < 0 else team_money
	var force_threshold := 9000 if team_money >= 0 else 4200
	var half_threshold := 4500 if team_money >= 0 else 1800
	if economy_money >= force_threshold:
		economy_mode = "force"
	elif economy_money >= half_threshold:
		economy_mode = "half"
	else:
		economy_mode = "eco"
	if economy_mode == "eco":
		return
	var team_name := String(actor.get("team"))
	if economy_mode == "force" and int(actor.get("current_armor")) < 100 and ai_money >= 650:
		ai_money -= 650
		actor.set("current_armor", 100)
	var grenade_kinds: Array[String] = []
	if economy_mode == "force":
		grenade_kinds.append("smoke_grenade")
		if team_name == "CT":
			grenade_kinds.append("flash_grenade")
	elif team_name == "CT" and ai_money >= 300:
		grenade_kinds.append("smoke_grenade")
	for kind in grenade_kinds:
		if int(grenade_counts.get(kind, 0)) > 0:
			continue
		var price := 300 if kind == "smoke_grenade" else 200
		if ai_money >= price:
			ai_money -= price
			grenade_counts[kind] = 1
	if team_name == "CT" and not has_defuse_kit and ai_money >= 400:
		ai_money -= 400
		has_defuse_kit = true
		if actor.has_method("set_ai_defuse_kit"):
			actor.call("set_ai_defuse_kit", true)

func _apply_configured_grenades(record: Dictionary) -> void:
	var grenade_variant: Variant = record.get("aiGrenades", {})
	if not grenade_variant is Dictionary:
		return
	var configured := grenade_variant as Dictionary
	for kind in grenade_counts:
		if configured.has(kind):
			grenade_counts[kind] = clampi(int(configured.get(kind, 0)), 0, 4)

func _try_pickup_weapon_nearby() -> bool:
	var tree := actor.get_tree()
	if tree == null:
		return false
	for pickup_variant in tree.get_nodes_in_group("weapon_pickups"):
		if not pickup_variant is Node3D:
			continue
		var pickup := pickup_variant as Node3D
		if not pickup.has_method("can_pick_up") or not bool(pickup.call("can_pick_up", actor.global_position)):
			continue
		var weapon_record: Variant = pickup.get("weapon_record")
		if not weapon_record is Dictionary:
			continue
		var record := weapon_record as Dictionary
		var weapon_id := String(record.get("weapon_id", ""))
		if not WEAPON_PROFILES.has(weapon_id):
			continue
		var picked_mag := int(record.get("ammo_in_mag", 0))
		var picked_reserve := int(record.get("ammo_reserve", 0))
		_weapon_owned[weapon_id] = true
		_weapon_ammo[weapon_id] = maxi(int(_weapon_ammo.get(weapon_id, 0)), picked_mag)
		_weapon_reserve[weapon_id] = maxi(int(_weapon_reserve.get(weapon_id, 0)), picked_reserve)
		if _current_weapon_id == weapon_id:
			ammo_in_mag = int(_weapon_ammo.get(weapon_id, 0))
		elif weapon_id == primary_weapon_id and not _weapon_is_owned(primary_weapon_id):
			_switch_to_weapon(primary_weapon_id)
		pickup.queue_free()
		return true
	return false

func _throw_ai_grenade(kind: String, target_position: Vector3) -> bool:
	if _grenade_cooldown > 0.0 or int(grenade_counts.get(kind, 0)) <= 0:
		return false
	var tree := actor.get_tree()
	if tree == null or tree.current_scene == null:
		return false
	var projectile := GrenadeProjectile.new()
	tree.current_scene.add_child(projectile)
	var origin := actor.call("get_eye_position") as Vector3
	var direction := (target_position - origin).normalized()
	var distance := origin.distance_to(target_position)
	var throw_speed := clampf(distance * 0.9, 8.0, 15.0)
	var flight_time := distance / maxf(throw_speed, 0.01)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var throw_arc := 0.5 * gravity * flight_time
	projectile.configure(kind, actor, origin, direction * throw_speed + Vector3.UP * throw_arc)
	grenade_counts[kind] = int(grenade_counts.get(kind, 0)) - 1
	_grenade_cooldown = 4.0
	record_dynamic_danger(origin, 0.35)
	return true

func _maybe_throw_combat_grenade(target: CharacterBody3D) -> void:
	var distance := actor.global_position.distance_to(target.global_position)
	var target_id := target.get_instance_id()
	if int(grenade_counts.get("flash_grenade", 0)) > 0 and distance <= 14.0 and _flash_thrown_for_target != target_id:
		_flash_thrown_for_target = target_id
		if _throw_ai_grenade("flash_grenade", target.global_position + Vector3.UP * 0.5):
			_burst_pause = maxf(_burst_pause, 0.65)
		return
	if int(grenade_counts.get("he_grenade", 0)) > 0 and distance <= 12.0 and _he_thrown_for_target != target_id:
		_he_thrown_for_target = target_id
		if _throw_ai_grenade("he_grenade", target.global_position):
			_burst_pause = maxf(_burst_pause, 0.65)

func _maybe_throw_objective_smoke() -> void:
	if _smoke_thrown_for_objective or int(grenade_counts.get("smoke_grenade", 0)) <= 0:
		return
	if not objective_target.is_finite() or actor.global_position.distance_to(objective_target) > 16.0:
		return
	var smoke_landing := actor.global_position.lerp(objective_target, 0.78)
	if _throw_ai_grenade("smoke_grenade", smoke_landing):
		_smoke_thrown_for_objective = true

func _tick_teammate_reports(delta: float) -> void:
	var retained: Array[Dictionary] = []
	for report_variant in _teammate_reports:
		var report := report_variant.duplicate(true)
		report["remaining"] = float(report.get("remaining", 0.0)) - delta
		if float(report.get("remaining", 0.0)) > 0.0:
			retained.append(report)
	_teammate_reports = retained

func _nearest_teammate_report() -> Vector3:
	var best_position := _last_known_position
	var best_distance := INF
	for report_variant in _teammate_reports:
		var report := report_variant as Dictionary
		var report_position := report.get("position", Vector3.ZERO) as Vector3
		var distance := actor.global_position.distance_squared_to(report_position)
		if distance < best_distance:
			best_distance = distance
			best_position = report_position
	return best_position

func _update_combat_stance(delta: float) -> void:
	_crouch_active = maxf(0.0, _crouch_active - delta)
	if _crouch_active > 0.0:
		return
	_crouch_timer = maxf(0.0, _crouch_timer - delta)
	if _crouch_timer > 0.0:
		return
	_crouch_timer = 1.1 + _rng.randf_range(0.0, 1.0)
	if _rng.randf() < crouch_during_combat_chance:
		_crouch_active = 0.55
		_crouch_count += 1

func _update_dodge(delta: float) -> void:
	_dodge_active = maxf(0.0, _dodge_active - delta)
	if _dodge_active > 0.0:
		return
	_dodge_timer = maxf(0.0, _dodge_timer - delta)
	if _dodge_timer > 0.0:
		return
	var target_distance := INF
	if _target != null:
		target_distance = actor.global_position.distance_to(_target.global_position)
	if target_distance < dodge_min_range_meters or target_distance > dodge_max_range_meters:
		_dodge_timer = 0.45
		return
	_dodge_timer = dodge_interval + _rng.randf_range(0.0, 0.45)
	_dodge_active = dodge_duration
	_dodge_count += 1
	_dodge_flip = not _dodge_flip
	var aim_forward := -actor.global_transform.basis.z
	aim_forward.y = 0.0
	if aim_forward.length_squared() <= 0.001:
		aim_forward = Vector3.FORWARD
	_dodge_direction = aim_forward.normalized().rotated(
		Vector3.UP,
		PI * 0.5 if _dodge_flip else -PI * 0.5
	)

func _strafe_dodge(delta: float) -> void:
	actor.call("apply_ai_navigation", _dodge_direction, move_speed * 0.58, actor.global_position.y, delta)

func _update_weapon_selection(distance: float) -> void:
	var desired := primary_weapon_id
	if has_knife:
		if _current_weapon_id == "knife":
			desired = "knife"
			if distance > melee_commit_range_meters:
				desired = primary_weapon_id
		elif distance <= melee_switch_range_meters and _damage_seconds > 1.2:
			desired = "knife"
	if (
		desired == primary_weapon_id
		and not _weapon_has_ammo(primary_weapon_id)
		and _weapon_has_ammo(secondary_weapon_id)
	):
		desired = secondary_weapon_id
	if desired != _current_weapon_id and _weapon_is_owned(desired):
		_switch_to_weapon(desired)

func _switch_to_weapon(weapon_id: String) -> void:
	if not _weapon_is_owned(weapon_id) or weapon_id == _current_weapon_id:
		return
	_current_weapon_id = weapon_id
	ammo_in_mag = int(_weapon_ammo.get(weapon_id, 0))
	_shots_in_burst = 0
	_burst_pause = maxf(_burst_pause, 0.12)
	_equip_seconds = float(WEAPON_PROFILES.get(weapon_id, {}).get("equip", 0.26))

func _current_profile() -> Dictionary:
	return WEAPON_PROFILES.get(_current_weapon_id, WEAPON_PROFILES["rifle"])

func _weapon_is_owned(weapon_id: String) -> bool:
	return bool(_weapon_owned.get(weapon_id, false))

func _weapon_has_ammo(weapon_id: String) -> bool:
	if not _weapon_is_owned(weapon_id):
		return false
	return int(_weapon_ammo.get(weapon_id, 0)) > 0 or weapon_id == "knife"

func _resolve_combat_plan(distance: float) -> Dictionary:
	if distance >= tap_range_meters:
		_spray_decision = "tap"
		return {"size": 1, "pause": 0.55}
	if distance >= spray_range_meters:
		_spray_decision = "burst"
		return {"size": 3, "pause": 0.42}
	_spray_decision = "spray"
	return {"size": 7, "pause": 0.68}

func _pick_retreat_target(enemy_position: Vector3) -> Vector3:
	if _navigation.points.is_empty():
		var away := actor.global_position - enemy_position
		away.y = 0.0
		if away.length_squared() <= 0.001:
			away = -actor.global_transform.basis.z
		return actor.global_position + away.normalized() * 4.5
	var best_position := actor.global_position
	var best_score := -INF
	for point_variant in _navigation.points:
		var point := point_variant as Vector3
		var distance := actor.global_position.distance_to(point)
		if distance < 2.0 or distance > 14.0:
			continue
		var from_enemy := point - enemy_position
		from_enemy.y = 0.0
		var separation := from_enemy.length()
		if separation <= 0.1:
			continue
		var cover_score := 0.0
		var node_index := _navigation.nearest_index(point)
		if node_index >= 0:
			for link_variant in _navigation.links_at(node_index):
				cover_score = maxf(cover_score, float((link_variant as Dictionary).get("cover", 0.0)))
		var score := cover_score * 2.4 + separation * 0.18 - distance * 0.06
		if score > best_score:
			best_score = score
			best_position = point
	return best_position

func _fire_melee(target_point: Vector3, profile: Dictionary, weapon_name: String, weapon_slot: int) -> void:
	_shot_count += 1
	_shots_in_burst += 1
	_shot_cooldown = float(profile.get("fire_interval", 0.42))
	var origin := actor.call("get_eye_position") as Vector3
	var direction := (target_point - origin).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * float(profile.get("max_range", 2.4)), 1)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var damage_result: Dictionary = {}
	if not hit.is_empty():
		var collider: Variant = hit.get("collider", null)
		if collider != null and collider.has_method("apply_hitscan_damage"):
			var collider_team := ""
			if collider is Node and (collider as Node).is_in_group("combat_actors"):
				collider_team = String((collider as Node).get("team"))
			elif collider is Node and (collider as Node).is_in_group("local_player"):
				collider_team = GameState.player_team
			if collider_team.is_empty() or collider_team != String(actor.get("team")):
				damage_result = collider.call(
					"apply_hitscan_damage",
					int(profile.get("damage", 55)),
					hit.get("position", Vector3.ZERO),
					1.0,
					false,
					String(actor.get("team")),
					origin
				) as Dictionary
	actor.call("emit_ai_shot", {
		"hit": bool(damage_result.get("hit", false)),
		"position": hit.get("position", origin + direction * 2.4),
		"damage_result": damage_result,
		"weapon_slot": weapon_slot,
		"weapon_name": weapon_name,
		"shooter_name": String(actor.get("display_name")),
		"shooter_team": String(actor.get("team")),
	}, origin)
	if _shots_in_burst >= _burst_size:
		_shots_in_burst = 0
		_burst_pause = _next_burst_pause

func _reset_weapon_ammo() -> void:
	_weapon_ammo.clear()
	_weapon_reserve.clear()
	_weapon_owned.clear()
	for weapon_id in WEAPON_PROFILES:
		var profile: Dictionary = WEAPON_PROFILES[weapon_id]
		_weapon_ammo[weapon_id] = int(profile.get("magazine", 30)) if int(profile.get("magazine", 30)) >= 0 else -1
		_weapon_reserve[weapon_id] = int(profile.get("reserve", 0))
		_weapon_owned[weapon_id] = weapon_id in [primary_weapon_id, secondary_weapon_id] or (weapon_id == "knife" and has_knife)
	_current_weapon_id = primary_weapon_id if _weapon_is_owned(primary_weapon_id) else (secondary_weapon_id if _weapon_is_owned(secondary_weapon_id) else "knife")
	ammo_in_mag = int(_weapon_ammo.get(_current_weapon_id, 0))
	_equip_seconds = 0.0

func _tick_danger_memory(delta: float) -> void:
	var retained: Array[Dictionary] = []
	for event_variant in _danger_events:
		var event := event_variant.duplicate(true)
		event["remaining"] = float(event.get("remaining", 0.0)) - delta
		if float(event.get("remaining", 0.0)) > 0.0:
			retained.append(event)
	_danger_events = retained

func _tick_patrol(delta: float) -> void:
	if _route_points.is_empty():
		_stop(delta)
		return
	var destination := _route_points[_route_index]
	if actor.global_position.distance_to(destination) <= 1.0:
		_route_index += _route_direction
		if _route_index < 0 or _route_index >= _route_points.size():
			_route_direction *= -1
			_route_index = clampi(_route_index, 0, _route_points.size() - 1)
		destination = _route_points[_route_index]
	_move_toward(destination, delta)

func _move_toward(destination: Vector3, delta: float) -> void:
	var steering_target := _resolve_navigation_target(destination)
	var planar := steering_target - actor.global_position
	planar.y = 0.0
	if planar.length_squared() <= 0.01:
		_stop(delta)
		return
	var desired_direction := planar.normalized()
	_update_navigation_progress(delta, desired_direction)
	var direction := desired_direction
	if _recovery_seconds > 0.0:
		_recovery_seconds = maxf(0.0, _recovery_seconds - delta)
		direction = _choose_open_recovery_direction(_recovery_direction, desired_direction)
	elif actor.test_move(actor.global_transform, direction * 0.45):
		var left := direction.rotated(Vector3.UP, PI * 0.5)
		var right := direction.rotated(Vector3.UP, -PI * 0.5)
		if not actor.test_move(actor.global_transform, left * 0.45):
			direction = left
		elif not actor.test_move(actor.global_transform, right * 0.45):
			direction = right
	var precise := bool(_active_navigation_link.get("precise", false))
	var crouch := bool(_active_navigation_link.get("crouch", false))
	var movement_scale := 0.54 if crouch else (0.72 if precise else 1.0)
	actor.call("set_ai_crouching", crouch)
	_aim_at(actor.global_position + direction, delta, 0.18)
	actor.call("apply_ai_navigation", direction, move_speed * movement_scale, steering_target.y, delta)

func _stop(delta: float) -> void:
	if actor != null and actor.has_method("set_ai_crouching"):
		actor.call("set_ai_crouching", false)
	actor.velocity.x = move_toward(actor.velocity.x, 0.0, 22.0 * delta)
	actor.velocity.z = move_toward(actor.velocity.z, 0.0, 22.0 * delta)
	_last_progress_position = actor.global_position
	_no_progress_seconds = 0.0
	_recovery_seconds = 0.0

func _aim_at(target_position: Vector3, delta: float, duration: float) -> void:
	var direction := target_position - actor.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	actor.rotation.y = lerp_angle(actor.rotation.y, desired_yaw, clampf(delta / maxf(duration, 0.01), 0.0, 1.0))

func _resolve_navigation_target(destination: Vector3) -> Vector3:
	if _navigation.points.is_empty() or actor.global_position.distance_to(destination) <= 2.2:
		_active_navigation_link.clear()
		return destination
	var destination_changed := (
		not _navigation_destination.is_finite()
		or _navigation_destination.distance_to(destination) > 1.8
	)
	if destination_changed or _repath_seconds <= 0.0 or _navigation_path.is_empty():
		_navigation_destination = destination
		_navigation_path = _navigation.find_path(
			_navigation.nearest_index(actor.global_position),
			_navigation.nearest_index(destination),
			_danger_events
		)
		_navigation_path_index = 0
		_repath_seconds = 0.65
	while _navigation_path_index < _navigation_path.size():
		var point := _navigation.points[_navigation_path[_navigation_path_index]]
		var arrival_radius := 0.55 if bool(_active_navigation_link.get("precise", false)) else 1.05
		if actor.global_position.distance_to(point) > arrival_radius:
			if _navigation_path_index > 0:
				_active_navigation_link = _navigation.find_link(
					_navigation_path[_navigation_path_index - 1],
					_navigation_path[_navigation_path_index],
					_danger_events
				)
			return point
		_navigation_path_index += 1
	_active_navigation_link.clear()
	return destination

func _update_navigation_progress(delta: float, desired_direction: Vector3) -> void:
	var traveled := Vector2(
		actor.global_position.x - _last_progress_position.x,
		actor.global_position.z - _last_progress_position.z
	).length()
	if traveled >= 0.18:
		_last_progress_position = actor.global_position
		_no_progress_seconds = 0.0
		return
	_no_progress_seconds += delta
	if _no_progress_seconds < 0.75 or _recovery_seconds > 0.0:
		return
	_recovery_flip = not _recovery_flip
	var side_angle := PI * 0.5 if _recovery_flip else -PI * 0.5
	var lateral := desired_direction.rotated(Vector3.UP, side_angle)
	_recovery_direction = (-desired_direction + lateral * 0.65).normalized()
	_recovery_seconds = 0.68
	_stuck_recoveries += 1
	_no_progress_seconds = 0.0
	_last_progress_position = actor.global_position
	_navigation_path.clear()
	_navigation_path_index = 0
	_repath_seconds = 0.0

func _choose_open_recovery_direction(preferred: Vector3, desired_direction: Vector3) -> Vector3:
	var candidates := [
		preferred,
		-desired_direction,
		desired_direction.rotated(Vector3.UP, PI * 0.5),
		desired_direction.rotated(Vector3.UP, -PI * 0.5),
	]
	for candidate_variant in candidates:
		var candidate := candidate_variant as Vector3
		if not actor.test_move(actor.global_transform, candidate * 0.45):
			return candidate
	return preferred

func _nearest_route_index() -> int:
	if actor == null or _route_points.is_empty():
		return 0
	var best_index := 0
	var best_distance := INF
	for index in range(_route_points.size()):
		var distance := actor.global_position.distance_squared_to(_route_points[index])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _segment_blocked_by_smoke(from: Vector3, to: Vector3) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false
	for smoke in actor.get_tree().get_nodes_in_group("smoke_volumes"):
		if smoke is Node3D:
			var t := clampf(((smoke as Node3D).global_position - from).dot(segment) / length_squared, 0.0, 1.0)
			if (from + segment * t).distance_to((smoke as Node3D).global_position) <= 3.1:
				return true
	return false
