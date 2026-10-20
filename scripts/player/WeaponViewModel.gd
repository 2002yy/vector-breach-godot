extends Node3D

const WeaponVisuals = preload("res://scripts/player/WeaponVisuals.gd")

@export var equip_drop: float = 0.11
@export var recoil_distance: float = 0.026
@export var recoil_degrees: float = 2.2
@export var recovery_speed: float = 13.0
@export var movement_sway_distance: float = 0.012
@export var movement_sway_degrees: float = 0.75
@export var landing_drop: float = 0.035
@export var reload_drop: float = 0.105

var _primary_weapon_id := "rifle"

@onready var rifle_model: Node3D = $RifleModel
@onready var pistol_model: Node3D = $PistolModel

const EquipmentVisuals = preload("res://scripts/player/EquipmentVisuals.gd")
const Hands = preload("res://scripts/player/FirstPersonHands.gd")
const Official = preload("res://scripts/player/OfficialEquipment.gd")
var hands: Node3D
var _magazine_parts: Array[Node] = []
var _official_team := ""
var _fallback_magazine_mesh: Mesh
var _fallback_models: Dictionary = {}

var equipment_models: Dictionary = {}
var equipped_kind := "rifle"
var _use_blend := 0.0
var _use_kind := ""
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
	hands = Hands.new()
	hands.name = "Hands"
	add_child(hands)
	_fallback_magazine_mesh = hands.magazine.mesh
	# Older weapon GLBs include rigid display arms. The articulated hands own this
	# presentation now; leaving both visible creates floating cylinders and gloves.
	for weapon in [rifle_model, pistol_model]:
		for part in weapon.find_children("GEO-*", "MeshInstance3D", true, false):
			if "-sleeve-" in part.name or "-glove-" in part.name:
				part.hide()
	for kind in ["knife", "he_grenade", "flash_grenade", "smoke_grenade", "fire_grenade"]:
		var model := EquipmentVisuals.build(kind, false)
		model.position = Vector3(0.24, -0.22, -0.43)
		model.rotation = Vector3(-0.15, -0.3, -0.35)
		model.visible = false
		add_child(model)
		var ring := model.get_node_or_null("SafetyRing") as Node3D
		if ring != null:
			ring.set_meta("rest_position", ring.position)
		equipment_models[kind] = model
	var c4 := preload("res://assets/models/objectives/c4_device.glb").instantiate() as Node3D
	c4.name = "C4Model"
	c4.position = Vector3(0.20, -0.20, -0.55)
	c4.scale = Vector3.ONE * 0.72
	c4.rotation_degrees = Vector3(66, 0, -9)
	c4.visible = false
	add_child(c4)
	equipment_models["c4"] = c4
	for model in [rifle_model, pistol_model] + equipment_models.values():
		model.reparent(hands.right, false)
		model.position -= Vector3(0.24, -0.29, -0.38)
		_magazine_parts.append_array(model.find_children("*magazine*", "MeshInstance3D", true, false))
	for kind in ["rifle", "pistol", "knife", "c4", "fire_grenade"]:
		var original: Node3D = rifle_model if kind == "rifle" else (pistol_model if kind == "pistol" else equipment_models[kind])
		_fallback_models[kind] = original.duplicate()
	set_weapon_slot(0, false)
	_refresh_official_equipment()


func _exit_tree() -> void:
	for model in _fallback_models.values():
		if is_instance_valid(model):
			model.free()
	_fallback_models.clear()


func _refresh_official_equipment() -> void:
	if hands == null or _official_team == GameState.player_team:
		return
	_official_team = GameState.player_team
	for kind in ["rifle", "pistol", "knife", "c4", "fire_grenade"]:
		var requested: String = _primary_weapon_id if kind == "rifle" else String(kind)
		var next := Official.build(requested, _official_team)
		if kind == "rifle" and _primary_weapon_id != "rifle" and next == null:
			next = WeaponVisuals.build(_primary_weapon_id, _official_team)
		var previous: Node3D = rifle_model if kind == "rifle" else (pistol_model if kind == "pistol" else equipment_models[kind])
		if next == null:
			if not previous.has_meta("official_cs") and not previous.has_meta("prototype_weapon"):
				continue
			next = _fallback_models[kind].duplicate() as Node3D
		if kind == "rifle" and next.has_meta("official_cs"):
			# First-person projection adapter; AI/world geometry keeps native metres.
			next.scale *= 0.86
		next.name = previous.name
		hands.right.remove_child(previous)
		previous.free()
		hands.right.add_child(next)
		next.visible = equipped_kind == kind
		if kind == "rifle":
			rifle_model = next
		elif kind == "pistol":
			pistol_model = next
		else:
			equipment_models[kind] = next
	_magazine_parts.clear()
	for model in [rifle_model, pistol_model]:
		if not model.has_meta("official_cs"):
			_magazine_parts.append_array(model.find_children("*magazine*", "MeshInstance3D", true, false))

func set_weapon_identity(weapon_id: String) -> void:
	if weapon_id == "pistol":
		return
	if weapon_id in ["rifle", "sniper", "smg", "shotgun"] and weapon_id != _primary_weapon_id:
		_primary_weapon_id = weapon_id
		_official_team = ""
		_refresh_official_equipment()

