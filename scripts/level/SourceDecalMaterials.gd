extends RefCounted


static func apply(root: Node, manifest_path: String) -> int:
	if not FileAccess.file_exists(manifest_path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or data.get("schema") != 1:
		return 0
	var entries: Variant = data.get("materials", [])
	if not entries is Array:
		return 0
	var materials := {}
	for entry in entries:
		if not entry is Dictionary or entry.get("source_shader") != "csgo_static_overlay.vfx":
			continue
		var mode: Variant = entry.get("blend_mode")
		var name: Variant = entry.get("name")
		var texture_path: Variant = entry.get("texture")
		if not (mode is int or mode is float) or not name is String or not texture_path is String:
			continue
		var mode_number := int(mode)
		if float(mode) != float(mode_number) or mode_number not in [1, 2]:
			continue
		if not ResourceLoader.exists(texture_path, "Texture2D"):
			continue
		var opacity: Variant = entry.get("opacity_multiplier", 1.0)
		var threshold: Variant = entry.get("alpha_test", 0.5)
		if not (opacity is float or opacity is int) or not (threshold is float or threshold is int):
			continue
		var settings: Dictionary = entry.duplicate()
		settings["blend_mode"] = mode_number
		settings["loaded_texture"] = load(texture_path) as Texture2D
		materials[name] = settings
	return _apply_recursive(root, materials, {})


static func _apply_recursive(node: Node, entries: Dictionary, cache: Dictionary) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as StandardMaterial3D
			if original == null or not entries.has(original.resource_name):
				continue
			var entry: Dictionary = entries[original.resource_name]
			if original.has_meta("source_decal_alpha_applied"):
				count += 1
				continue
			var repaired: StandardMaterial3D
			if cache.has(original):
				repaired = cache[original]
			else:
				repaired = original.duplicate() as StandardMaterial3D
				repaired.albedo_texture = entry.loaded_texture
				repaired.albedo_color.a *= clampf(
					float(entry.get("opacity_multiplier", 1.0)), 0.0, 1.0
				)
				if int(entry.blend_mode) == 2:
					repaired.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					repaired.alpha_scissor_threshold = clampf(
						float(entry.get("alpha_test", 0.5)), 0.0, 1.0
					)
				else:
					repaired.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				repaired.set_meta("source_decal_alpha_applied", true)
				cache[original] = repaired
			if node.material_override != null:
				node.material_override = repaired
			else:
				node.set_surface_override_material(surface, repaired)
			# csgo_static_overlay implies no cast shadows even without the VMAT flag.
			if node.mesh.get_surface_count() == 1:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			count += 1
	for child in node.get_children():
		count += _apply_recursive(child, entries, cache)
	return count
