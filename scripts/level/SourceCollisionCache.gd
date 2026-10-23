extends RefCounted

const VERSION := 1
const DIRECTORY := "res://assets/local_reference/collision_cache"


static func cache_path(source: String, directory := DIRECTORY) -> String:
	return directory.path_join(source.sha256_text() + ".res")


static func signature(source: String) -> Dictionary:
	if not FileAccess.file_exists(source) or not FileAccess.file_exists(source + ".import"):
		return {}
	return {
		"version": VERSION,
		"source": source,
		"source_sha256": FileAccess.get_sha256(source),
		"import_sha256": FileAccess.get_sha256(source + ".import"),
		"engine": Engine.get_version_info().hex,
	}


static func meshes(root: Node) -> Dictionary:
	var found := {}
	_collect(root, root, found)
	return found


static func _collect(root: Node, node: Node, found: Dictionary) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("COLLISION_"):
		if node.mesh != null:
			found[String(root.get_path_to(node))] = node
	for child in node.get_children():
		_collect(root, child, found)


static func bake(root: Node, source: String, directory := DIRECTORY) -> bool:
	var identity := signature(source)
	if identity.is_empty():
		return false
	var shapes := {}
	var transforms := {}
	for path in meshes(root):
		var node := root.get_node(path) as MeshInstance3D
		var shape := node.mesh.create_trimesh_shape()
		if shape == null:
			return false
		shapes[path] = shape
		transforms[path] = node.transform
	if shapes.is_empty():
		return false
	var payload := Resource.new()
	payload.set_meta("shapes", shapes)
	payload.set_meta("transforms", transforms)
	var path := cache_path(source, directory)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	# Publish the receipt last: interrupted writes cannot qualify a partial cache.
	if ResourceSaver.save(payload, path, ResourceSaver.FLAG_COMPRESS) != OK:
		return false
	identity["cache_sha256"] = FileAccess.get_sha256(path)
	var file := FileAccess.open(path + ".json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(identity, "\t"))
	file.close()
	return true


static func load_shapes(
	root: Node, source: String, receipt: Dictionary, directory := DIRECTORY
) -> Dictionary:
	var began := Time.get_ticks_usec()
	receipt.clear()
	receipt["status"] = "missing"
	var path := cache_path(source, directory)
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".json"):
		return {}
	receipt.status = "invalid"
	var file := FileAccess.open(path + ".json", FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var raw: Dictionary = parser.data
	var identity := signature(source)
	if identity.is_empty():
		return {}
	for key in identity:
		if raw.get(key) != identity[key]:
			return {}
	if raw.get("cache_sha256", "") != FileAccess.get_sha256(path):
		return {}
	receipt["verify_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	var phase := Time.get_ticks_usec()
	var payload := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	receipt["read_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	if payload == null:
		return {}
	var shapes: Variant = payload.get_meta("shapes", {})
	var transforms: Variant = payload.get_meta("transforms", {})
	if not shapes is Dictionary or not transforms is Dictionary:
		return {}
	var expected := meshes(root)
	if expected.is_empty() or shapes.size() != expected.size():
		return {}
	for key in expected:
		var shape: Variant = shapes.get(key)
		if not shape is ConcavePolygonShape3D or shape.backface_collision:
			return {}
		if transforms.get(key) != expected[key].transform:
			return {}
	receipt.status = "hit"
	receipt["shape_count"] = shapes.size()
	receipt["total_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	return shapes
