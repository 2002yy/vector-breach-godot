extends RefCounted

static var _manifests: Dictionary = {}


static func apply(root: Node, scene_path: String) -> int:
	var path := scene_path.get_base_dir().path_join("source-materials.json")
	if not _manifests.has(path):
		var data: Variant = {}
		if FileAccess.file_exists(path):
			data = JSON.parse_string(FileAccess.get_file_as_string(path))
		_manifests[path] = data if data is Dictionary and data.get("schema") == 1 else {}
	var asset: Dictionary = _manifests[path].get("assets", {}).get(scene_path.get_file(), {})
	root.set_meta("source_material_contract", asset.duplicate(true))
	# The dummy renderer cannot instantiate shaders for pre-tree material copies.
	# Keep the complete contract available to headless logic without GPU overrides.
	if DisplayServer.get_name() == "headless":
		return 0
	var entries := {}
	for entry in asset.get("materials", []):
		if entry is Dictionary and entry.get("native_material", {}) is Dictionary:
			entries[entry.get("name", "")] = entry
	return _apply_recursive(root, entries, {})


static func _apply_recursive(node: Node, entries: Dictionary, cache: Dictionary) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as StandardMaterial3D
			if original == null or not entries.has(original.resource_name):
				continue
			if original.has_meta("source_material_parameters"):
				count += 1
				continue
			var result: StandardMaterial3D
			if cache.has(original):
				result = cache[original]
			else:
				var entry: Dictionary = entries[original.resource_name]
				var native: Dictionary = entry.get("native_material", {})
				result = original.duplicate() as StandardMaterial3D
				if entry.get("render_contract") == "source-additive-v1":
					if native.get("IntParams", {}).get("F_ADDITIVE_BLEND", 0) == 1:
						result.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				result.set_meta("source_material_parameters", native.duplicate(true))
				result.set_meta(
					"source_features_pending", entry.get("pending_features", []).duplicate()
				)
				cache[original] = result
			if node.material_override != null:
				node.material_override = result
			else:
				node.set_surface_override_material(surface, result)
			count += 1
	for child in node.get_children():
		count += _apply_recursive(child, entries, cache)
	return count
