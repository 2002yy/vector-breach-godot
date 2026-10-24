extends RefCounted

const VERSION := 1
const DIRECTORY := "res://assets/local_reference/collision_cache"


static func cache_path(source: String, directory := DIRECTORY) -> String:
	return directory.path_join(source.sha256_text() + ".res")


static func physical_path(resource: String) -> String:
	var path := ProjectSettings.globalize_path(resource)
	if resource.begins_with("res://") and not path.is_absolute_path():
		var base := OS.get_executable_path().get_base_dir()
		if OS.has_feature("editor"):
			# Editor-driven PCK validation has no source-project resource root.
			base = DirAccess.open(".").get_current_dir()
		return base.path_join(resource.trim_prefix("res://"))
	return path


static func signature(source: String) -> Dictionary:
	# The export keeps original bytes beside the PCK; do not hash remapped imports.
	var physical := physical_path(source)
	if not FileAccess.file_exists(physical) or not FileAccess.file_exists(physical + ".import"):
		return {}
	return {
		"version": VERSION,
		"source": source,
		"source_sha256": FileAccess.get_sha256(physical),
		"import_sha256": FileAccess.get_sha256(physical + ".import"),
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


static func _file_stamps(source: String, path: String) -> Dictionary:
	var stamps := {}
	var physical := physical_path(source)
	for file_path in [physical, physical + ".import", path, path + ".json"]:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			return {}
		stamps[file_path] = [file.get_length(), FileAccess.get_modified_time(file_path)]
	return stamps


static func verify_files(source: String, directory := DIRECTORY) -> Dictionary:
	var began := Time.get_ticks_usec()
	var path := physical_path(cache_path(source, directory))
	var proof := {
		"status": "missing", "source": source, "path": path, "engine": Engine.get_version_info().hex
	}
	var before := _file_stamps(source, path)
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".json"):
		return proof
	proof.status = "invalid"
	var file := FileAccess.open(path + ".json", FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return proof
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return proof
	var raw: Dictionary = parser.data
	var identity := signature(source)
	if identity.is_empty():
		return proof
	for key in identity:
		if raw.get(key) != identity[key]:
			return proof
	if raw.get("cache_sha256", "") != FileAccess.get_sha256(path):
		return proof
	proof["verify_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	if before.is_empty() or before != _file_stamps(source, path):
		return proof
	proof["source_sha256"] = identity.get("source_sha256", "")
	proof["cache_sha256"] = raw.get("cache_sha256", "")
	proof["import_sha256"] = identity.get("import_sha256", "")
	proof["stamps"] = before
	proof.status = "verified"
	return proof


static func shape_geometry(shape: ConcavePolygonShape3D) -> Array:
	return [shape.get_faces(), shape.backface_collision, shape.margin, shape.custom_solver_bias]


static func load_shapes(
	root: Node,
	source: String,
	receipt: Dictionary,
	directory := DIRECTORY,
	verified: Dictionary = {},
	retained: Dictionary = {}
) -> Dictionary:
	var began := Time.get_ticks_usec()
	var proof := verify_files(source, directory) if verified.is_empty() else verified
	receipt.clear()
	receipt["status"] = "missing" if proof.get("status") == "missing" else "invalid"
	if proof.get("status") != "verified":
		return {}
	var path := physical_path(cache_path(source, directory))
	if proof.get("source") != source or proof.get("path") != path:
		return {}
	if proof.get("engine") != Engine.get_version_info().hex:
		return {}
	if proof.get("stamps", {}).is_empty() or proof.stamps != _file_stamps(source, path):
		return {}
	if not verified.is_empty():
		# Bind the consumed payload/import bytes again; only large source hashing waits off-thread.
		if FileAccess.get_sha256(path) != proof.get("cache_sha256", ""):
			return {}
		if (
			FileAccess.get_sha256(physical_path(source) + ".import")
			!= proof.get("import_sha256", "")
		):
			return {}
	receipt["verify_ms"] = float(proof.get("verify_ms", 0.0))
	receipt["background_verified"] = not verified.is_empty()
	var phase := Time.get_ticks_usec()
	var reuse: bool = retained.get("valid", false) == true
	for key in ["source", "path", "engine", "source_sha256", "cache_sha256", "import_sha256"]:
		reuse = reuse and retained.get(key) == proof.get(key)
	if reuse:
		for key in retained.get("shapes", {}):
			var shape: Variant = retained.shapes[key]
			if (
				not shape is ConcavePolygonShape3D
				or retained.get("geometry", {}).get(key) != shape_geometry(shape)
			):
				reuse = false
				break
	var shapes: Variant
	var transforms: Variant
	if reuse:
		shapes = retained.get("shapes", {})
		transforms = retained.get("transforms", {})
	else:
		var payload := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
		if payload == null:
			return {}
		shapes = payload.get_meta("shapes", {})
		transforms = payload.get_meta("transforms", {})
	receipt["read_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	receipt["warm_reused"] = reuse
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
