extends RefCounted

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")
const DIRECTORY := "user://warm-collision-fixture"
const SOURCE := DIRECTORY + "/source.glb"


static func run(host: Node) -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_write(SOURCE, "warm fixture source")
	_write(SOURCE + ".import", "warm fixture import")
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "COLLISION_ONLY_Box"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var level: Node = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.load_on_ready = false
	host.add_child(level)
	host.call("_assert_true", Cache.bake(root, SOURCE, DIRECTORY), "bake warm fixture")
	var receipt := {}
	var proof := Cache.verify_files(SOURCE, DIRECTORY)
	var shapes := Cache.load_shapes(root, SOURCE, receipt, DIRECTORY, proof)
	level.call("_replace_collision_lease", root, shapes, proof)
	var warm := Cache.load_shapes(root, SOURCE, receipt, DIRECTORY, proof, level._collision_lease)
	host.call("_assert_true", receipt.warm_reused, "matching fresh proof reuses live shapes")
	host.call("_assert_true", warm[mesh.name] == shapes[mesh.name], "same native shape survives")
	var node := CollisionShape3D.new()
	node.shape = shapes[mesh.name]
	host.call(
		"_assert_true", level._collision_lease.valid, "node assignment keeps unchanged geometry"
	)
	node.free()
	mesh.position.x = 1.0
	host.call(
		"_assert_true",
		(
			Cache
			. load_shapes(root, SOURCE, receipt, DIRECTORY, proof, level._collision_lease)
			. is_empty()
		),
		"warm path still verifies mesh transforms"
	)
	mesh.position.x = 0.0
	var other := proof.duplicate(true)
	other.source_sha256 = "different identity"
	level.call("_replace_collision_lease", root, shapes, other)
	warm = Cache.load_shapes(root, SOURCE, receipt, DIRECTORY, proof, level._collision_lease)
	host.call("_assert_true", not receipt.warm_reused, "identity mismatch reads original cache")
	host.call("_assert_true", warm[mesh.name] != shapes[mesh.name], "no stale resource reuse")
	level.call("_replace_collision_lease", root, shapes, proof)
	var original: PackedVector3Array = shapes[mesh.name].get_faces()
	shapes[mesh.name].set_faces(PackedVector3Array())
	host.call("_assert_true", not level._collision_lease.valid, "shape mutation invalidates lease")
	warm = Cache.load_shapes(root, SOURCE, receipt, DIRECTORY, proof, level._collision_lease)
	host.call("_assert_true", not receipt.warm_reused, "mutated shape cannot be reused")
	host.call("_assert_equal", warm[mesh.name].get_faces(), original, "original triangles restored")
	level.call("_replace_collision_lease", root, warm, proof)
	var original_margin: float = warm[mesh.name].margin
	warm[mesh.name].margin += 0.1
	warm = Cache.load_shapes(root, SOURCE, receipt, DIRECTORY, proof, level._collision_lease)
	host.call(
		"_assert_true", not receipt.warm_reused, "silent physical margin change rejects reuse"
	)
	host.call("_assert_equal", warm[mesh.name].margin, original_margin, "original margin restored")
	level.call("_replace_collision_lease", root, warm, proof)
	_write(SOURCE + ".import", "modified import options")
	host.call(
		"_assert_true",
		Cache.load_shapes(root, SOURCE, receipt, DIRECTORY, {}, level._collision_lease).is_empty(),
		"fresh verification rejects changed input despite retained shape"
	)
	_write(SOURCE + ".import", "warm fixture import")
	level._current_level_data = {"id": "depot"}
	level.call("_begin_level", "depot", false, Time.get_ticks_usec())
	host.call("_assert_true", not level._collision_lease.is_empty(), "same map retains lease")
	level.call("_begin_level", "missing-warm-fixture", false, Time.get_ticks_usec())
	host.call("_assert_true", level._collision_lease.is_empty(), "map change clears lease")
	level.call("_replace_collision_lease", root, warm, proof)
	level.load_level("missing-warm-fixture", false)
	host.call("_assert_true", level._collision_lease.is_empty(), "sync load clears lease")
	level.call("_replace_collision_lease", root, warm, proof)
	var resource_ref: WeakRef = weakref(warm[mesh.name])
	warm = {}
	host.remove_child(level)
	host.call("_assert_true", level._collision_lease.is_empty(), "exit clears all retained shapes")
	host.call("_assert_true", resource_ref.get_ref() == null, "exit releases final resource owner")
	level.free()
	root.free()
	var path := Cache.cache_path(SOURCE, DIRECTORY)
	for file in [path, path + ".json", SOURCE, SOURCE + ".import"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(DIRECTORY)
	await host.get_tree().process_frame


static func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
