extends CharacterBody3D

const DamageModel = preload("res://scripts/combat/DamageModel.gd")

signal footstep_emitted(world_position: Vector3, surface: String, quiet: bool)
signal landed(world_position: Vector3, surface: String, strength: float)
signal player_died

@export var run_speed: float = 6.2
@export var quiet_walk_speed: float = 3.2
@export var crouch_speed: float = 2.2
@export var jump_velocity: float = 5.1
@export var crouch_jump_velocity: float = 5.55
@export var mouse_sensitivity: float = 0.0022
@export var acceleration: float = 44.0
@export var deceleration: float = 34.0
@export var counter_strafe_acceleration: float = 62.0
@export var ground_friction: float = 6.2
@export var stop_speed: float = 2.4
@export var air_acceleration: float = 7.0
@export var air_speed_cap: float = 6.5
@export var standing_height: float = 0.9
@export var crouching_collision_height: float = 1.2
@export var crouching_camera_height: float = 1.02
@export var crouch_transition_speed: float = 8.0
@export var max_step_height: float = 0.42
@export var floor_probe_distance: float = 0.9
@export var step_probe_distance: float = 0.55
@export var walk_bob_amplitude: float = 0.012
@export var walk_bob_frequency: float = 10.0
@export var landing_kick_distance: float = 0.028
@export var camera_recovery_speed: float = 10.0
@export var fall_damage_threshold: float = 10.0
@export var fall_damage_scale: float = 4.0
@export var ladder_climb_speed: float = 2.8
@export var ladder_lateral_speed: float = 1.65
@export var ladder_jump_push: float = 3.0
@export var shallow_water_speed_multiplier: float = 0.72
@export var deep_water_speed_multiplier: float = 0.52

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var environment_sensor: Area3D = $EnvironmentSensor

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var controls_enabled: bool = false
var movement_enabled: bool = false
var mouse_capture_enabled: bool = false
var _spawn_applied: bool = false
var _camera_pivot_origin: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0
var _landing_offset: float = 0.0
var is_crouching: bool = false
var _camera_stance_offset: float = 0.0
var _landing_accuracy_penalty: float = 0.0
var _footstep_distance: float = 0.0
var _tagging_multiplier: float = 1.0
var is_dead: bool = false
var _flash_intensity: float = 0.0
var _flash_seconds: float = 0.0
var _last_step_probe: Dictionary = {}
var current_ladder: Area3D = null
var current_water: Area3D = null
var is_on_ladder: bool = false
var is_in_water: bool = false
var is_submerged: bool = false
var _water_depth: float = 0.0
var _water_surface_y: float = -INF
var _ladder_detach_cooldown: float = 0.0

func _ready() -> void:
	collision_shape.shape = collision_shape.shape.duplicate()
	_camera_pivot_origin = camera_pivot.position
	_apply_user_settings(UserSettings.get_snapshot())
	if not UserSettings.settings_changed.is_connected(_apply_user_settings):
		UserSettings.settings_changed.connect(_apply_user_settings)
	floor_snap_length = 0.3
	max_slides = 8
	set_mouse_capture_enabled(false)
	_apply_spawn()

