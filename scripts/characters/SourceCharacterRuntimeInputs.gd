extends Node
## Explicit candidate-only owner of one map's complete environment input set.

const Reflection = preload("res://scripts/level/SourceReflectionDiagnostic.gd")
const Probes = preload("res://scripts/level/SourceProbeDiagnostic.gd")
const Inputs = preload("res://scripts/characters/SourceEnvironmentInputs.gd")
const Indirect = preload("res://scripts/characters/SourceIndirectInputs.gd")
const Alignment = preload("res://scripts/level/SourceVisualAlignment.gd")
const Composite = preload("res://scripts/characters/SourceCharacterEnvironment.gd")
var reflection := Reflection.new()
var probes := Probes.new()
var inputs := Inputs.new()
var indirect := Indirect.new()
var configured := false
var level_id := ""
var _generation := 0
var _pending: Array[RefCounted] = []
var _characters: Array[RefCounted] = []


static func relative(path: Variant) -> bool:
	if not path is String or path.is_empty() or ":" in path or "\\" in path:
		return false
	for segment in path.split("/"):
		if segment in ["", ".", ".."]:
			return false
	return true


# gdlint: disable=max-returns
static func manifest_paths(data: Dictionary, level: Dictionary) -> Dictionary:
	var trace: Variant = level.get("sourceTrace")
	if not trace is Dictionary or not trace.get("vpkSha256") is String:
		return {}
	for field in ["contract", "purpose", "level", "vpk_sha256"]:
		if not data.get(field) is String:
			return {}
	if (
		not (data.get("schema") is int or data.get("schema") is float)
		or data.get("schema") != 1
		or data.get("contract") != "source-character-runtime-bundle-v1"
		or data.get("purpose") != "controlled-candidate"
		or not data.get("level") is String
		or data.get("level") != level.get("id")
		or data.get("vpk_sha256") != trace.vpkSha256
		or trace.vpkSha256.length() != 64
		or not trace.vpkSha256.is_valid_hex_number(false)
		or not data.get("files") is Array
		or data.files.size() < 7
		or data.files.size() > 16
		or not data.get("inputs") is Dictionary
	):
		return {}
	var files := {}
	var seen := []
	for row in data.files:
		if not row is Dictionary or not relative(row.get("path")):
			return {}
		if row.path.to_lower() in seen or not row.get("sha256") is String:
			return {}
		if (
			row.sha256.length() != 64
			or not row.sha256.is_valid_hex_number(false)
			or not (row.get("bytes") is int or row.get("bytes") is float)
			or not is_finite(row.bytes)
			or row.bytes != floorf(row.bytes)
			or row.bytes < 1
			or row.bytes > 1073741824
		):
			return {}
		files[row.path] = row
		seen.append(row.path.to_lower())
	for key in data.inputs:
		if key not in ["reflection", "lighting", "normalization", "indirect", "alignment"]:
			return {}
		if not relative(data.inputs[key]) or not files.has(data.inputs[key]):
			return {}
	for key in ["reflection", "lighting", "normalization", "indirect"]:
		if not data.inputs.has(key):
			return {}
	return data.inputs.duplicate()


static func inspect(path: String, level: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {}
	var roles := manifest_paths(data, level)
	if roles.is_empty():
		return {}
	var declared := {}
	for row in data.files:
		var file := path.get_base_dir().path_join(row.path)
		if not FileAccess.file_exists(file):
			return {}
		var stream := FileAccess.open(file, FileAccess.READ)
		if stream == null or stream.get_length() != row.bytes:
			return {}
		if FileAccess.get_sha256(file) != row.sha256:
			return {}
		declared[row.path] = true
	var documents := {}
	var result := {}
	for key in roles:
		result[key] = path.get_base_dir().path_join(roles[key])
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(result[key]))
		if not document is Dictionary:
			return {}
		documents[key] = document
	if documents.reflection.get("file") != "blocks/reflection.bc6h":
		return {}
	var dependencies := [
		roles.reflection.get_base_dir().path_join("blocks/reflection.bc6h"),
		roles.normalization.get_base_dir().path_join("brdf-rgba-f32.bin"),
	]
	var sources: Variant = documents.lighting.get("sources")
	if not sources is Dictionary:
		return {}
	for source in sources.values():
		if not source is Dictionary:
			return {}
		if source.has("decoded"):
			if not source.decoded is Dictionary or not relative(source.decoded.get("file")):
				return {}
			dependencies.append(roles.lighting.get_base_dir().path_join(source.decoded.file))
	for file in dependencies:
		if not declared.has(file):
			return {}
	return result


func clear() -> void:
	_generation += 1
	configured = false
	level_id = ""
	for character in _characters:
		character.detach()
	_characters.clear()
	for uploading in _pending:
		uploading.clear()
	_pending.clear()
	reflection.clear()
	reflection = Reflection.new()
	probes = Probes.new()
	inputs = Inputs.new()
	indirect = Indirect.new()


func configure(path: String, level: Dictionary, visual: Node, diagnostic := false) -> bool:
	clear()
	if not diagnostic or not is_inside_tree() or not is_instance_valid(visual):
		return false
	if not visual.is_inside_tree() or visual.get_viewport() != get_viewport():
		return false
	var paths := inspect(path, level)
	if paths.is_empty():
		return false
	var alignment := Alignment.resolve(visual, level, paths.get("alignment", ""))
	if not Probes.valid_alignment(alignment):
		return false
	var generation := _generation
	var candidate := Reflection.new()
	_pending.append(candidate)
	var uploaded := await candidate.configure(paths.reflection, level, alignment, true)
	_pending.erase(candidate)
	if not uploaded or generation != _generation or not is_instance_valid(visual):
		candidate.clear()
		return false
	if not visual.is_inside_tree() or visual.get_viewport() != get_viewport():
		candidate.clear()
		return false
	var candidate_probes := Probes.new()
	var candidate_inputs := Inputs.new()
	var candidate_indirect := Indirect.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(paths.reflection))
	if (
		not candidate_probes.configure(paths.lighting, level, alignment, true)
		or not candidate_inputs.configure(paths.normalization, data)
		or not candidate_indirect.configure(paths.indirect, paths.lighting)
	):
		candidate.clear()
		return false
	reflection = candidate
	probes = candidate_probes
	inputs = candidate_inputs
	indirect = candidate_indirect
	level_id = level.id
	configured = true
	return true


func track(character: RefCounted) -> void:
	for index in range(_characters.size() - 1, -1, -1):
		var alive := false
		for binding in _characters[index]._bindings:
			if is_instance_valid(binding.mesh):
				alive = true
				break
		if not alive:
			_characters[index].detach()
			_characters.remove_at(index)
	if configured and character not in _characters:
		_characters.append(character)


func attach_character(root: Node, body := true) -> RefCounted:
	if not configured:
		return null
	var character := Composite.new()
	if character.attach(root, reflection, probes, inputs, true, body) == 0:
		return null
	for material in character.materials:
		if not indirect.bind(material):
			character.detach()
			return null
	track(character)
	return character


func _exit_tree() -> void:
	clear()
