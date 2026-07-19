extends StaticBody3D

const DamageModel = preload("res://scripts/combat/DamageModel.gd")

signal dummy_killed(dummy_name: String)

@export var display_name: String = "训练目标"
@export var max_health: int = 100
@export var max_armor: int = 0
@export var has_helmet: bool = false
@export var alive_color: Color = Color(0.88, 0.32, 0.24)
@export var damaged_color: Color = Color(1.0, 0.78, 0.26)
@export var dead_color: Color = Color(0.20, 0.20, 0.20)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _current_health: int = 100
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _is_dead: bool = false
var _current_armor: int = 100

func _ready() -> void:
	_current_health = max_health
	_current_armor = max_armor
	_material.albedo_color = alive_color
	_material.roughness = 0.85
	mesh_instance.material_override = _material
	add_to_group("target_dummies")

func configure_from_record(record: Dictionary) -> void:
	var next_name: String = String(record.get("name", display_name))
	if not next_name.is_empty():
		display_name = next_name
	name = display_name.replace(" ", "_")
	max_armor = clampi(int(record.get("armor", max_armor)), 0, 100)
	has_helmet = bool(record.get("helmet", has_helmet))
	_current_armor = max_armor

func apply_hitscan_damage(amount: int, hit_position: Vector3 = Vector3.ZERO, armor_penetration: float = 1.0, penetrated: bool = false) -> Dictionary:
	if _is_dead:
		return {
			"hit": false,
			"killed": false
		}

	var local_hit := to_local(hit_position)
	var hit_group := DamageModel.resolve_hit_group(local_hit)
	var resolved := DamageModel.resolve_damage(amount, hit_group, _current_armor, has_helmet, armor_penetration)
	var health_damage := int(resolved.damage)
	var armor_damage := int(resolved.armor_damage)
	_current_armor -= armor_damage
	_current_health = maxi(0, _current_health - health_damage)
	var killed: bool = _current_health == 0

	if killed:
		_is_dead = true
		_material.albedo_color = dead_color
		collision_layer = 0
		collision_mask = 0
		collision_shape.disabled = true
		dummy_killed.emit(display_name)
		queue_free()
	else:
		_material.albedo_color = damaged_color

	return {
		"hit": true,
		"killed": killed,
		"target_name": display_name,
		"hit_group": hit_group,
		"headshot": bool(resolved.headshot),
		"armored": bool(resolved.armored),
		"helmet": has_helmet,
		"penetrated": penetrated,
		"damage": health_damage,
		"armor_damage": armor_damage,
		"remaining_armor": _current_armor,
		"remaining_health": _current_health,
		"position": hit_position
	}
