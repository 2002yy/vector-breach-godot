extends RefCounted

const Reflection = preload("res://scripts/level/SourceReflectionTexture.gd")
var harmonics: Array = []


static func valid(data: Dictionary, lighting: Dictionary, lighting_sha: String) -> bool:
	if not data.get("source_trace") is Dictionary or not lighting.get("source_trace") is Dictionary:
		return false
	for field in ["contract", "kind", "level", "lighting_sha256"]:
		if not data.get(field) is String:
			return false
	if (
		not lighting.get("level") is String
		or not (data.get("schema") is int or data.get("schema") is float)
	):
		return false
	if (
		data.get("schema") != 1
		or data.get("contract") != "source-indirect-diagnostic-v1"
		or data.get("kind") != "viewer-derived-source-sun-SH1"
		or data.get("level") != lighting.get("level")
		or data.get("source_trace") != lighting.get("source_trace")
		or data.get("lighting_sha256") != lighting_sha
		or not data.get("ambient_sh") is Array
		or data.ambient_sh.size() != 3
	):
		return false
	for row in data.ambient_sh:
		if not row is Array or row.size() != 4:
			return false
		for value in row:
			if not (value is int or value is float) or not is_finite(value):
				return false
	return true


func configure(path: String, lighting_path: String) -> bool:
	harmonics.clear()
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(lighting_path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var lighting: Variant = JSON.parse_string(FileAccess.get_file_as_string(lighting_path))
	if not data is Dictionary or not lighting is Dictionary:
		return false
	if not valid(data, lighting, FileAccess.get_sha256(lighting_path)):
		return false
	harmonics = data.ambient_sh.duplicate(true)
	return true


func bind(material: ShaderMaterial) -> bool:
	if harmonics.size() != 3:
		return false
	for c in range(3):
		var row: Array = harmonics[c]
		material.set_shader_parameter(
			"source_ambient_sh_" + ["r", "g", "b"][c], Vector4(row[0], row[1], row[2], row[3])
		)
	material.set_shader_parameter("source_indirect_enabled", true)
	return true
