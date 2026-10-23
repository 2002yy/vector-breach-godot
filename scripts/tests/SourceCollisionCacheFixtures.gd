extends RefCounted

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")
const DIRECTORY := "user://collision-cache-fixture"
const SOURCE := DIRECTORY + "/source.glb"


static func run(host: Node) -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_write(SOURCE, "fixture mesh source")
	_write(SOURCE + ".import", "fixture import options")
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "COLLISION_ONLY_Box"
	mesh.mesh = BoxMesh.new()
	mesh.position = Vector3(3, 0, 1)
	root.add_child(mesh)
	var receipt := {}
	host.call("_assert_true", Cache.bake(root, SOURCE, DIRECTORY), "bake fixture")
	var shapes := Cache.load_shapes(root, SOURCE, receipt, DIRECTORY)
	host.call("_assert_equal", receipt.status, "hit", "valid identity loads all cached shapes")
	host.call("_assert_equal", shapes.size(), 1, "exact shape count")
	var expected := mesh.mesh.create_trimesh_shape()
	host.call(
		"_assert_equal",
		shapes["COLLISION_ONLY_Box"].get_faces(),
		expected.get_faces(),
		"baked faces preserve exact source triangles"
	)
	mesh.position.x += 1.0
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"changed transform rejects entire cache"
	)
	mesh.position.x -= 1.0
	_write(SOURCE, "changed geometry source")
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"changed source rejects cache"
	)
	_write(SOURCE, "fixture mesh source")
	_write(SOURCE + ".import", "changed import options")
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"changed import options reject cache"
	)
	_write(SOURCE + ".import", "fixture import options")
	var path := Cache.cache_path(SOURCE, DIRECTORY)
	var original := FileAccess.get_file_as_string(path + ".json")
	var identity: Dictionary = JSON.parse_string(original)
	identity.engine = 0
	_write(path + ".json", JSON.stringify(identity))
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"changed engine rejects cache"
	)
	_write(path + ".json", "{malformed")
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"malformed receipt falls back silently"
	)
	identity = JSON.parse_string(original)
	identity.cache_sha256 = "wrong"
	_write(path + ".json", JSON.stringify(identity))
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"cache bytes must match receipt"
	)
	_write(path + ".json", original)
	root.remove_child(mesh)
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY).is_empty(),
		"no eligible meshes rejects entire cache"
	)
	root.add_child(mesh)
	var builder: Node3D = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
	host.add_child(root)
	var cached := Cache.load_shapes(root, SOURCE, receipt, DIRECTORY)
	host.call("_assert_equal", cached.size(), 1, "rejected receipts do not poison later valid load")
	builder.call("_build_runtime_collision_recursive", root, true, cached, root)
	host.call("_assert_true", mesh.mesh == null, "cached collision releases render mesh")
	var body := mesh.get_node("RuntimeCollision") as StaticBody3D
	host.call("_assert_equal", body.collision_layer, 1, "cached body keeps default collision layer")
	var shape := mesh.get_node("RuntimeCollision/CollisionShape3D") as CollisionShape3D
	host.call(
		"_assert_true",
		shape.shape == cached["COLLISION_ONLY_Box"],
		"builder reuses validated shape resource"
	)
	for frame in range(3):
		await host.get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(3, 2, 1), Vector3(3, -2, 1))
	var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
	host.call("_assert_true", hit.get("collider") == body, "cached shape blocks actual physics ray")
	root.free()
	builder.free()
	for file in [path, path + ".json", SOURCE, SOURCE + ".import"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(DIRECTORY)


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
