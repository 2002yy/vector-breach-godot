extends RefCounted

const HELPER_NAMES := ["wrongway_timer", "toolssolidblocklight", "toolsblocklight"]
const HIDDEN_SHADER = preload("res://scripts/level/source_hidden_helper.gdshader")


static func apply(root: Node) -> int:
	if root.has_meta("source_helper_hidden_surfaces"):
		return int(root.get_meta("source_helper_hidden_surfaces"))
	var material := ShaderMaterial.new()
	material.shader = HIDDEN_SHADER
	var count := _apply_recursive(root, material)
	root.set_meta("source_helper_hidden_surfaces", count)
	return count


static func _apply_recursive(node: Node, hidden: ShaderMaterial) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		var helpers: Array[int] = []
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			if material != null and material.resource_name.to_lower() in HELPER_NAMES:
				helpers.append(surface)
		if (
			helpers.size() == node.mesh.get_surface_count()
			and not helpers.is_empty()
			and node.get_child_count() == 0
		):
			node.hide()
		else:
			for surface in helpers:
				if node.material_override != null:
					node.material_override = hidden
				else:
					node.set_surface_override_material(surface, hidden)
		count += helpers.size()
	for child in node.get_children():
		count += _apply_recursive(child, hidden)
	return count
