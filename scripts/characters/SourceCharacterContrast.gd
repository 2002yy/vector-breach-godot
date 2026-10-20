extends RefCounted

const POSTLIT = preload("res://scripts/characters/distance_contrast_postlit.gdshader")


static func context_valid(context: Dictionary) -> bool:
	if context.get("purpose") != "diagnostic" or not context.get("accept_average_candidate", false):
		return false
	for key in ["source_unit_m", "strength", "fog_modification"]:
		if not context.get(key) is float and not context.get(key) is int:
			return false
		var value := float(context.get(key, -1.0))
		if not is_finite(value) or value < 0.0:
			return false
	if (
		context.source_unit_m <= 0.0
		or context.source_unit_m > 0.1
		or context.strength > 0.8
		or context.fog_modification > 1.0
	):
		return false
	var coefficients: Variant = context.get("irradiance_sh1", [])
	if not coefficients is Array or coefficients.size() != 3:
		return false
	for coefficient in coefficients:
		if not coefficient is Vector4 or not coefficient.is_finite():
			return false
	return true


static func apply(root: Node, scene_path: String, context: Dictionary = {}) -> int:
	if not context_valid(context):
		detach(root)
		return 0
	var path := scene_path.get_base_dir().path_join("source-character-contrast-inputs.json")
	if not FileAccess.file_exists(path):
		detach(root)
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if (
		not data is Dictionary
		or data.get("schema") != 1
		or data.get("contract") != "source-character-contrast-inputs-v1"
	):
		detach(root)
		return 0
	var entries := {}
	for row in data.get("materials", []):
		if row is Dictionary and row.get("name") is String:
			entries[row.name] = row
	var count := 0
	var seen := {}
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface) as ShaderMaterial
			if (
				original == null
				or seen.has(original)
				or not original.has_meta("source_character_shading_applied")
			):
				continue
			seen[original] = true
			var entry: Dictionary = entries.get(original.resource_name, {})
			if not _entry_valid(original, entry):
				if (
					original.next_pass != null
					and original.next_pass.has_meta("source_contrast_diagnostic")
				):
					original.next_pass = null
				continue
			if (
				original.next_pass != null
				and not original.next_pass.has_meta("source_contrast_diagnostic")
			):
				continue
			var material := original.next_pass as ShaderMaterial
			if material == null:
				material = _material(original, entry)
				original.next_pass = material
			material.set_shader_parameter("source_unit_m", float(context.source_unit_m))
			material.set_shader_parameter("contrast_strength", float(context.strength))
			material.set_shader_parameter("fog_modification", float(context.fog_modification))
			for channel in range(3):
				material.set_shader_parameter(
					["irradiance_sh_r", "irradiance_sh_g", "irradiance_sh_b"][channel],
					context.irradiance_sh1[channel]
				)
			material.set_shader_parameter("inputs_ready", true)
			count += 1
	return count


static func detach(root: Node) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if (
				original != null
				and original.next_pass != null
				and original.next_pass.has_meta("source_contrast_diagnostic")
			):
				original.next_pass = null


static func _entry_valid(original: ShaderMaterial, entry: Dictionary) -> bool:
	if (
		entry.get("average_basis") != "vtex-reflectivity-candidate"
		or entry.get("native_material", {}) != original.get_meta("source_material_parameters", {})
	):
		return false
	var average: Array = entry.get("reflectivity_rgba", [])
	if average.size() != 4:
		return false
	for value in average:
		if not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
			return false
	var exposure := float(entry.get("exposure_effective", -1.0))
	var native: Dictionary = entry.native_material
	var flags: Dictionary = native.get("IntParams", {})
	var raw := float(native.get("FloatParams", {}).get("g_fDistanceContrastExposure", 0.6))
	var translucent: bool = flags.get("F_TRANSLUCENT", 0) == 1
	var expected := raw if translucent else 1.0 - raw
	var enabled: bool = flags.get("F_DISTANCE_CONTRAST_ADJUSTMENT", 0) == 1 and not translucent
	return (
		is_finite(exposure)
		and exposure >= 0.0
		and exposure <= 1.0
		and is_equal_approx(exposure, expected)
		and entry.get("material_adjustment") == enabled
	)


static func _material(original: ShaderMaterial, entry: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = POSTLIT
	for mode in ["cull_disabled", "cull_front"]:
		if original.shader.code.contains(mode):
			var variant := POSTLIT.duplicate() as Shader
			variant.code = variant.code.replace("cull_back", mode)
			material.shader = variant
	material.render_priority = -127
	var tint: Variant = original.get_shader_parameter("base_color")
	var color := (
		Vector3(tint.r, tint.g, tint.b) if tint is Color else Vector3(tint.x, tint.y, tint.z)
	)
	material.set_shader_parameter("surface_albedo", color)
	material.set_shader_parameter("use_surface_texture", original.get_shader_parameter("use_base"))
	material.set_shader_parameter("surface_texture", original.get_shader_parameter("base_texture"))
	material.set_shader_parameter("surface_uv_scale", original.get_shader_parameter("uv_scale"))
	material.set_shader_parameter("surface_uv_offset", original.get_shader_parameter("uv_offset"))
	var average: Array = entry.reflectivity_rgba
	material.set_shader_parameter("average_albedo", Vector3(average[0], average[1], average[2]))
	material.set_shader_parameter("source_exposure", float(entry.exposure_effective))
	material.set_shader_parameter("material_adjustment", bool(entry.material_adjustment))
	material.set_shader_parameter("use_directional_sh1", true)
	material.set_meta("source_contrast_diagnostic", true)
	return material
