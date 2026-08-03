extends CharacterBody3D

const DamageModel = preload("res://scripts/combat/DamageModel.gd")
const WorldWeaponPickup = preload("res://scripts/combat/WorldWeaponPickup.gd")

signal actor_killed(actor_name: String, team: String)
signal ai_shot(result: Dictionary, world_position: Vector3)
signal ai_footstep(world_position: Vector3, surface: String, quiet: bool)
signal ai_spot(world_position: Vector3, enemy_team: String)
signal ai_damaged(world_position: Vector3, source_team: String)

@export var display_name: String = "战术单位"
@export_enum("T", "CT") var team: String = "CT"
@export var max_health: int = 100
@export var max_armor: int = 0
@export var has_helmet: bool = false
@export var equipped_weapon_id: String = "rifle"

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var head_mesh: MeshInstance3D = $HeadMesh
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh
@onready var armor_vest: MeshInstance3D = $ArmorVest
@onready var helmet_mesh: MeshInstance3D = $HelmetMesh
@onready var actor_visual: Node3D = $ActorVisual
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var environment_sensor: Area3D = $EnvironmentSensor
@onready var bot_brain: Node = $TacticalBotBrain

var current_health: int = 100
var current_armor: int = 0
var is_dead: bool = false
var ai_crouching: bool = false
var has_defuse_kit: bool = false
var spawn_position: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_ladder: Area3D
var _current_water: Area3D
var _water_depth: float = 0.0
var _footstep_distance: float = 0.0
var _body_mesh_y: float = 0.0
var _head_mesh_y: float = 0.0
var _weapon_mesh_y: float = 0.0
var _presentation_time: float = 0.0
var _hit_flash_time: float = 0.0
var _visual_drop: float = 0.0
var _actor_visual_y: float = 0.0
var _active_visual_animation: StringName = &""
var _imported_animation_player: AnimationPlayer
var _imported_animation_names: Dictionary = {}

func _ready() -> void:
	add_to_group("combat_actors")
	add_to_group("target_dummies")
	spawn_position = global_position
	spawn_yaw = rotation.y
	current_health = max_health
	current_armor = max_armor
	collision_shape.shape = collision_shape.shape.duplicate()
	_body_mesh_y = body_mesh.position.y
	_head_mesh_y = head_mesh.position.y
	_weapon_mesh_y = weapon_mesh.position.y
	_actor_visual_y = actor_visual.position.y
	_discover_imported_animations()
	_create_visual_animations()
	bot_brain.call("setup", self)
	_apply_team_visual()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_environment_state()
	var position_before := global_position
	if bot_brain != null:
		bot_brain.call("tick", delta)
	if _current_ladder == null and not is_on_floor():
		var gravity_scale := 0.18 if _water_depth >= 1.2 else (0.48 if _current_water != null else 1.0)
		velocity.y -= _gravity * gravity_scale * delta
	else:
		if _current_ladder == null:
			velocity.y = 0.0
	move_and_slide()
	_update_ai_footsteps(position_before)
	_update_presentation(delta)

func configure_from_record(record: Dictionary) -> void:
	display_name = String(record.get("name", display_name))
	name = display_name.replace(" ", "_")
	team = _resolve_team(String(record.get("team", team)))
	max_health = clampi(int(record.get("health", max_health)), 1, 500)
	max_armor = clampi(int(record.get("armor", max_armor)), 0, 100)
	has_helmet = bool(record.get("helmet", has_helmet))
	equipped_weapon_id = String(record.get("weapon", equipped_weapon_id))
	has_defuse_kit = bool(record.get("defuseKit", has_defuse_kit))
	rotation.y = deg_to_rad(float(record.get("yawDegrees", rad_to_deg(rotation.y))))
	spawn_position = global_position
	spawn_yaw = rotation.y
	current_health = max_health
	current_armor = max_armor
	is_dead = false
	bot_brain.call("configure", record)
	_apply_team_visual()

