extends Node

# Bind locations and radii are calibrated from preserved original export bones.
# Eye directions use bone skin deltas, not the orientation of the eyeball joint.
var _skeleton: Skeleton3D
var _bones: Array[int] = []
var _rests: Array[Transform3D] = []
var _materials: Array[ShaderMaterial] = []
var _source_unit_m := 0.0


func configure(root: Node, scene_path: String) -> bool:
	var path := scene_path.get_base_dir().path_join("source-character-eye-bindings.json")
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema") != 1:
		return false
	var model: Dictionary = data.get("models", {}).get(scene_path.get_file(), {})
	_source_unit_m = float(model.get("source_unit_m", 0.0))
	if _source_unit_m <= 0.0 or _source_unit_m > 0.1:
		return false
	for candidate in root.find_children("*", "Skeleton3D", true, false):
		_skeleton = candidate
		break
	if _skeleton == null:
		return false
	if not _bind_bones(root, model):
		return false
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material == null or material in _materials:
				continue
			var native: Dictionary = material.get_meta("source_material_parameters", {})
			if native.get("IntParams", {}).get("F_EYEBALLS", 0) == 1:
				_materials.append(material)
	process_priority = 100
	return not _materials.is_empty()


func _bind_bones(root: Node, model: Dictionary) -> bool:
	for bone in ["eyeball_l", "eyeball_r", "eye_target"]:
		var index := _skeleton.find_bone(bone)
		var position: Array = model.get("rest_positions", {}).get(bone, [])
		if index < 0 or position.size() != 3:
			return false
		var rest := _skeleton.get_bone_global_rest(index)
		# Account for the imported model's skeleton node transform as well.
		var relative := Transform3D.IDENTITY
		var cursor: Node = _skeleton
		while cursor != root:
			if cursor is Node3D:
				relative = cursor.transform * relative
			cursor = cursor.get_parent()
		var expected := Vector3(position[0], position[1], position[2])
		if (relative * rest.origin).distance_to(expected) > 0.0001:
			return false
		_bones.append(index)
		_rests.append(rest)
	return true


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if not is_instance_valid(_skeleton) or not _skeleton.is_inside_tree():
		return
	var target := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[2]).origin
	for material in _materials:
		var floats: Dictionary = material.get_meta("source_material_parameters").get(
			"FloatParams", {}
		)
		material.set_shader_parameter(
			"eye_radius",
			(
				float(floats.get("g_flEyeBallRadius1", 0.0))
				* _source_unit_m
				* _skeleton.global_basis.get_scale().abs().x
			)
		)
		for side in range(2):
			var pose := _skeleton.get_bone_global_pose(_bones[side])
			var skin := _skeleton.global_transform * pose * _rests[side].affine_inverse()
			var center := _skeleton.global_transform * pose.origin
			var up := (skin.basis * Vector3.UP).normalized()
			var forward := (skin.basis * Vector3.FORWARD).normalized()
			var direction := (target - center).normalized()
			var wall := float(
				floats.get("g_flEyeBallWalleyeL1" if side == 0 else "g_flEyeBallWalleyeR1", 0.0)
			)
			direction = direction.rotated(up, deg_to_rad(wall * (1.0 if side == 0 else -1.0)))
			for sign_value in [0.5, -0.5]:
				var limit: Vector3 = (forward + up * sign_value).normalized()
				var axis := limit.cross(direction)
				if (
					limit.angle_to(direction) > deg_to_rad(40.0)
					and axis.length_squared() > 0.000001
				):
					direction = limit.rotated(axis.normalized(), deg_to_rad(40.0))
			var prefix := "eye_left_" if side == 0 else "eye_right_"
			material.set_shader_parameter(prefix + "center", center)
			material.set_shader_parameter(prefix + "forward", direction)
			material.set_shader_parameter(prefix + "up", up)
		material.set_shader_parameter("enable_eyes", true)
