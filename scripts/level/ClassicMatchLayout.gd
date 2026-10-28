extends RefCounted

const ExportIdentity = preload("res://scripts/level/ExportedLayoutIdentity.gd")

const AUTHORED_PATH := "res://data/levels/match-local/dustline.json"


static func input_stamps(data: Dictionary, manifest_path: String = AUTHORED_PATH) -> Dictionary:
	manifest_path = String(data.get("match_manifest", manifest_path))
	var collision := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	var level := "res://data/levels/%s.json" % String(data.get("id", ""))
	var result := {}
	var paths: Array = [manifest_path, collision, level]
	if not FileAccess.file_exists(collision):
		paths = ExportIdentity.input_paths(data, manifest_path)
		if paths.is_empty():
			return {}
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {}
		result[path] = [file.get_length(), FileAccess.get_modified_time(path)]
		file.close()
	return result


# Runtime consumes frozen local JSON. Only the explicit authoring tool scans
# collision; asset/data changes invalidate this baseline instead of moving routes.
static func load_authored(data: Dictionary, manifest_path: String = AUTHORED_PATH) -> Dictionary:
	manifest_path = String(data.get("match_manifest", manifest_path))
	if not FileAccess.file_exists(manifest_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		return {}
	var manifest: Dictionary = parsed
	var collision_path := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	var level_path := "res://data/levels/%s.json" % String(data.get("id", ""))
	var level_hashes: Dictionary = manifest.get("level_sha256", {})
	if manifest.get("schema", 0) != 1 or manifest.get("collision_path", "") != collision_path:
		return {}
	var collision_hash := (
		FileAccess.get_sha256(collision_path) if FileAccess.file_exists(collision_path) else ""
	)
	if not ExportIdentity.collision_matches(data, manifest, manifest_path, collision_hash):
		return {}
	var level_hash := FileAccess.get_sha256(level_path)
	if level_hash.is_empty() or level_hash != String(level_hashes.get(level_path, "")):
		return {}
	var layout: Dictionary = manifest.get("layout", {})
	var graph: Dictionary = layout.get("navigationGraph", {})
	var spawns: Dictionary = layout.get("matchSpawns", {})
	if (
		(graph.get("points", []) as Array).is_empty()
		or (graph.get("links", []) as Array).is_empty()
	):
		return {}
	if (layout.get("objectives", []) as Array).size() != 2:
		return {}
	if (spawns.get("T", []) as Array).size() != 5 or (spawns.get("CT", []) as Array).size() != 5:
		return {}
	return layout.duplicate(true)
