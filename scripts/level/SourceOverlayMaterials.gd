extends RefCounted

# Source2Viewer 20.1 exports overlays with this offset in mesh coordinates.
# Keep the immutable input meshes; undo the excess only in their visual material.
const EXPORTED_OFFSET := 0.01 / 0.0254
const SURFACE_OFFSET := 0.001


static func apply(root: Node, manifest_path: String) -> int:
	if not FileAccess.file_exists(manifest_path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or parsed.get("schema") != 1:
		return 0
	if parsed.get("exporter") != "Source2Viewer-CLI 20.1":
		return 0
	var names: Variant = parsed.get("materials", [])
	if not names is Array:
		return 0
	var materials: Dictionary = {}
	for name in names:
		if name is String and not name.is_empty():
			materials[name] = null
	return _apply_recursive(root, materials)


static func _apply_recursive(node: Node, materials: Dictionary, cache: Dictionary = {}) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as StandardMaterial3D
			if original == null or not materials.has(original.resource_name):
				continue
			var repaired: StandardMaterial3D = original
			if original.grow and is_equal_approx(original.grow_amount, SURFACE_OFFSET - EXPORTED_OFFSET):
				pass
			elif cache.has(original):
				repaired = cache[original]
			else:
				repaired = original.duplicate() as StandardMaterial3D
				repaired.grow = true
				repaired.grow_amount = SURFACE_OFFSET - EXPORTED_OFFSET
				cache[original] = repaired
			node.set_surface_override_material(surface, repaired)
			# Grow displaces rendered vertices outside the immutable mesh bounds.
			# Expand conservatively, including scaled instances, to keep them visible.
			var margin: float = EXPORTED_OFFSET * maxf(1.0, node.global_transform.basis.get_scale().abs().length())
			node.extra_cull_margin = maxf(node.extra_cull_margin, margin)
			count += 1
	for child in node.get_children():
		count += _apply_recursive(child, materials, cache)
	return count