func _input(event: InputEvent) -> void:
	if not controls_enabled:
		return

	if event is InputEventMouseMotion and mouse_capture_enabled:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventMouseButton and event.pressed and mouse_capture_enabled and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	_ladder_detach_cooldown = maxf(0.0, _ladder_detach_cooldown - delta)
	_update_environment_state()
	_flash_seconds = maxf(0.0, _flash_seconds - delta)
	_flash_intensity = move_toward(_flash_intensity, 0.0, delta / maxf(_flash_seconds + 0.2, 0.2))
	if not _spawn_applied and GameState.player_spawn != Vector3.ZERO:
		_apply_spawn()

	if not movement_enabled:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		_update_camera_motion(delta, Vector3.ZERO)
		return

	var was_on_floor: bool = is_on_floor()
	_landing_accuracy_penalty = move_toward(_landing_accuracy_penalty, 0.0, delta * 2.8)
	_tagging_multiplier = move_toward(_tagging_multiplier, 1.0, delta * 1.9)
	if is_on_ladder:
		_handle_ladder_movement(delta)
		return
	if not is_on_floor():
		velocity.y -= gravity * resolve_water_gravity_multiplier() * delta
	if is_in_water and _water_depth >= 1.2:
		_apply_deep_water_vertical_control(delta)

	_update_crouch(Input.is_action_pressed("crouch"), delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = crouch_jump_velocity if is_crouching else jump_velocity

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir: Vector3 = get_world_move_direction(input_vector)

	var speed := resolve_move_speed(Input.is_action_pressed("walk")) * get_equipped_movement_multiplier() * resolve_water_speed_multiplier()
	var horizontal := simulate_tactical_horizontal_velocity(
		Vector3(velocity.x, 0.0, velocity.z),
		move_dir,
		speed,
		is_on_floor(),
		delta
	)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var step_motion: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta
	var position_before_move := global_position
	var impact_speed := absf(velocity.y)
	if velocity.y <= 0.1 and step_motion.length_squared() > 0.000001:
		_pre_step_up(step_motion)
		position_before_move = global_position
	move_and_slide()

	if (was_on_floor or is_on_floor()) and step_motion.length() > 0.001:
		_try_step_up(position_before_move, step_motion)

	if not is_on_floor() and velocity.y <= 0.0:
		_snap_to_floor()

	if not was_on_floor and is_on_floor():
		_landing_offset = landing_kick_distance
		_landing_accuracy_penalty = 1.0
		_apply_fall_damage(impact_speed)
		landed.emit(global_position, _detect_floor_surface(), clampf(impact_speed / 8.0, 0.35, 1.0))
	_update_footsteps(delta, move_dir)
	_update_camera_motion(delta, move_dir)

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	movement_enabled = enabled
	if not controls_enabled:
		velocity.x = 0.0
		velocity.z = 0.0

func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled and controls_enabled and not is_dead
	if not movement_enabled:
		velocity.x = 0.0
		velocity.z = 0.0

func set_mouse_capture_enabled(enabled: bool) -> void:
	mouse_capture_enabled = enabled
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func reset_to_spawn() -> void:
	_apply_spawn()

func get_camera_node() -> Camera3D:
	return camera

func get_world_move_direction(input_vector: Vector2) -> Vector3:
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var world_direction: Vector3 = global_transform.basis * local_direction
	world_direction.y = 0.0
	return world_direction.normalized()

func get_movement_response_acceleration(move_dir: Vector3, grounded: bool) -> float:
	if not grounded:
		return air_acceleration
	if move_dir == Vector3.ZERO:
		return deceleration
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > 0.01 and horizontal_velocity.normalized().dot(move_dir) < -0.15:
		return counter_strafe_acceleration
	return acceleration

func simulate_tactical_horizontal_velocity(
	current_velocity: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	grounded: bool,
	delta: float
) -> Vector3:
	var horizontal := Vector3(current_velocity.x, 0.0, current_velocity.z)
	if grounded:
		horizontal = _apply_ground_friction(horizontal, delta)
	var normalized_wish := wish_direction.normalized() if wish_direction.length_squared() > 0.0001 else Vector3.ZERO
	if normalized_wish == Vector3.ZERO:
		return horizontal
	var resolved_wish_speed := minf(wish_speed, air_speed_cap) if not grounded else wish_speed
	var accel := get_movement_response_acceleration(normalized_wish, grounded)
	var current_along_wish := horizontal.dot(normalized_wish)
	var add_speed := resolved_wish_speed - current_along_wish
	if add_speed <= 0.0:
		return horizontal
	var accel_speed := minf(add_speed, accel * delta)
	horizontal += normalized_wish * accel_speed
	if not grounded and horizontal.length() > air_speed_cap:
		horizontal = horizontal.normalized() * air_speed_cap
	return horizontal

func _apply_ground_friction(horizontal: Vector3, delta: float) -> Vector3:
	var current_speed := horizontal.length()
	if current_speed <= 0.001:
		return Vector3.ZERO
	var control := maxf(current_speed, stop_speed)
	var next_speed := maxf(0.0, current_speed - control * ground_friction * delta)
	return horizontal * (next_speed / current_speed)

func get_equipped_movement_multiplier() -> float:
	match GameState.current_weapon_slot:
		0:
			return 0.94
		1:
			return 1.0
		2:
			return 1.04
		_:
			return 1.0

func resolve_move_speed(quiet_walk_held: bool) -> float:
	if is_crouching:
		return crouch_speed
	return (quiet_walk_speed if quiet_walk_held else run_speed) * _tagging_multiplier

func resolve_water_speed_multiplier() -> float:
	if not is_in_water:
		return 1.0
	return deep_water_speed_multiplier if _water_depth >= 1.2 else shallow_water_speed_multiplier

func resolve_water_gravity_multiplier() -> float:
	if not is_in_water:
		return 1.0
	return 0.16 if _water_depth >= 1.2 else 0.48

func get_environment_state() -> Dictionary:
	return {
		"on_ladder": is_on_ladder,
		"in_water": is_in_water,
		"submerged": is_submerged,
		"water_depth": _water_depth,
		"water_surface_y": _water_surface_y,
	}

func get_accuracy_state() -> Dictionary:
	return {
		"speed": Vector2(velocity.x, velocity.z).length(),
		"crouching": is_crouching,
		"airborne": not is_on_floor(),
		"landing_penalty": _landing_accuracy_penalty,
	}

func apply_hitscan_damage(amount: int, hit_position: Vector3 = Vector3.ZERO, armor_penetration: float = 1.0, penetrated: bool = false) -> Dictionary:
	if is_dead:
		return {"hit": false, "killed": false}
	var resolved_position := global_position if hit_position == Vector3.ZERO else hit_position
	var hit_group := DamageModel.resolve_hit_group(to_local(resolved_position))
	var resolved := DamageModel.resolve_damage(amount, hit_group, GameState.player_armor, GameState.player_helmet, armor_penetration)
	var health_damage := int(resolved.damage)
	var armor_damage := int(resolved.armor_damage)
	GameState.player_armor = maxi(0, GameState.player_armor - armor_damage)
	GameState.player_health = maxi(0, GameState.player_health - health_damage)
	_tagging_multiplier = minf(_tagging_multiplier, 0.48)
	var killed := GameState.player_health == 0
	if killed:
		is_dead = true
		controls_enabled = false
		movement_enabled = false
		GameState.friendly_alive = maxi(0, GameState.friendly_alive - 1)
		player_died.emit()
	GameState.notify_player_vitals_changed()
	return {
		"hit": true,
		"killed": killed,
		"damage": health_damage,
		"armor_damage": armor_damage,
		"hit_group": hit_group,
		"headshot": bool(resolved.headshot),
		"armored": bool(resolved.armored),
		"penetrated": penetrated,
		"remaining_health": GameState.player_health,
		"remaining_armor": GameState.player_armor,
	}

func calculate_fall_damage(impact_speed: float) -> int:
	if impact_speed <= fall_damage_threshold:
		return 0
	return maxi(1, int(round((impact_speed - fall_damage_threshold) * fall_damage_scale)))

func apply_explosive_damage(amount: int, armor_ratio: float = 0.5) -> Dictionary:
	if is_dead or amount <= 0:
		return {"hit": false, "killed": is_dead}
	var health_damage := amount
	var armor_damage := 0
	if GameState.player_armor > 0:
		health_damage = maxi(1, int(round(float(amount) * clampf(armor_ratio, 0.0, 1.0))))
		armor_damage = mini(GameState.player_armor, maxi(1, int(round(float(amount - health_damage) * 0.5))))
		GameState.player_armor -= armor_damage
	GameState.player_health = maxi(0, GameState.player_health - health_damage)
	var killed := GameState.player_health == 0
	if killed:
		is_dead = true
		controls_enabled = false
		movement_enabled = false
		GameState.friendly_alive = maxi(0, GameState.friendly_alive - 1)
		player_died.emit()
	GameState.notify_player_vitals_changed()
	return {"hit": true, "damage": health_damage, "armor_damage": armor_damage, "killed": killed, "remaining_health": GameState.player_health}

func apply_flash_effect(intensity: float, duration: float) -> void:
	_flash_intensity = maxf(_flash_intensity, clampf(intensity, 0.0, 1.0))
	_flash_seconds = maxf(_flash_seconds, duration)

func get_flash_intensity() -> float:
	return _flash_intensity

func _apply_fall_damage(impact_speed: float) -> void:
	var damage := calculate_fall_damage(impact_speed)
	if damage <= 0 or is_dead:
		return
	GameState.player_health = maxi(0, GameState.player_health - damage)
	if GameState.player_health == 0:
		is_dead = true
		controls_enabled = false
		movement_enabled = false
		GameState.friendly_alive = maxi(0, GameState.friendly_alive - 1)
		player_died.emit()
	GameState.notify_player_vitals_changed()

func apply_recoil_kick(pitch_radians: float, yaw_radians: float) -> void:
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x - pitch_radians,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)
	rotate_y(-yaw_radians)

