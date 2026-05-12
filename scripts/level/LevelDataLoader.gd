extends RefCounted

static func load_level(level_id: String) -> Dictionary:
	var path: String = "res://data/levels/%s.json" % level_id
	if not FileAccess.file_exists(path):
		push_error("Missing level data: %s" % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open level data: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON level payload: %s" % path)
		return {}

	return parsed as Dictionary
