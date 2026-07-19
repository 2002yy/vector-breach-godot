extends StaticBody3D

signal dummy_killed(dummy_name: String)

@export var display_name: String = "Dummy"
@export var max_health: int = 100
@export var max_armor: int = 100
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

func apply_hitscan_damage(amount: int, hit_position: Vector3 = Vector3.ZERO, armor_penetration: float = 1.0, penetrated: bool = false) -> Dictionary:
	if _is_dead:
		return {
			"hit": false,
			"killed": false
		}

	var local_hit := to_local(hit_position)
	var hit_group := "torso"
	var multiplier := 1.0
	var armored := true
	if local_hit.y >= 0.52:
		hit_group = "head"
		multiplier = 4.0
	elif local_hit.y <= -0.34:
		hit_group = "legs"
		multiplier = 0.75
		armored = false
	var scaled_damage := maxi(1, int(round(float(amount) * multiplier)))
	var health_damage := scaled_damage
	var armor_damage := 0
	if armored and _current_armor > 0:
		health_damage = maxi(1, int(round(float(scaled_damage) * clampf(armor_penetration, 0.0, 1.0))))
		armor_damage = mini(_current_armor, maxi(1, int(round(float(scaled_damage - health_damage) * 0.5))))
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
		"headshot": hit_group == "head",
		"penetrated": penetrated,
		"damage": health_damage,
		"armor_damage": armor_damage,
		"remaining_armor": _current_armor,
		"remaining_health": _current_health,
		"position": hit_position
	}
