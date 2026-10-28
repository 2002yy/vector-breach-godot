extends RefCounted
## Local derived collision topology. Missing/invalid atlases leave legacy radar intact.

const ROOT := "res://assets/local_reference/radar/"
const LEVELS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]

var level_id := ""
var status := "unloaded"
var manifest: Dictionary = {}
var directory := ""
var active_layer := -1
var textures: Dictionary = {}
var verification := Thread.new()


static func valid_manifest(data: Dictionary, expected_level: String) -> bool:
	if int(data.get("schema", 0)) != 1 or String(data.get("level", "")) != expected_level:
		return false
	for key in ["source_sha256", "source_import_sha256", "level_sha256"]:
		if String(data.get(key, "")).length() != 64:
			return false
	var rect: Array = data.get("world_rect", [])
	if rect.size() != 4:
		return false
	for value in rect:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	if float(rect[2]) <= 0.0 or float(rect[3]) <= 0.0:
		return false
	var layers: Array = data.get("layers", [])
	if layers.is_empty() or layers.size() > 32:
		return false
	var previous := -INF
	for layer in layers:
		if not layer is Dictionary:
			return false
		var height = layer.get("height", null)
		if not (height is float or height is int) or not is_finite(float(height)):
			return false
		if float(height) <= previous:
			return false
		previous = float(height)
		var filename := String(layer.get("texture", ""))
		if filename.get_file() != filename or not filename.ends_with(".png"):
			return false
		if String(layer.get("sha256", "")).length() != 64:
			return false
	return true


func load_level(requested: String) -> bool:
	if requested == level_id:
		_poll_identity()
		return status == "ready"
	level_id = requested
	manifest.clear()
	textures.clear()
	active_layer = -1
	status = "no_local_atlas"
	if requested not in LEVELS:
		return false
	directory = ROOT + requested + "/v4/"
	var path := directory + "atlas.json"
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not valid_manifest(parsed, requested):
		status = "invalid_atlas"
		return false
	var source := String(parsed.get("source", ""))
	var level_path := "res://data/levels/" + requested + ".json"
	var level_data = JSON.parse_string(FileAccess.get_file_as_string(level_path))
	if (
		not level_data is Dictionary
		or not source.begins_with("res://assets/")
		or source != String(level_data.get("runtime_collision_scene", ""))
		or not FileAccess.file_exists(source)
		or not import_identity_matches(parsed, FileAccess.get_sha256(source + ".import"))
		or FileAccess.get_sha256(level_path) != String(parsed.get("level_sha256", ""))
	):
		status = "source_identity_mismatch"
		return false
	manifest = parsed
	status = "verifying_source"
	_poll_identity()
	return status == "ready"


static func import_identity_matches(data: Dictionary, import_sha256: String) -> bool:
	return (
		import_sha256.length() == 64
		and String(data.get("source_import_sha256", "")) == import_sha256
	)


static func _source_identity(source: String, expected_level: String) -> Dictionary:
	return {"level": expected_level, "sha256": FileAccess.get_sha256(source)}


func _poll_identity() -> void:
	if status != "verifying_source":
		return
	if verification.is_started():
		if verification.is_alive():
			return
		var proof: Dictionary = verification.wait_to_finish()
		if String(proof.level) == level_id:
			var matched: bool = proof.sha256 == manifest.source_sha256
			matched = (
				matched
				and import_identity_matches(
					manifest, FileAccess.get_sha256(String(manifest.source) + ".import")
				)
			)
			status = "ready" if matched else "source_identity_mismatch"
			return
	# A map switch may happen while the previous map's worker is finishing.
	verification.start(_source_identity.bind(String(manifest.source), level_id))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and verification.is_started():
		verification.wait_to_finish()


static func nearest_layer(layers: Array, height: float, previous := -1) -> int:
	if not is_finite(height) or layers.is_empty():
		return -1
	var chosen := 0
	for index in range(1, layers.size()):
		if absf(float(layers[index].height) - height) < absf(float(layers[chosen].height) - height):
			chosen = index
	# Keep the present slice near a transition, rather than flickering on stairs.
	if previous >= 0 and previous < layers.size():
		if (
			absf(float(layers[previous].height) - height)
			<= absf(float(layers[chosen].height) - height) + 0.25
		):
			chosen = previous
	return chosen if absf(float(layers[chosen].height) - height) <= 2.5 else -1


func select_layer(feet_height: float) -> Dictionary:
	if status != "ready":
		return {}
	var selected := nearest_layer(manifest.layers, feet_height, active_layer)
	if selected < 0:
		return {}
	active_layer = selected
	if not textures.has(selected):
		var layer: Dictionary = manifest.layers[selected]
		var path := directory + String(layer.texture)
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != String(layer.sha256):
			status = "texture_identity_mismatch"
			return {}
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			status = "texture_unreadable"
			return {}
		# Bound decoded texture memory to two slices per active map.
		if textures.size() >= 2:
			textures.erase(textures.keys()[0])
		textures[selected] = ImageTexture.create_from_image(image)
	return {
		"texture": textures[selected],
		"world_rect": manifest.world_rect,
		"height": float(manifest.layers[selected].height),
		"layer_index": selected,
		"layer_count": manifest.layers.size(),
	}


static func world_uv(point: Vector2, rect: Array) -> Vector2:
	return Vector2(
		(point.x - float(rect[0])) / float(rect[2]), (point.y - float(rect[1])) / float(rect[3])
	)


static func floor_sample(
	previous: float, feet_height: float, grounded: bool, level_changed: bool
) -> float:
	return feet_height if grounded or level_changed else previous
