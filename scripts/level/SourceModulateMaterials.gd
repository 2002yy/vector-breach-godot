extends RefCounted

const MODULATE = preload("res://scripts/level/SourceModulate.gdshader")


static func apply(root: Node, manifest_path: String) -> int:
	if not FileAccess.file_exists(manifest_path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or data.get("schema") != 1:
		return 0
	var entries := {}
	for entry in data.get("materials", []):
		if not entry is Dictionary:
			continue
		if entry.get("source_shader") != "csgo_static_overlay.vfx" or entry.get("blend_mode") != 3:
			continue
		if entry.get("render_contract") != "source-static-overlay-mod2x-v1":
			continue
		var texture_path: String = entry.get("texture", "")
		if not ResourceLoader.exists(texture_path, "Texture2D"):
			continue
		var settings: Dictionary = entry.duplicate(true)
		settings["loaded_texture"] = load(texture_path) as Texture2D
		entries[entry.get("name", "")] = settings
	return _apply_recursive(root, entries, {})


static func _apply_recursive(node: Node, entries: Dictionary, cache: Dictionary) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var active: Material = node.get_active_material(surface)
			if active == null or not entries.has(active.resource_name):
				continue
			if active.has_meta("source_mod2x_applied"):
				count += 1
				continue
			var original := active as StandardMaterial3D
			if original == null:
				continue
			var repaired: ShaderMaterial
			if cache.has(original):
				repaired = cache[original]
			else:
				repaired = _material(original, entries[original.resource_name])
				cache[original] = repaired
			if node.material_override != null:
				node.material_override = repaired
			else:
				node.set_surface_override_material(surface, repaired)
			# Static overlays never cast shadows, even without an explicit VMAT flag.
			if node.mesh.get_surface_count() == 1:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			count += 1
	for child in node.get_children():
		count += _apply_recursive(child, entries, cache)
	return count


static func _material(original: StandardMaterial3D, entry: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = MODULATE
	if original.cull_mode != BaseMaterial3D.CULL_BACK:
		var variant := MODULATE.duplicate() as Shader
		var mode := (
			"cull_disabled" if original.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_front"
		)
		variant.code = variant.code.replace("cull_back", mode)
		result.shader = variant
	result.resource_name = original.resource_name
	result.render_priority = original.render_priority
	result.set_shader_parameter("source_color_texture", entry.loaded_texture)
	result.set_shader_parameter("source_opacity", float(entry.get("opacity_multiplier", 1.0)))
	var linear_tint := original.albedo_color.srgb_to_linear()
	result.set_shader_parameter("source_tint", Vector3(linear_tint.r, linear_tint.g, linear_tint.b))
	result.set_shader_parameter("uv_scale", original.uv1_scale)
	result.set_shader_parameter("uv_offset", original.uv1_offset)
	result.set_shader_parameter("surface_offset", original.grow_amount if original.grow else 0.0)
	result.set_meta("source_mod2x_applied", true)
	result.set_meta("source_material_parameters", entry.get("native_material", {}).duplicate(true))
	result.set_meta("source_render_contract", entry.get("render_contract", ""))
	var native: Dictionary = entry.get("native_material", {})
	result.set_shader_parameter(
		"source_fog_enabled", native.get("IntParams", {}).get("g_bFogEnabled", 1) != 0
	)
	return result


static func update_environment(root: Node, environment: Environment) -> void:
	if environment == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as ShaderMaterial
			if material == null or not material.has_meta("source_mod2x_applied"):
				continue
			for property in [
				"fog_enabled",
				"fog_density",
				"fog_height",
				"fog_height_density",
				"fog_depth_begin",
				"fog_depth_end",
				"fog_depth_curve"
			]:
				material.set_shader_parameter(property, environment.get(property))
			material.set_shader_parameter(
				"depth_fog", environment.fog_mode == Environment.FOG_MODE_DEPTH
			)
