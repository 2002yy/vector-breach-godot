extends RefCounted

const CHARACTER_SHADER = preload("res://scripts/characters/native_character.gdshader")
static var _manifests: Dictionary = {}


static func apply(root: Node, scene_path: String) -> int:
	var path := scene_path.get_base_dir().path_join("source-character-shading.json")
	var special_path := scene_path.get_base_dir().path_join("source-character-special.json")
	var eyes_path := scene_path.get_base_dir().path_join("source-character-eyes.json")
	if FileAccess.file_exists(special_path):
		path = special_path
	if FileAccess.file_exists(eyes_path):
		path = eyes_path
	if not _manifests.has(path):
		_manifests[path] = _load_manifest(path)
	var entries: Dictionary = _manifests[path]
	root.set_meta("source_character_shading_surfaces", 0)
	if entries.is_empty() or DisplayServer.get_name() == "headless":
		return 0
	root.set_meta(
		"source_character_shading_contract",
		(
			"source-character-direct-v2"
			if path in [special_path, eyes_path]
			else "source-character-direct-v1"
		)
	)
	var count := _apply_recursive(root, entries, {})
	if path == eyes_path and not root.has_meta("source_eye_controller"):
		var controller := preload("res://scripts/characters/SourceCharacterEyes.gd").new()
		if controller.configure(root, scene_path):
			root.add_child(controller)
			root.set_meta("source_eye_controller", true)
		else:
			controller.free()
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
		if (
			not entry is Dictionary
			or (
				entry.get("render_contract")
				not in ["source-character-direct-v1", "source-character-direct-v2"]
			)
		):
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
			"F_ANISOTROPIC_GLOSS": ["g_tAnisoGloss"],
			"F_RETRO_REFLECTIVE": ["g_tMetalness"],
			"F_ANISOTROPIC_HAIR": ["g_tSssMask", "g_tAnisoGloss"],
			"F_EYEBALLS": ["g_tEyeAlbedo1", "g_tEyeMask1"]
		}
		for flag in required:
			if flag == "F_EYEBALLS" and not path.ends_with("source-character-eyes.json"):
				continue
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
	if textures.has("g_tMetalness"):
		result.set_shader_parameter("retro_texture", textures["g_tMetalness"])
	# Eye shading stays disabled until validated per-model bone calibration is bound.
	for binding in {"g_tEyeAlbedo1": "eye_albedo", "g_tEyeMask1": "eye_mask_texture"}:
		if textures.has(binding):
			result.set_shader_parameter(
				"eye_albedo" if binding == "g_tEyeAlbedo1" else "eye_mask_texture",
				textures[binding]
			)
	var eye_parameters := {
		"hue": "HueShift", "iris": "IrisSize", "pupil": "PupilSize", "saturation": "Saturation"
	}
	for parameter in eye_parameters:
		result.set_shader_parameter(
			"eye_" + parameter,
			float(
				floats.get(
					"g_flEye" + eye_parameters[parameter] + "1",
					1.0 if parameter in ["iris", "saturation"] else 0.0
				)
			)
		)
	result.set_shader_parameter("enable_retro", flags.get("F_RETRO_REFLECTIVE", 0) == 1)
	result.set_shader_parameter("enable_hair", flags.get("F_ANISOTROPIC_HAIR", 0) == 1)
	result.set_shader_parameter(
		"hair_roughness_scale", float(floats.get("g_flHairGlossRoughnessScale", 1.25))
	)
	result.set_shader_parameter("hair_shift", float(floats.get("g_flHairGlossShift", 0.3)))
	result.set_shader_parameter("hair_transmission", float(floats.get("g_flHairTransmission", 0.3)))
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
	# Verified against 86 native/converted bind-pose bones (max residual 4 um).
	# Source +X -> game -Z, Source +Y -> game -X, Source +Z -> game +Y.
	var pole := _vector(vectors.get("g_vSphericalAnisotropyPole", [0, 0, 1]))
	result.set_shader_parameter("aniso_pole", Vector3(-pole.y, pole.z, -pole.x))
	result.set_shader_parameter(
		"aniso_angle", float(floats.get("g_vSphericalAnisotropyAngle", 0.0))
	)
	result.set_meta("source_character_shading_applied", true)
	result.set_meta("source_material_parameters", native.duplicate(true))
	result.set_meta("source_features_pending", entry.get("pending_features", []).duplicate())
	return result


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
