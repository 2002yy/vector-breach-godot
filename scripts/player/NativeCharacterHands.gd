extends Node3D

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
var profile_id := ""
var rigs: Dictionary = {}
var skeleton_bones := 0


func install(id: String) -> bool:
	if not Appearance.available(id):
		return false
	profile_id = id
	for side in ["L", "R"]:
		var model := Appearance.instantiate(id, "-arm-" + side)
		add_child(model)
		var skeleton := Appearance.find_skeleton(model)
		if skeleton == null:
			return false
		var forearm := skeleton.find_bone("arm_lower_" + side)
		var hand := skeleton.find_bone("hand_" + side)
		if forearm < 0 or hand < 0:
			return false
		var fingers: Array = []
		for i in range(skeleton.get_bone_count()):
			var bone_name := skeleton.get_bone_name(i)
			if (
				bone_name.begins_with("finger_")
				and bone_name.ends_with("_" + side)
				and "meta" not in bone_name
			):
				fingers.append(i)
		rigs[side] = {
			"model": model,
			"skeleton": skeleton,
			"forearm": forearm,
			"hand": hand,
			"forearm_rest": skeleton.get_bone_global_rest(forearm),
			"hand_rest": skeleton.get_bone_global_rest(hand),
			"fingers": fingers,
		}
		skeleton_bones += skeleton.get_bone_count()
	return true


func update_pose(side: String, wrist: Transform3D, elbow: Vector3, curl: float) -> void:
	if not rigs.has(side):
		return
	var rig: Dictionary = rigs[side]
	var model: Node3D = rig.model
	model.transform = wrist
	var skeleton: Skeleton3D = rig.skeleton
	var forearm: Transform3D = rig.forearm_rest
	var hand: Transform3D = rig.hand_rest
	var local_elbow := wrist.affine_inverse() * elbow
	var start := forearm.origin
	var length := maxf(start.length(), 0.01)
	var direction := start.normalized()
	var axis := Quaternion(direction, local_elbow.normalized())
	# Stretch along the original sleeve axis, preserve its cross section.
	var align := Basis(Quaternion(Vector3.FORWARD, direction))
	var stretch := (
		align * Basis.from_scale(Vector3(1, 1, local_elbow.length() / length)) * align.inverse()
	)
	forearm.basis = Basis(axis) * stretch * forearm.basis
	forearm.origin = local_elbow
	skeleton.set_bone_global_pose_override(rig.forearm, forearm, 1.0, true)
	# Pin the connected glove to the actual weapon wrist; forearm deformation cannot pull it away.
	skeleton.set_bone_global_pose_override(rig.hand, hand, 1.0, true)
	for index in rig.fingers:
		var rest := skeleton.get_bone_global_rest(index)
		var bend_axis := rest.basis.inverse() * Vector3.RIGHT
		var bend := curl * (0.5 if "thumb" in skeleton.get_bone_name(index) else 0.95)
		skeleton.set_bone_pose_rotation(index, Quaternion(bend_axis.normalized(), -bend))


func snapshot() -> Dictionary:
	return {"profile": profile_id, "skeleton_bones": skeleton_bones, "arms": rigs.size()}
