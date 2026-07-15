extends Node3D

@export var equip_drop: float = 0.11
@export var recoil_distance: float = 0.026
@export var recoil_degrees: float = 2.2
@export var recovery_speed: float = 13.0

@onready var rifle_model: Node3D = $RifleModel
@onready var pistol_model: Node3D = $PistolModel

var current_weapon_slot: int = 0
var _equip_offset: float = 0.0
var _shot_kick: float = 0.0

func _ready() -> void:
	set_weapon_slot(0, false)

func _process(delta: float) -> void:
	_equip_offset = move_toward(_equip_offset, 0.0, recovery_speed * delta)
	_shot_kick = move_toward(_shot_kick, 0.0, recovery_speed * delta)
	position = Vector3(0.0, -_equip_offset, _shot_kick * recoil_distance)
	rotation.x = deg_to_rad(-_shot_kick * recoil_degrees)

func set_weapon_slot(slot_index: int, animate: bool = true) -> void:
	if slot_index < 0 or slot_index > 1:
		return
	current_weapon_slot = slot_index
	rifle_model.visible = slot_index == 0
	pistol_model.visible = slot_index == 1
	if animate:
		_equip_offset = equip_drop

func play_shot() -> void:
	_shot_kick = 1.0

func get_debug_snapshot() -> Dictionary:
	return {
		"weapon_slot": current_weapon_slot,
		"rifle_visible": rifle_model.visible,
		"pistol_visible": pistol_model.visible,
		"shot_kick": _shot_kick,
	}
