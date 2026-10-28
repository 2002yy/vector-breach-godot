extends RefCounted
## Build consistency proof for frozen routes when source GLB bytes are not exported.


static func input_paths(data: Dictionary, manifest_path: String) -> Array:
	var source := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	var receipt_path := manifest_path + ".export.json"
	var sidecar := source + ".import"
	if not FileAccess.file_exists(receipt_path) or not FileAccess.file_exists(sidecar):
		return []
	var receipt = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	var config := ConfigFile.new()
	if not receipt is Dictionary or config.load(sidecar) != OK:
		return []
	var compiled := String(config.get_value("remap", "path", ""))
	if (
		not compiled.begins_with("res://.godot/imported/")
		or compiled.contains("..")
		or not compiled.ends_with(".scn")
		or receipt.get("compiled", "") != compiled
		or not FileAccess.file_exists(compiled)
	):
		return []
	return [
		manifest_path,
		"res://data/levels/%s.json" % String(data.get("id", "")),
		receipt_path,
		sidecar,
		compiled
	]


static func collision_matches(
	data: Dictionary, manifest: Dictionary, manifest_path: String, raw_hash: String
) -> bool:
	var source := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	if FileAccess.file_exists(source):
		return not raw_hash.is_empty() and raw_hash == String(manifest.get("collision_sha256", ""))
	var paths := input_paths(data, manifest_path)
	if paths.is_empty():
		return false
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(paths[2]))
	var expected := {
		"schema": 1,
		"source": source,
		"source_sha256": String(manifest.get("collision_sha256", "")),
		"manifest_sha256": FileAccess.get_sha256(manifest_path),
		"level_sha256": FileAccess.get_sha256(paths[1]),
		"shipped_import_sha256": FileAccess.get_sha256(paths[3]),
		"compiled_sha256": FileAccess.get_sha256(paths[4])
	}
	for key in expected:
		if receipt.get(key, null) != expected[key]:
			return false
	return String(expected.source_sha256).length() == 64
