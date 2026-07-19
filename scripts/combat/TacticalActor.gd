extends CharacterBody3D

const DamageModel = preload("res://scripts/combat/DamageModel.gd")

signal actor_killed(actor_name: String, team: String)

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

var current_health: int = 100
var current_armor: int = 0
var is_dead: bool = false
var spawn_position: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	add_to_group("combat_actors")
	add_to_group("target_dummies")
	spawn_position = global_position
	spawn_yaw = rotation.y
	current_health = max_health
	current_armor = max_armor
	_apply_team_visual()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

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
	_apply_team_visual()

func apply_hitscan_damage(amount: int, hit_position: Vector3 = Vector3.ZERO, armor_penetration: float = 1.0, penetrated: bool = false) -> Dictionary:
	if is_dead:
		return {"hit": false, "killed": false, "target_team": team}
	var resolved_position := global_position if hit_position == Vector3.ZERO else hit_position
	var hit_group := DamageModel.resolve_hit_group(to_local(resolved_position))
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
	return {
		"name": display_name, "team": team, "alive": not is_dead,
		"health": current_health, "armor": current_armor, "helmet": has_helmet,
		"weapon": equipped_weapon_id, "x": global_position.x, "y": global_position.y,
		"z": global_position.z, "yaw": rotation.y,
	}

func reset_actor() -> void:
	global_position = spawn_position
	rotation.y = spawn_yaw
	velocity = Vector3.ZERO
	current_health = max_health
	current_armor = max_armor
	is_dead = false
	collision_layer = 1
	collision_mask = 1
	collision_shape.disabled = false
	_apply_team_visual()

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
