extends RefCounted

const SHADER = preload("res://scripts/level/source_effect.gdshader")


static func apply(root: Node, manifest_path: String) -> void:
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or parsed.get("schema") != 1:
		return
	var materials: Dictionary = {}
	for entry in parsed.get("materials", []):
		if not entry is Dictionary or entry.get("source_shader") != "csgo_effects.vfx":
			continue
		var textures: Dictionary = {}
		for key in ["color_texture", "mask1", "mask2", "mask3"]:
			var path: String = entry.get(key, "")
			if path.begins_with("res://assets/local_reference/") and ResourceLoader.exists(path):
				textures[key] = load(path)
		if textures.size() != 4:
			continue
		var material := _make_material(entry, textures)
		if material != null:
			materials[material.resource_name] = material
	_apply_recursive(root, materials)


static func _make_material(entry: Dictionary, textures: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = entry.get("name", "")
	var shader: Shader = SHADER
	if bool(entry.get("additive", false)):
		shader = Shader.new()
		shader.code = SHADER.code.replace("blend_mix", "blend_add")
	material.shader = shader
	for key in textures:
		material.set_shader_parameter(key, textures[key])
	for index in range(1, 4):
		for suffix in ["scale", "pan"]:
			var key := "mask%d_%s" % [index, suffix]
			var value: Variant = entry.get(key, [1.0, 1.0] if suffix == "scale" else [0.0, 0.0])
			if not value is Array or value.size() != 2:
				return null
			if not (value[0] is float or value[0] is int) or not (value[1] is float or value[1] is int):
				return null
			material.set_shader_parameter(key, Vector2(value[0], value[1]))
	material.set_shader_parameter("opacity", float(entry.get("opacity", 1.0)))
	return material


static func _apply_recursive(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var original: Material = node.get_active_material(surface)
			if original != null and materials.has(original.resource_name):
				node.set_surface_override_material(surface, materials[original.resource_name])
	for child in node.get_children():
		_apply_recursive(child, materials)