func get_debug_snapshot(menu_open: bool) -> Dictionary:
	return {
		"speed": Vector2(velocity.x, velocity.z).length(),
		"grounded": is_on_floor(),
		"crouching": is_crouching,
		"position": global_position,
		"mode": "\u83dc\u5355" if menu_open else "\u6e38\u620f\u4e2d",
		"window": "\u5168\u5c4f" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "\u7a97\u53e3",
		"mouse": "\u9501\u5b9a" if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else "\u81ea\u7531"
	}

func get_movement_profile() -> Dictionary:
	return {
		"walk_speed": quiet_walk_speed,
		"run_speed": run_speed,
		"quiet_walk_speed": quiet_walk_speed,
		"jump_velocity": jump_velocity,
		"crouch_jump_velocity": crouch_jump_velocity,
		"standing_height": standing_height * 2.0,
		"crouching_height": crouching_collision_height,
		"double_jump": false,
		"mantle": false,
		"ladder_climb_speed": ladder_climb_speed,
		"shallow_water_speed_multiplier": shallow_water_speed_multiplier,
		"deep_water_speed_multiplier": deep_water_speed_multiplier,
	}

func _apply_spawn() -> void:
	if GameState.player_spawn == Vector3.ZERO:
		return
	global_position = GameState.player_spawn
	rotation.y = GameState.player_spawn_yaw_radians
	camera_pivot.rotation.x = 0.0
	velocity = Vector3.ZERO
	_bob_phase = 0.0
	_landing_offset = 0.0
	_landing_accuracy_penalty = 0.0
	_footstep_distance = 0.0
	is_crouching = false
	is_dead = false
	_tagging_multiplier = 1.0
	current_ladder = null
	current_water = null
	is_on_ladder = false
	is_in_water = false
	is_submerged = false
	_water_depth = 0.0
	_water_surface_y = -INF
	_ladder_detach_cooldown = 0.0
	_camera_stance_offset = 0.0
	_set_collision_height(standing_height * 2.0)
	if camera_pivot != null:
		camera_pivot.position = _camera_pivot_origin
	_spawn_applied = true
	reset_physics_interpolation()