func apply_hitscan_damage(amount: int, hit_position: Vector3 = Vector3.ZERO, armor_penetration: float = 1.0, penetrated: bool = false, source_team: String = "", source_position: Vector3 = Vector3.INF) -> Dictionary:
	if is_dead:
		return {"hit": false, "killed": false, "target_team": team}
	var resolved_position := global_position if hit_position == Vector3.ZERO else hit_position
	var local_hit := to_local(resolved_position)
	if ai_crouching:
		local_hit.y += 0.32
	var hit_group := DamageModel.resolve_hit_group(local_hit)
	var resolved := DamageModel.resolve_damage(amount, hit_group, current_armor, has_helmet, armor_penetration)
	var health_damage := int(resolved.damage)
	var armor_damage := int(resolved.armor_damage)
	current_armor = maxi(0, current_armor - armor_damage)
	current_health = maxi(0, current_health - health_damage)
	if bot_brain != null:
		bot_brain.call("notify_damage", resolved_position, source_team, source_position)
	ai_damaged.emit(resolved_position, source_team)
	var killed := current_health == 0
	if killed:
		_drop_ai_weapon()
		is_dead = true
		collision_layer = 0
		collision_mask = 0
		collision_shape.set_deferred("disabled", true)
		_material.albedo_color = Color(0.16, 0.17, 0.18)
		_set_visual_animation(&"death")
		actor_killed.emit(display_name, team)
		_play_death_then_release()
	else:
		_hit_flash_time = 0.10
		_material.albedo_color = Color(1.0, 0.72, 0.22)
	return {
		"hit": true, "killed": killed, "target_name": display_name, "target_team": team,
		"hit_group": hit_group, "headshot": bool(resolved.headshot), "armored": bool(resolved.armored),
		"helmet": has_helmet, "penetrated": penetrated, "damage": health_damage,
		"armor_damage": armor_damage, "remaining_armor": current_armor,
		"remaining_health": current_health, "position": resolved_position,
	}

func get_combat_snapshot() -> Dictionary:
	var snapshot := {
		"name": display_name, "team": team, "alive": not is_dead,
		"health": current_health, "armor": current_armor, "helmet": has_helmet,
		"weapon": equipped_weapon_id, "x": global_position.x, "y": global_position.y,
		"z": global_position.z, "yaw": rotation.y, "crouching": ai_crouching,
		"defuse_kit": has_defuse_kit,
	}
	if bot_brain != null:
		snapshot["ai"] = bot_brain.call("get_snapshot")
		snapshot["objective"] = bot_brain.call("get_objective_snapshot")
	return snapshot

func reset_actor() -> void:
	global_position = spawn_position
	rotation.y = spawn_yaw
	velocity = Vector3.ZERO
	current_health = max_health
	current_armor = max_armor
	is_dead = false
	set_ai_crouching(false)
	collision_layer = 1
	collision_mask = 1
	collision_shape.disabled = false
	_footstep_distance = 0.0
	_presentation_time = 0.0
	_hit_flash_time = 0.0
	_active_visual_animation = &""
	bot_brain.call("reset_runtime")
	_apply_team_visual()

func _drop_ai_weapon() -> void:
	if bot_brain == null or get_tree() == null or get_tree().current_scene == null:
		return
	var record := bot_brain.call("get_weapon_pickup_record") as Dictionary
	if record.is_empty():
		return
	var pickup := WorldWeaponPickup.new()
	get_tree().current_scene.add_child(pickup)
	pickup.configure(record, global_position)

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * (0.30 if ai_crouching else 0.62)

func notify_ai_sound(world_position: Vector3, audible_radius: float, source_team: String) -> bool:
	return bool(bot_brain.call("notify_sound", world_position, audible_radius, source_team))

func record_ai_dynamic_danger(world_position: Vector3, intensity: float = 0.7) -> void:
	bot_brain.call("record_dynamic_danger", world_position, intensity)

func set_ai_c4_device(device: Node3D) -> void:
	bot_brain.call("set_c4_device", device)

func set_ai_defuse_kit(has_kit: bool) -> void:
	bot_brain.call("set_defuse_kit", has_kit)

func set_ai_combat_enabled(enabled_combat: bool) -> void:
	bot_brain.call("set_ai_combat_enabled", enabled_combat)

func notify_ai_teammate_report(world_position: Vector3, enemy_team: String) -> void:
	bot_brain.call("notify_teammate_report", world_position, enemy_team)

func emit_ai_spot(world_position: Vector3, enemy_team: String) -> void:
	ai_spot.emit(world_position, enemy_team)

func emit_ai_shot(result: Dictionary, world_position: Vector3) -> void:
	ai_shot.emit(result, world_position)

func apply_ai_navigation(direction: Vector3, speed: float, target_y: float, delta: float) -> void:
	if _current_ladder != null:
		var ladder_normal := _current_ladder.get_meta("ladder_normal", Vector3.FORWARD) as Vector3
		var tangent := Vector3(-ladder_normal.z, 0.0, ladder_normal.x).normalized()
		velocity = tangent * direction.dot(tangent) * 1.4
		velocity.y = signf(target_y - global_position.y) * 2.7
		var ladder_top := float(_current_ladder.get_meta("ladder_top", global_position.y + 1.0))
		if target_y > global_position.y and global_position.y >= ladder_top - 0.5:
			var exit_direction := _current_ladder.get_meta("ladder_exit_direction", -ladder_normal) as Vector3
			global_position += exit_direction.normalized() * 0.72 + Vector3.UP * 0.12
			_current_ladder = null
		return
		return
	var speed_multiplier := 0.52 if _water_depth >= 1.2 else (0.72 if _current_water != null else 1.0)
	var target_velocity := direction * speed * speed_multiplier
	velocity.x = move_toward(velocity.x, target_velocity.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, 18.0 * delta)
	if _water_depth >= 1.2 and global_position.y < float(_current_water.get_meta("water_surface_y", global_position.y)) - 0.7:
		velocity.y = move_toward(velocity.y, 0.45, 4.0 * delta)

