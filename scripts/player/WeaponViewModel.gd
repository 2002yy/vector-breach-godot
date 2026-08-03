extends Node3D

@export var equip_drop: float = 0.11
@export var recoil_distance: float = 0.026
@export var recoil_degrees: float = 2.2
@export var recovery_speed: float = 13.0
@export var movement_sway_distance: float = 0.012
@export var movement_sway_degrees: float = 0.75
@export var landing_drop: float = 0.035
@export var reload_drop: float = 0.105

@onready var rifle_model: Node3D = $RifleModel
@onready var pistol_model: Node3D = $PistolModel

var current_weapon_slot: int = 0
var _equip_offset: float = 0.0
var _shot_kick: float = 0.0
var _shot_side: float = 0.0
var _landing_offset: float = 0.0
var _reload_blend: float = 0.0
var _reload_active: bool = false
var _movement_speed: float = 0.0
var _grounded: bool = true
var _crouching: bool = false
var _sway_phase: float = 0.0
var _shot_sequence: int = 0

func _ready() -> void:
	set_weapon_slot(0, false)

func _process(delta: float) -> void:
	_equip_offset = move_toward(_equip_offset, 0.0, recovery_speed * delta)
	_shot_kick = move_toward(_shot_kick, 0.0, recovery_speed * delta)
	_shot_side = move_toward(_shot_side, 0.0, recovery_speed * 0.8 * delta)
	_landing_offset = move_toward(_landing_offset, 0.0, landing_drop * 4.0 * delta)
	_reload_blend = move_toward(_reload_blend, 1.0 if _reload_active else 0.0, delta * (5.5 if _reload_active else 8.0))
	var movement_weight := clampf(_movement_speed / 6.2, 0.0, 1.0) if _grounded else 0.0
	if movement_weight > 0.03:
		_sway_phase += delta * lerpf(4.2, 8.5, movement_weight)
	else:
		_sway_phase = move_toward(_sway_phase, 0.0, delta * 5.0)
	var sway_x := sin(_sway_phase) * movement_sway_distance * movement_weight
	var sway_y := absf(cos(_sway_phase)) * movement_sway_distance * 0.52 * movement_weight
	if _crouching:
		sway_x *= 0.55
		sway_y *= 0.55
	position = Vector3(
		sway_x + _shot_side * recoil_distance * 0.36,
		-_equip_offset - _landing_offset - _reload_blend * reload_drop - sway_y,
		_shot_kick * recoil_distance + _reload_blend * 0.025
	)
	rotation = Vector3(
		deg_to_rad(-_shot_kick * recoil_degrees + _reload_blend * 11.0),
		deg_to_rad(_shot_side * 0.45 - _reload_blend * 4.5),
		deg_to_rad(-sin(_sway_phase) * movement_sway_degrees * movement_weight + _reload_blend * 7.5)
	)

func set_weapon_slot(slot_index: int, animate: bool = true) -> void:
	if slot_index < 0 or slot_index > 1:
		return
	current_weapon_slot = slot_index
	rifle_model.visible = slot_index == 0
	pistol_model.visible = slot_index == 1
	if animate:
		_equip_offset = equip_drop

func play_shot() -> void:
	_shot_sequence += 1
	_shot_kick = 1.0
	_shot_side = -1.0 if _shot_sequence % 2 == 0 else 1.0

func update_motion(speed: float, grounded: bool, crouching: bool) -> void:
	_movement_speed = maxf(0.0, speed)
	_grounded = grounded
	_crouching = crouching

func play_landing(strength: float) -> void:
	_landing_offset = landing_drop * clampf(strength, 0.25, 1.0)

func play_reload_started() -> void:
	_reload_active = true

func play_reload_finished() -> void:
	_reload_active = false

func get_debug_snapshot() -> Dictionary:
	return {
		"weapon_slot": current_weapon_slot,
		"rifle_visible": rifle_model.visible,
		"pistol_visible": pistol_model.visible,
		"shot_kick": _shot_kick,
		"shot_side": _shot_side,
		"landing_offset": _landing_offset,
		"reload_active": _reload_active,
		"movement_speed": _movement_speed,
	}
