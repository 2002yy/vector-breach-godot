extends RefCounted

const CHARACTER_SHADER = preload("res://scripts/characters/native_character.gdshader")
static var _manifests: Dictionary = {}


static func apply(root: Node, scene_path: String) -> int:
	var path := scene_path.get_base_dir().path_join("source-character-shading.json")
	if not _manifests.has(path):
		_manifests[path] = _load_manifest(path)
	var entries: Dictionary = _manifests[path]
	root.set_meta("source_character_shading_surfaces", 0)
	if entries.is_empty() or DisplayServer.get_name() == "headless":
		return 0
	root.set_meta("source_character_shading_contract", "source-character-direct-v1")
	var count := _apply_recursive(root, entries, {})
	root.set_meta("source_character_shading_surfaces", count)
	return count


static func _load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema") != 1:
		return {}
	var entries := {}
	for entry in data.get("materials", []):
		if not entry is Dictionary or entry.get("render_contract") != "source-character-direct-v1":
			continue
		var native: Dictionary = entry.get("native_material", {})
		if native.get("ShaderName") != "csgo_character.vfx":
			continue
		var settings: Dictionary = entry.duplicate(true)
		var textures := {}
		var complete := true
		var required := {
			"F_CLOTH_SHADING": ["g_tMetalness"],
			"F_SUBSURFACE_SCATTERING": ["g_tSssMask", "g_tDiffuseFalloff"],
			"F_ANISOTROPIC_GLOSS": ["g_tAnisoGloss"]
		}
		for flag in required:
			if native.get("IntParams", {}).get(flag, 0) == 1:
				for binding in required[flag]:
					complete = complete and entry.get("textures", {}).has(binding)
		for binding in entry.get("textures", {}):
			var texture_path: String = entry.textures[binding]
			if not texture_path.begins_with("res://assets/local_reference/"):
				complete = false
			elif ResourceLoader.exists(texture_path, "Texture2D"):
				textures[binding] = load(texture_path)
			else:
				complete = false
		if complete:
			settings["loaded_textures"] = textures
			entries[entry.get("name", "")] = settings
	return entries


static func _apply_recursive(node: Node, entries: Dictionary, cache: Dictionary) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var active: Material = node.get_active_material(surface)
			if active == null or not entries.has(active.resource_name):
				continue
			if active.has_meta("source_character_shading_applied"):
				count += 1
				continue
			var original := active as StandardMaterial3D
			if original == null or original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if not cache.has(original):
				cache[original] = _material(original, entries[original.resource_name])
			if node.material_override != null:
				node.material_override = cache[original]
			else:
				node.set_surface_override_material(surface, cache[original])
			count += 1
	for child in node.get_children():
		count += _apply_recursive(child, entries, cache)
	return count


static func _material(original: StandardMaterial3D, entry: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = CHARACTER_SHADER
	if original.cull_mode != BaseMaterial3D.CULL_BACK:
		var variant := CHARACTER_SHADER.duplicate() as Shader
		var mode := (
			"cull_disabled" if original.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_front"
		)
		variant.code = variant.code.replace("cull_back", mode)
		result.shader = variant
	result.resource_name = original.resource_name
	result.render_priority = original.render_priority
	result.set_shader_parameter("base_color", original.albedo_color.srgb_to_linear())
	result.set_shader_parameter("base_roughness", original.roughness)
	result.set_shader_parameter("base_metallic", original.metallic)
	result.set_shader_parameter("uv_scale", original.uv1_scale)
	result.set_shader_parameter("uv_offset", original.uv1_offset)
	result.set_shader_parameter("normal_strength", original.normal_scale)
	result.set_shader_parameter("ao_light_affect", original.ao_light_affect)
	for channel in ["roughness", "metal", "ao"]:
		var property: String = "metallic" if channel == "metal" else channel
		result.set_shader_parameter(
			channel + "_channel", original.get(property + "_texture_channel")
		)
	var bindings := {
		"base": original.albedo_texture,
		"normal": original.normal_texture,
		"roughness": original.roughness_texture,
		"metal": original.metallic_texture,
		"ao": original.ao_texture
	}
	for key in bindings:
		var enabled: bool = bindings[key] != null
		if key == "normal":
			enabled = enabled and original.normal_enabled
		elif key == "ao":
			enabled = enabled and original.ao_enabled
		result.set_shader_parameter("use_" + key, enabled)
		if bindings[key] != null:
			result.set_shader_parameter(key + "_texture", bindings[key])
	var native: Dictionary = entry.get("native_material", {})
	var flags: Dictionary = native.get("IntParams", {})
	var floats: Dictionary = native.get("FloatParams", {})
	var vectors: Dictionary = native.get("VectorParams", {})
	var textures: Dictionary = entry.get("loaded_textures", {})
	for binding in {
		"g_tMetalness": "cloth_texture",
		"g_tAnisoGloss": "aniso_texture",
		"g_tSssMask": "skin_texture",
		"g_tDiffuseFalloff": "skin_falloff"
	}:
		if textures.has(binding):
			var uniform_name: String = {
				"g_tMetalness": "cloth_texture",
				"g_tAnisoGloss": "aniso_texture",
				"g_tSssMask": "skin_texture",
				"g_tDiffuseFalloff": "skin_falloff"
			}[binding]
			result.set_shader_parameter(uniform_name, textures[binding])
	result.set_shader_parameter("enable_cloth", flags.get("F_CLOTH_SHADING", 0) == 1)
	result.set_shader_parameter("enable_skin", flags.get("F_SUBSURFACE_SCATTERING", 0) == 1)
	result.set_shader_parameter("enable_aniso", flags.get("F_ANISOTROPIC_GLOSS", 0) == 1)
	result.set_shader_parameter("sheen_scale", float(floats.get("g_flSheenScale", 1.0)))
	result.set_shader_parameter("curvature_scale", float(floats.get("g_flCurvatureScale", 1.0)))
	result.set_shader_parameter(
		"normal_softness", _vector(vectors.get("g_vNormalSoftness", [0, 0, 0]))
	)
	var tint := _vector(vectors.get("g_flSheenTintColor", [1, 1, 1]))
	var linear_tint := Color(tint.x, tint.y, tint.z).srgb_to_linear()
	result.set_shader_parameter("sheen_tint", Vector3(linear_tint.r, linear_tint.g, linear_tint.b))
	result.set_shader_parameter(
		"spherical_aniso", flags.get("F_SPHERICAL_PROJECTED_ANISOTROPIC_TANGENTS", 0) == 1
	)
	# Official Source Z-up -> normalized, turned body -> exported Godot Y-up.
	var pole := _vector(vectors.get("g_vSphericalAnisotropyPole", [0, 0, 1]))
	result.set_shader_parameter("aniso_pole", Vector3(-pole.x, pole.z, pole.y))
	result.set_shader_parameter(
		"aniso_angle", float(floats.get("g_vSphericalAnisotropyAngle", 0.0))
	)
	result.set_meta("source_character_shading_applied", true)
	result.set_meta("source_material_parameters", native.duplicate(true))
	result.set_meta("source_features_pending", entry.get("pending_features", []).duplicate())
	return result


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