func _try_step_up(position_before_move: Vector3, step_motion: Vector3) -> void:
	var actual_motion := Vector2(global_position.x - position_before_move.x, global_position.z - position_before_move.z).length()
	if actual_motion >= step_motion.length() * 0.98:
		return
	var blocked_position := global_position
	var clearance_lift := max_step_height + 0.08
	global_position = position_before_move + Vector3.UP * clearance_lift
	if move_and_collide(step_motion) != null:
		global_position = blocked_position
		return
	var downward_motion := Vector3.DOWN * (clearance_lift + 0.02)
	var floor_collision := move_and_collide(downward_motion)
	if floor_collision == null or not _is_walkable_normal(floor_collision.get_normal()):
		global_position = blocked_position
		return
	if global_position.y - position_before_move.y > max_step_height + 0.01:
		global_position = blocked_position
		return
	apply_floor_snap()

func _pre_step_up(step_motion: Vector3) -> void:
	var direction := step_motion.normalized()
	var foot_y := global_position.y - standing_height
	var probe_origin := global_position + direction * step_probe_distance + Vector3.UP * (max_step_height + 0.08)
	var probe_end := Vector3(probe_origin.x, foot_y - 0.04, probe_origin.z)
	var floor_hit := _raycast(probe_origin, probe_end)
	_last_step_probe = {"origin": probe_origin, "end": probe_end, "hit": not floor_hit.is_empty(), "foot_y": foot_y}
	if floor_hit.is_empty() or not _is_walkable_normal(floor_hit.normal):
		return
	var step_height := float(floor_hit.position.y) - foot_y
	_last_step_probe["step_height"] = step_height
	if step_height <= 0.025 or step_height > max_step_height:
		return
	var lift := Vector3.UP * (step_height + 0.01)
	global_position += lift
	_last_step_probe["lifted"] = true
	apply_floor_snap()