func _process(delta: float) -> void:
	_refresh_official_equipment()
	var current: Node3D = rifle_model if equipped_kind == "rifle" else pistol_model
	hands.magazine.mesh = null if current.has_meta("official_cs") else _fallback_magazine_mesh
	for magazine in _magazine_parts:
		magazine.visible = not hands.magazine.visible
	if hands.action == "throw" and hands.animator.current_animation_position >= 0.30 and equipment_models.has(equipped_kind):
		(equipment_models[equipped_kind] as Node3D).visible = false
	if hands.action == "throw" and equipment_models.has(equipped_kind):
		var ring := (equipment_models[equipped_kind] as Node3D).get_node_or_null("SafetyRing") as Node3D
		if ring != null:
			var time: float = hands.animator.current_animation_position
			ring.position = (ring.get_meta("rest_position") as Vector3) + Vector3.LEFT * clampf((time - 0.12) / 0.10, 0.0, 1.0) * 0.12
			ring.visible = time < 0.22
	_use_blend = move_toward(_use_blend, 0.0, delta * 4.5)
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


func set_equipment(kind: String, animate: bool = true) -> void:
	if kind not in ["rifle", "pistol"] and not equipment_models.has(kind):
		return
	equipped_kind = kind
	_refresh_official_equipment()
	for model in [rifle_model, pistol_model] + equipment_models.values():
		Official.reset(model)
	_use_blend = 0.0
	hands.set_equipment(kind, animate)
	current_weapon_slot = 0 if kind == "rifle" else (1 if kind == "pistol" else (2 if kind == "knife" else (4 if kind == "c4" else 3)))
	rifle_model.visible = kind == "rifle"
	pistol_model.visible = kind == "pistol"
	for key in equipment_models:
		(equipment_models[key] as Node3D).visible = key == kind
		var ring := (equipment_models[key] as Node3D).get_node_or_null("SafetyRing") as Node3D
		if ring != null:
			ring.position = ring.get_meta("rest_position")
			ring.visible = true
	_reload_active = false
	_reload_blend = 0.0
	_shot_kick = 0.0
	if animate:
		_equip_offset = equip_drop

func play_equipment_use(kind: String) -> void:
	_use_kind = kind
	_use_blend = 1.0
	hands.play_action(kind if kind in ["knife", "knife_heavy"] else "throw", 0.95 if kind == "knife_heavy" else (0.65 if kind.ends_with("grenade") else 0.45))

func set_objective_action(kind: String) -> void:
	if kind in ["plant", "defuse"]:
		if hands.action != kind:
			_reload_active = false
			_reload_blend = 0.0
			rifle_model.visible = false
			pistol_model.visible = false
			for key in equipment_models:
				(equipment_models[key] as Node3D).visible = kind == "plant" and key == "c4"
			hands.set_equipment("c4" if kind == "plant" else equipped_kind, false)
			hands.play_action(kind, 0.8)
	elif hands.action in ["plant", "defuse"]:
		set_equipment(equipped_kind, false)

func cancel_actions(preserve_reload: bool = false) -> void:
	_use_blend = 0.0
	if preserve_reload and _reload_active:
		return
	_reload_active = false
	for model in [rifle_model, pistol_model]:
		Official.reset(model)
	hands.reset_pose()

func set_reload_paused(paused: bool) -> void:
	hands.animator.speed_scale = 0.0 if paused and _reload_active else 1.0
	for model in [rifle_model, pistol_model]:
		if model.has_meta("official_cs"):
			for player in model.find_children("*", "AnimationPlayer", true, false):
				player.speed_scale = 0.0 if paused and _reload_active else 1.0

func set_weapon_slot(slot_index: int, animate: bool = true) -> void:
	if slot_index < 0 or slot_index > 1:
		return
	set_equipment("rifle" if slot_index == 0 else "pistol", animate)

func play_shot() -> void:
	Official.play(rifle_model if equipped_kind == "rifle" else pistol_model, "shoot", 0.12)
	hands.play_action("shot", 0.12)
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
	var profile = preload("res://data/weapons/rifle.tres") if equipped_kind == "rifle" else preload("res://data/weapons/pistol.tres")
	hands.play_action("reload", profile.reload_duration)
	Official.play(rifle_model if equipped_kind == "rifle" else pistol_model, "reload", profile.reload_duration)

func play_reload_finished() -> void:
	_reload_active = false
	for model in [rifle_model, pistol_model]:
		Official.reset(model)
	if hands.action == "reload":
		hands.reset_pose()

func get_debug_snapshot() -> Dictionary:
	return {
		"hands": hands.snapshot(),
		"official_rifle": rifle_model.get_meta("official_cs", ""),
		"official_pistol": pistol_model.get_meta("official_cs", ""),
		"official_knife": equipment_models["knife"].get_meta("official_cs", ""),
		"official_c4": equipment_models["c4"].get_meta("official_cs", ""),
		"weapon_slot": current_weapon_slot,
		"equipped_kind": equipped_kind,
		"use_blend": _use_blend,
		"visible_equipment": equipment_models.keys().filter(func(kind): return (equipment_models[kind] as Node3D).visible),
		"rifle_visible": rifle_model.visible,
		"pistol_visible": pistol_model.visible,
		"shot_kick": _shot_kick,
		"shot_side": _shot_side,
		"landing_offset": _landing_offset,
		"reload_active": _reload_active,
		"movement_speed": _movement_speed,
	}
