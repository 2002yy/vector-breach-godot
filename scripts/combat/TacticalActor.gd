extends CharacterBody3D

const DamageModel = preload("res://scripts/combat/DamageModel.gd")

signal actor_killed(actor_name: String, team: String)
signal ai_shot(result: Dictionary, world_position: Vector3)
signal ai_footstep(world_position: Vector3, surface: String, quiet: bool)

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
@onready var environment_sensor: Area3D = $EnvironmentSensor
@onready var bot_brain: Node = $TacticalBotBrain

var current_health: int = 100
var current_armor: int = 0
var is_dead: bool = false
var ai_crouching: bool = false
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

func configure_from_record(record: Dictionary) -> void:
	display_name = String(record.get("name", display_name))
	name = display_name.replace(" ", "_")
	team = _resolve_team(String(record.get("team", team)))
	max_health = clampi(int(record.get("health", max_health)), 1, 500)
	max_armor = clampi(int(record.get("armor", max_armor)), 0, 100)
	has_helmet = bool(record.get("helmet", has_helmet))
	equipped_weapon_id = String(record.get("weapon", equipped_weapon_id))
	rotation.y = deg_to_rad(float(record.get("yawDegrees", rad_to_deg(rotation.y))))
	spawn_position = global_position
	spawn_yaw = rotation.y
	current_health = max_health
	current_armor = max_armor
	is_dead = false
	bot_brain.call("configure", record)
	_apply_team_visual()

func apply_hitscan_damage(amount: int, hit_position: Vector3 = Vector3.ZERO, armor_penetration: float = 1.0, penetrated: bool = false) -> Dictionary:
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
	var killed := current_health == 0
	if killed:
		is_dead = true
		collision_layer = 0
		collision_mask = 0
		collision_shape.set_deferred("disabled", true)
		_material.albedo_color = Color(0.16, 0.17, 0.18)
		actor_killed.emit(display_name, team)
		queue_free()
	else:
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
	}
	if bot_brain != null:
		snapshot["ai"] = bot_brain.call("get_snapshot")
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
	bot_brain.call("reset_runtime")
	_apply_team_visual()

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * (0.30 if ai_crouching else 0.62)

func notify_ai_sound(world_position: Vector3, audible_radius: float, source_team: String) -> bool:
	return bool(bot_brain.call("notify_sound", world_position, audible_radius, source_team))

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
	var visual_drop := -0.32 if ai_crouching else 0.0
	body_mesh.position.y = _body_mesh_y + visual_drop
	head_mesh.position.y = _head_mesh_y + visual_drop
	weapon_mesh.position.y = _weapon_mesh_y + visual_drop
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
