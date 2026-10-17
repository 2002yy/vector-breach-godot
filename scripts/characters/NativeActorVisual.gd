extends Node3D

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const EquipmentVisuals = preload("res://scripts/player/EquipmentVisuals.gd")
const RIFLE = preload("res://assets/models/weapons/vb_rifle.glb")
const PISTOL = preload("res://assets/models/weapons/vb_pistol.glb")
const Official = preload("res://scripts/player/OfficialEquipment.gd")
var model: Node3D
var weapon_socket: Node3D
var weapon: Node3D
var weapon_kind := ""
var profile_id := ""


func install(id: String) -> bool:
	model = Appearance.instantiate(id)
	if model == null:
		return false
	profile_id = id
	add_child(model)
	var skeleton := Appearance.find_skeleton(model)
	if skeleton == null or skeleton.find_bone("hand_R") < 0:
		return false
	var attach := BoneAttachment3D.new()
	attach.bone_name = "hand_R"
	skeleton.add_child(attach)
	weapon_socket = Node3D.new()
	weapon_socket.name = "WeaponSocket"
	attach.add_child(weapon_socket)
	weapon_socket.transform = (
		skeleton.get_bone_global_rest(skeleton.find_bone("hand_R")).affine_inverse()
		* Appearance.grip_frame(id, "R")
	)
	for player in model.find_children("*", "AnimationPlayer", true, false):
		for clip in player.get_animation_list():
			var animation: Animation = player.get_animation(clip)
			animation.loop_mode = (
				Animation.LOOP_LINEAR
				if clip not in ["death", "hit", "reload", "pistol_reload"]
				else Animation.LOOP_NONE
			)
	return true


func set_weapon(kind: String) -> void:
	if kind == weapon_kind:
		return
	weapon_kind = kind
	if weapon != null:
		weapon.free()
	weapon = Official.build(kind, "CT" if profile_id.begins_with("ct-") else "T")
	if weapon != null:
		weapon_socket.add_child(weapon)
		return
	if kind == "knife":
		weapon = EquipmentVisuals.build("knife")
		weapon.position = Vector3(0, 0.07, -0.05)
		weapon.rotation = Vector3(-0.15, -0.3, -0.35)
	else:
		weapon = (PISTOL if kind == "pistol" else RIFLE).instantiate()
		weapon.position = Vector3(0, 0.03, -0.10)
		weapon.rotation.y = PI
		weapon.scale = Vector3.ONE * (0.68 if kind == "pistol" else 0.55)
		for part in weapon.find_children("GEO-*", "MeshInstance3D", true, false):
			if "-sleeve-" in part.name or "-glove-" in part.name:
				part.hide()
	weapon_socket.add_child(weapon)


func clip_for(action: StringName) -> StringName:
	if weapon_kind in ["pistol", "knife"] and action in [&"idle", &"run", &"crouch"]:
		return StringName(weapon_kind + "_" + String(action))
	return action