func set_ai_crouching(wants_crouch: bool) -> bool:
	if not wants_crouch and ai_crouching and not _has_ai_standing_clearance():
		return false
	ai_crouching = wants_crouch
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = 1.2 if ai_crouching else 1.8
	collision_shape.position.y = -0.30 if ai_crouching else 0.0
	_visual_drop = -0.32 if ai_crouching else 0.0
	body_mesh.position.y = _body_mesh_y + _visual_drop
	head_mesh.position.y = _head_mesh_y + _visual_drop
	weapon_mesh.position.y = _weapon_mesh_y + _visual_drop
	actor_visual.position.y = _actor_visual_y + _visual_drop
	return true

func get_ai_environment_snapshot() -> Dictionary:
	return {
		"on_ladder": _current_ladder != null,
		"in_water": _current_water != null,
		"water_depth": _water_depth,
		"speed_multiplier": 0.52 if _water_depth >= 1.2 else (0.72 if _current_water != null else 1.0),
	}

func _resolve_team(value: String) -> String:
	if value.to_lower() == "friendly":
		return GameState.player_team
	if value.to_lower() == "enemy":
		return "CT" if GameState.player_team == "T" else "T"
	return "CT" if value.to_upper() == "CT" else "T"

func _apply_team_visual() -> void:
	if not is_instance_valid(body_mesh):
		return
	_material.albedo_color = Color(0.20, 0.48, 0.88) if team == "CT" else Color(0.86, 0.43, 0.16)
	_material.roughness = 0.78
	body_mesh.material_override = _material
	head_mesh.material_override = _material
	weapon_mesh.material_override = _material
	armor_vest.material_override = _material
	for limb_path in ["LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		var limb := get_node(limb_path) as MeshInstance3D
		limb.material_override = _material
	helmet_mesh.material_override = _material
	# Legacy primitives remain collision-era fallbacks only; the GLB owns presentation.
	helmet_mesh.visible = false
	for part_name in ["TeamChestMarker", "TeamPatch_L", "TeamPatch_R", "VestPouch_L", "VestPouch_R"]:
		var part := actor_visual.find_child(part_name, true, false) as MeshInstance3D
		if part != null:
			part.material_override = _material
	var model_helmet := actor_visual.find_child("Helmet_LowProfile", true, false) as Node3D
	if model_helmet != null:
		model_helmet.visible = has_helmet

func _update_presentation(delta: float) -> void:
	_presentation_time += delta
	_hit_flash_time = maxf(0.0, _hit_flash_time - delta)
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / 4.8, 0.0, 1.0)
	var bob := sin(_presentation_time * lerpf(2.2, 10.5, speed_ratio)) * (0.014 + speed_ratio * 0.026)
	body_mesh.position.y = _body_mesh_y + _visual_drop + bob
	head_mesh.position.y = _head_mesh_y + _visual_drop + bob * 0.65
	weapon_mesh.position.y = _weapon_mesh_y + _visual_drop + bob * 0.75
	weapon_mesh.rotation.z = 0.18 + sin(_presentation_time * 8.0) * speed_ratio * 0.07
	var next_animation: StringName = &"idle"
	if _hit_flash_time > 0.0:
		next_animation = &"hit"
	elif ai_crouching:
		next_animation = &"crouch"
	elif speed_ratio > 0.12:
		next_animation = &"run"
	_set_visual_animation(next_animation)
	if _hit_flash_time > 0.0:
		_material.albedo_color = Color(1.0, 0.72, 0.22)
	elif _material.albedo_color != (Color(0.20, 0.48, 0.88) if team == "CT" else Color(0.86, 0.43, 0.16)):
		_apply_team_visual()

