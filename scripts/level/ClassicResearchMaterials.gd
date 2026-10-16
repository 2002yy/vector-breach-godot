extends RefCounted

# This is a disclosed material reconstruction, never an original Valve texture.
const ROOT := "res://assets/textures/foundry/"


static func apply(root: Node) -> void:
	var materials: Dictionary = {}
	_apply_recursive(root, materials)


static func _apply_recursive(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for index in range(instance.mesh.get_surface_count()):
			var original := instance.get_active_material(index) as StandardMaterial3D
			if original == null:
				continue
			var key := original.resource_name
			if not materials.has(key):
				var material := original.duplicate() as StandardMaterial3D
				var metal := key.to_lower().contains("metal")
				var family := "blue_metal_plate" if metal else "concrete_floor_worn_001"
				material.albedo_texture = load(ROOT + family + "_diffuse.jpg")
				material.normal_enabled = true
				material.normal_texture = load(ROOT + family + "_nor_gl.jpg")
				material.normal_scale = 0.3
				material.roughness_texture = load(ROOT + family + "_rough.jpg")
				material.uv1_triplanar = true
				material.uv1_world_triplanar = true
				material.uv1_scale = Vector3.ONE * 0.3
				material.metallic = 0.35 if metal else 0.0
				material.vertex_color_use_as_albedo = false
				materials[key] = material
			instance.set_surface_override_material(index, materials[key])
	for child in node.get_children():
		_apply_recursive(child, materials)
