extends RefCounted

const ASSETS = preload("res://assets/models/equipment/hand_equipment.glb")
static var _fabric_normal: NoiseTexture2D


# Editable canonical Blender assets. Presentation only, never collision authority.
static func build(kind: String, _held: bool = false) -> Node3D:
	var model := part(kind)
	model.name = kind.to_pascal_case() + "Model"
	return model


static func part(kind: String) -> Node3D:
	var source := ASSETS.instantiate()
	var model := source.find_child(kind, true, false) as Node3D
	assert(model != null, "Missing canonical equipment part: " + kind)
	model.get_parent().remove_child(model)
	source.free()
	for child in model.get_children():
		if String(child.name).begins_with("SafetyRing"):
			child.name = "SafetyRing"
		elif String(child.name).begins_with("SafetyLever"):
			child.name = "SafetyLever"
	_apply_surface_detail(model)
	return model


static func _apply_surface_detail(node: Node) -> void:
	if node is MeshInstance3D:
		for index in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(index) as StandardMaterial3D
			if material != null and "fabric" in material.resource_name:
				if _fabric_normal == null:
					var noise := FastNoiseLite.new()
					noise.seed = 10715
					noise.frequency = 0.18
					_fabric_normal = NoiseTexture2D.new()
					_fabric_normal.width = 128
					_fabric_normal.height = 128
					_fabric_normal.noise = noise
					_fabric_normal.as_normal_map = true
					_fabric_normal.bump_strength = 0.35
				var detailed := material.duplicate() as StandardMaterial3D
				detailed.normal_enabled = true
				detailed.normal_texture = _fabric_normal
				detailed.normal_scale = 0.25
				node.set_surface_override_material(index, detailed)
	for child in node.get_children():
		_apply_surface_detail(child)
