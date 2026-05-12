extends RefCounted

static func load_level(level_id: String, emit_errors: bool = true) -> Dictionary:
	var path: String = "res://data/levels/%s.json" % level_id
	if not FileAccess.file_exists(path):
		if emit_errors:
			push_error("Missing level data: %s" % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if emit_errors:
			push_error("Unable to open level data: %s" % path)
		return {}

	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if parse_error != OK:
		if emit_errors:
			push_error("Invalid JSON level payload: %s" % path)
		return {}

	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		if emit_errors:
			push_error("Invalid JSON level payload: %s" % path)
		return {}

	return parsed as Dictionary