func _create_visual_animations() -> void:
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", _make_visual_animation(1.2, true, {
		"ActorVisual:position": [[0.0, Vector3(0.0, _actor_visual_y, 0.0)], [0.6, Vector3(0.0, _actor_visual_y + 0.015, 0.0)], [1.2, Vector3(0.0, _actor_visual_y, 0.0)]],
	}))
	library.add_animation(&"run", _make_visual_animation(0.52, true, {
		"ActorVisual:position": [[0.0, Vector3(0.0, _actor_visual_y, 0.0)], [0.13, Vector3(0.0, _actor_visual_y + 0.035, 0.0)], [0.26, Vector3(0.0, _actor_visual_y, 0.0)], [0.39, Vector3(0.0, _actor_visual_y + 0.035, 0.0)], [0.52, Vector3(0.0, _actor_visual_y, 0.0)]],
	}))
	library.add_animation(&"crouch", _make_visual_animation(0.8, true, {
		"ActorVisual:position": [[0.0, Vector3(0.0, _actor_visual_y - 0.28, 0.02)], [0.4, Vector3(0.0, _actor_visual_y - 0.265, 0.02)], [0.8, Vector3(0.0, _actor_visual_y - 0.28, 0.02)]],
	}))
	library.add_animation(&"hit", _make_visual_animation(0.22, false, {
		"ActorVisual:rotation": [[0.0, Vector3.ZERO], [0.08, Vector3(-0.08, 0.0, 0.08)], [0.22, Vector3.ZERO]],
	}))
	library.add_animation(&"death", _make_visual_animation(0.78, false, {
		"ActorVisual:position": [[0.0, Vector3(0.0, _actor_visual_y, 0.0)], [0.78, Vector3(0.0, _actor_visual_y - 0.35, 0.20)]],
		"ActorVisual:rotation": [[0.0, Vector3.ZERO], [0.78, Vector3(-1.30, 0.0, 0.18)]],
	}))
	animation_player.add_animation_library(&"tactical", library)

func _discover_imported_animations() -> void:
	_imported_animation_player = null
	_imported_animation_names.clear()
	for candidate in actor_visual.find_children("*", "AnimationPlayer", true, false):
		var player := candidate as AnimationPlayer
		if player == null:
			continue
		for imported_name in player.get_animation_list():
			var normalized := String(imported_name).to_lower()
			for expected in [&"idle", &"run", &"crouch", &"hit", &"death"]:
				if normalized == String(expected) or normalized.ends_with("/" + String(expected)) or normalized.ends_with("|" + String(expected)):
					_imported_animation_player = player
					_imported_animation_names[expected] = imported_name

func get_visual_animation_snapshot() -> Dictionary:
	return {
		"active": _active_visual_animation,
		"uses_imported": _imported_animation_player != null and _imported_animation_names.has(_active_visual_animation),
		"imported_names": _imported_animation_names.keys(),
		"imported_current": _imported_animation_player.current_animation if _imported_animation_player != null else &"",
		"fallback_current": animation_player.current_animation,
	}

func _make_visual_animation(length: float, loop: bool, tracks: Dictionary) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for path_variant in tracks:
		var track_index := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track_index, NodePath(String(path_variant)))
		for key in tracks[path_variant] as Array:
			animation.track_insert_key(track_index, float(key[0]), key[1])
	return animation

func _set_visual_animation(next_animation: StringName) -> void:
	if _active_visual_animation == next_animation:
		return
	_active_visual_animation = next_animation
	if _imported_animation_player != null and _imported_animation_names.has(next_animation):
		_imported_animation_player.play(_imported_animation_names[next_animation])
		animation_player.stop()
	else:
		animation_player.play(&"tactical/" + next_animation)

func _play_death_then_release() -> void:
	if get_tree() == null:
		queue_free()
		return
	await get_tree().create_timer(0.80).timeout
	queue_free()

func _update_environment_state() -> void:
	_current_ladder = null
	_current_water = null
	for area in environment_sensor.get_overlapping_areas():
		var environment_type := String(area.get_meta("environment_type", ""))
		if environment_type == "ladder" and _current_ladder == null:
			_current_ladder = area
		elif environment_type == "water" and _current_water == null:
			_current_water = area
	_water_depth = float(_current_water.get_meta("water_depth", 0.0)) if _current_water != null else 0.0

func _update_ai_footsteps(position_before: Vector3) -> void:
	if not is_on_floor() and _current_water == null:
		_footstep_distance = 0.0
		return
	var traveled := Vector2(global_position.x - position_before.x, global_position.z - position_before.z).length()
	_footstep_distance += traveled
	if _footstep_distance < 1.8:
		return
	_footstep_distance = fmod(_footstep_distance, 1.8)
	var surface := "water" if _current_water != null else _detect_floor_surface()
	ai_footstep.emit(global_position, surface, false)

func _detect_floor_surface() -> String:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 1.2, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "concrete"
	var collider: Object = hit.get("collider")
	var surface_type := String(collider.get_meta("surface_type", "")) if collider != null else ""
	return surface_type if not surface_type.is_empty() else "concrete"

func _has_ai_standing_clearance() -> bool:
	var standing_shape := CapsuleShape3D.new()
	standing_shape.radius = 0.4
	standing_shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = Transform3D(global_transform.basis, global_position)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
