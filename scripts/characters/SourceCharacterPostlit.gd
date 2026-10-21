extends RefCounted

const POSTLIT = preload("res://scripts/characters/character_probe_postlit.gdshader")
const SurfaceFollower = preload("res://scripts/characters/PostlitSurfaceFollower.gd")
var _adapter: RefCounted
var _entries: Dictionary = {}
var _options: Dictionary = {}
var _bindings: Array = []


# Fail closed at each independent diagnostic input boundary.
# gdlint: disable=max-returns
func configure(adapter: RefCounted, manifest: String, options: Dictionary = {}) -> bool:
	detach()
	_adapter = null
	_entries.clear()
	_options.clear()
	if not context_valid(options) or adapter == null or not adapter.has_method("bind"):
		return false
	if not FileAccess.file_exists(manifest):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if (
		not data is Dictionary
		or data.get("schema") != 1
		or data.get("contract") != "source-character-contrast-inputs-v1"
	):
		return false
	var materials := manifest.get_base_dir().path_join("source-materials.json")
	if (
		not FileAccess.file_exists(materials)
		or FileAccess.get_sha256(materials) != data.get("materials_manifest_sha256")
	):
		return false
	if not data.get("materials") is Array:
		return false
	for entry in data.materials:
		if entry is Dictionary and entry.get("name") is String:
			if _entries.has(entry.name):
				_entries.clear()
				return false
			_entries[entry.name] = entry
	_adapter = adapter
	_options = options.duplicate(true)
	return not _entries.is_empty()


# gdlint: enable=max-returns
static func context_valid(options: Dictionary) -> bool:
	if (
		options.get("purpose") != "diagnostic"
		or options.get("accept_average_candidate") != true
		or options.get("fog_input_kind") != "diagnostic-constant"
	):
		return false
	for name in ["strength", "fog_modification"]:
		var value: Variant = options.get(name)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0:
			return false
	return options.strength <= 0.8 and options.fog_modification <= 1.0


func attach(root: Node) -> int:
	if _adapter == null:
		return 0
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if (
			mesh.has_meta("source_postlit_surface")
			or not mesh.mesh is ArrayMesh
			or mesh.material_overlay != null
			or mesh.material_override != null
		):
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var attached := false
			for binding in _bindings:
				if binding.mesh == mesh and binding.surface == surface:
					attached = true
			if attached:
				continue
			var original := mesh.get_active_material(surface) as ShaderMaterial
			if original == null or original.next_pass != null:
				continue
			var entry: Dictionary = _entries.get(original.resource_name, {})
			if not _entry_valid(original, entry):
				continue
			var pass_material := _material(original, entry)
			if not _adapter.bind(pass_material):
				continue
			# Keep the live base material in place. Each auxiliary draw uses the
			# original surface arrays and the same skeleton/skin, including weights.
			var geometry := ArrayMesh.new()
			for index in range(mesh.mesh.get_blend_shape_count()):
				geometry.add_blend_shape(mesh.mesh.get_blend_shape_name(index))
			geometry.blend_shape_mode = mesh.mesh.blend_shape_mode
			geometry.add_surface_from_arrays(
				mesh.mesh.surface_get_primitive_type(surface),
				mesh.mesh.surface_get_arrays(surface),
				mesh.mesh.surface_get_blend_shape_arrays(surface),
				{},
				mesh.mesh.surface_get_format(surface)
			)
			var proxy := SurfaceFollower.new()
			proxy.name = "PostlitSurface" + str(surface)
			proxy.set_meta("source_postlit_surface", true)
			proxy.mesh = geometry
			proxy.material_override = pass_material
			proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			proxy.layers = mesh.layers
			mesh.add_child(proxy)
			var skeleton := mesh.get_node_or_null(mesh.skeleton)
			if mesh.skin != null and skeleton != null:
				proxy.skin = mesh.skin
				proxy.skeleton = proxy.get_path_to(skeleton)
			_bindings.append({"mesh": mesh, "surface": surface, "proxy": proxy})
			count += 1
	return count


func detach() -> void:
	for entry in _bindings:
		if is_instance_valid(entry.proxy):
			entry.proxy.hide()
			if entry.proxy.get_parent() != null:
				entry.proxy.get_parent().remove_child(entry.proxy)
			entry.proxy.queue_free()
	_bindings.clear()


# gdlint: disable=max-returns
static func _entry_valid(original: ShaderMaterial, entry: Dictionary) -> bool:
	var tint: Variant = original.get_shader_parameter("base_color")
	if not tint is Color and not tint is Vector4:
		return false
	if (
		not original.get_shader_parameter("uv_scale") is Vector3
		or not original.get_shader_parameter("uv_offset") is Vector3
	):
		return false
	if not original.get_shader_parameter("use_base") is bool:
		return false
	if (
		entry.get("average_basis") != "vtex-reflectivity-candidate"
		or entry.get("native_material", {}) != original.get_meta("source_material_parameters", {})
	):
		return false
	var average: Variant = entry.get("reflectivity_rgba")
	if not average is Array or average.size() != 4:
		return false
	for value in average:
		if (
			not (value is int or value is float)
			or not is_finite(float(value))
			or float(value) < 0
			or float(value) > 1
		):
			return false
	var native: Dictionary = entry.native_material
	var flags: Dictionary = native.get("IntParams", {})
	if flags.get("F_TRANSLUCENT", 0) != 0:
		return false
	var exposure := float(native.get("FloatParams", {}).get("g_fDistanceContrastExposure", 0.6))
	return is_finite(exposure) and exposure >= 0 and exposure <= 1


# gdlint: enable=max-returns
func _material(original: ShaderMaterial, entry: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = POSTLIT
	for mode in ["cull_disabled", "cull_front"]:
		if original.shader.code.contains(mode):
			var variant := POSTLIT.duplicate() as Shader
			variant.code = variant.code.replace("cull_back", mode)
			result.shader = variant
	result.render_priority = -127
	var tint: Variant = original.get_shader_parameter("base_color")
	var color := (
		Vector3(tint.r, tint.g, tint.b) if tint is Color else Vector3(tint.x, tint.y, tint.z)
	)
	result.set_shader_parameter("surface_albedo", color)
	for pair in [
		["use_surface_texture", "use_base"],
		["surface_texture", "base_texture"],
		["surface_uv_scale", "uv_scale"],
		["surface_uv_offset", "uv_offset"]
	]:
		result.set_shader_parameter(pair[0], original.get_shader_parameter(pair[1]))
	var average: Array = entry.reflectivity_rgba
	result.set_shader_parameter("average_albedo", Vector3(average[0], average[1], average[2]))
	var native: Dictionary = entry.native_material
	result.set_shader_parameter(
		"source_exposure",
		1.0 - float(native.get("FloatParams", {}).get("g_fDistanceContrastExposure", 0.6))
	)
	result.set_shader_parameter(
		"material_adjustment",
		native.get("IntParams", {}).get("F_DISTANCE_CONTRAST_ADJUSTMENT", 0) == 1
	)
	result.set_shader_parameter("contrast_strength", float(_options.strength))
	result.set_shader_parameter("fog_modification", float(_options.fog_modification))
	result.set_shader_parameter("inputs_ready", true)
	return result