func _snap_to_floor() -> void:
	var from: Vector3 = global_position + Vector3.UP * 0.1
	var to: Vector3 = from + Vector3.DOWN * (standing_height + floor_probe_distance)
	var hit: Dictionary = _raycast(from, to)
	if hit.is_empty():
		return
	if not _is_walkable_normal(hit.normal):
		return

	var target_y: float = float(hit.position.y) + standing_height
	if global_position.y >= target_y and global_position.y - target_y <= 0.45:
		global_position.y = target_y
		if velocity.y < 0.0:
			velocity.y = 0.0

func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func _is_walkable_normal(normal: Vector3) -> bool:
	return normal.dot(Vector3.UP) >= cos(floor_max_angle)

func _update_crouch(wants_crouch: bool, delta: float) -> void:
	if wants_crouch:
		is_crouching = true
	elif is_crouching and _has_standing_clearance():
		is_crouching = false
	var target_height := crouching_collision_height if is_crouching else standing_height * 2.0
	_set_collision_height(target_height)
	var crouch_pivot_y := crouching_camera_height - standing_height
	var target_offset := crouch_pivot_y - _camera_pivot_origin.y if is_crouching else 0.0
	_camera_stance_offset = move_toward(_camera_stance_offset, target_offset, crouch_transition_speed * delta)

func _set_collision_height(total_height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.height = total_height
	collision_shape.position.y = -(standing_height * 2.0 - total_height) * 0.5

func _has_standing_clearance() -> bool:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return true
	var standing_capsule := CapsuleShape3D.new()
	standing_capsule.radius = capsule.radius
	standing_capsule.height = standing_height * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_capsule
	query.transform = Transform3D(global_transform.basis, global_position + Vector3.UP * 0.03)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _update_camera_motion(delta: float, move_dir: Vector3) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var bob_weight := clampf(horizontal_speed / maxf(run_speed, 0.01), 0.0, 1.25) if is_on_floor() else 0.0
	if move_dir != Vector3.ZERO and bob_weight > 0.05:
		_bob_phase += delta * walk_bob_frequency * bob_weight
	else:
		_bob_phase = move_toward(_bob_phase, 0.0, delta * walk_bob_frequency)
	_landing_offset = move_toward(_landing_offset, 0.0, delta * camera_recovery_speed * landing_kick_distance)
	var bob_y := sin(_bob_phase * 2.0) * walk_bob_amplitude * bob_weight
	var bob_x := cos(_bob_phase) * walk_bob_amplitude * 0.55 * bob_weight
	camera_pivot.position = _camera_pivot_origin + Vector3(bob_x, bob_y - _landing_offset + _camera_stance_offset, 0.0)

func _update_footsteps(delta: float, move_dir: Vector3) -> void:
	if (not is_on_floor() and not is_in_water) or move_dir == Vector3.ZERO:
		_footstep_distance = 0.0
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.35:
		return
	_footstep_distance += horizontal_speed * delta
	var quiet := is_crouching or Input.is_action_pressed("walk")
	var stride := 2.35 if quiet else 1.75
	if _footstep_distance >= stride:
		_footstep_distance = fmod(_footstep_distance, stride)
		footstep_emitted.emit(global_position, _detect_floor_surface(), quiet)

func _detect_floor_surface() -> String:
	if is_in_water:
		return "water"
	var hit := _raycast(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 1.1)
	if hit.is_empty():
		return "concrete"
	var collider: Object = hit.get("collider")
	var collider_name := String(collider.get("name") if collider != null else "").to_lower()
	if collider_name.contains("metal") or collider_name.contains("catwalk") or collider_name.contains("stair"):
		return "metal"
	if collider_name.contains("wood") or collider_name.contains("crate"):
		return "wood"
	return "concrete"

func _update_environment_state() -> void:
	var next_ladder: Area3D = null
	var next_water: Area3D = null
	if is_instance_valid(environment_sensor):
		for area in environment_sensor.get_overlapping_areas():
			var environment_type := String(area.get_meta("environment_type", ""))
			if environment_type == "ladder" and next_ladder == null:
				next_ladder = area
			elif environment_type == "water" and next_water == null:
				next_water = area
	current_water = next_water
	is_in_water = current_water != null
	if is_in_water:
		_water_depth = float(current_water.get_meta("water_depth", 0.0))
		_water_surface_y = float(current_water.get_meta("water_surface_y", global_position.y))
		is_submerged = camera.global_position.y < _water_surface_y - 0.05
	else:
		_water_depth = 0.0
		_water_surface_y = -INF
		is_submerged = false
	if _ladder_detach_cooldown <= 0.0:
		current_ladder = next_ladder
	else:
		current_ladder = null
	is_on_ladder = current_ladder != null

func _handle_ladder_movement(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var normal := current_ladder.get_meta("ladder_normal", Vector3.FORWARD) as Vector3
	var tangent := Vector3(-normal.z, 0.0, normal.x).normalized()
	var vertical_input := -input_vector.y
	velocity = tangent * input_vector.x * ladder_lateral_speed
	velocity.y = vertical_input * ladder_climb_speed
	if Input.is_action_just_pressed("jump"):
		detach_from_ladder(normal)
		move_and_slide()
		_update_camera_motion(delta, Vector3.ZERO)
		return
	var ladder_top := float(current_ladder.get_meta("ladder_top", global_position.y + 1.0))
	if vertical_input > 0.0 and global_position.y >= ladder_top - standing_height * 0.55:
		var exit_direction := current_ladder.get_meta("ladder_exit_direction", -normal) as Vector3
		global_position += exit_direction.normalized() * 0.72 + Vector3.UP * 0.12
		velocity = exit_direction.normalized() * 1.8
		_ladder_detach_cooldown = 0.28
		current_ladder = null
		is_on_ladder = false
		reset_physics_interpolation()
	else:
		move_and_slide()
	_update_footsteps(delta, Vector3(tangent.x * input_vector.x, 0.0, tangent.z * input_vector.x))
	_update_camera_motion(delta, Vector3.ZERO)

func detach_from_ladder(outward_normal: Vector3 = Vector3.ZERO) -> void:
	if current_ladder == null and not is_on_ladder:
		return
	var normal := outward_normal
	if normal == Vector3.ZERO and current_ladder != null:
		normal = current_ladder.get_meta("ladder_normal", Vector3.FORWARD) as Vector3
	velocity = normal.normalized() * ladder_jump_push + Vector3.UP * 3.6
	_ladder_detach_cooldown = 0.32
	current_ladder = null
	is_on_ladder = false

func _apply_deep_water_vertical_control(delta: float) -> void:
	var vertical_input := 0.0
	if Input.is_action_pressed("jump"):
		vertical_input += 1.0
	if Input.is_action_pressed("crouch"):
		vertical_input -= 1.0
	var target_vertical := vertical_input * 2.4
	if is_zero_approx(vertical_input) and global_position.y < _water_surface_y - 0.65:
		target_vertical = 0.55
	velocity.y = move_toward(velocity.y, target_vertical, delta * 5.0)

func _apply_user_settings(snapshot: Dictionary) -> void:
	mouse_sensitivity = 0.0022 * float(snapshot.get("mouse_sensitivity_multiplier", 1.0))
