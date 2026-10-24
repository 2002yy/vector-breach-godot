extends RefCounted

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")


class Waiter:
	extends Node
	var result: Dictionary = {}
	var finished := false

	func start(source: String, directory: String) -> void:
		result = await get_node("/root/CollisionVerifier").verify(source, directory)
		finished = true


static func run(host: Node) -> void:
	var directory := "user://collision-verifier-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var source := directory.path_join("fixture.glb")
	_write(source, "fixture geometry")
	_write(source + ".import", "fixture import")
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "COLLISION_ONLY_Fixture"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	host.call("_assert_true", Cache.bake(root, source, directory), "bake valid fixture")
	var verifier := host.get_node("/root/CollisionVerifier")
	var first := Waiter.new()
	var second := Waiter.new()
	var abandoned := Waiter.new()
	for waiter in [first, second, abandoned]:
		host.add_child(waiter)
		waiter.start(source, directory)
	host.call("_assert_equal", verifier.pending_count(), 1, "same input coalesces verification")
	abandoned.free()
	while not first.finished or not second.finished:
		await host.get_tree().process_frame
	host.call(
		"_assert_equal", first.result.status, "verified", "worker hashes full source and cache"
	)
	host.call("_assert_equal", verifier.pending_count(), 0, "worker task is joined and removed")
	var proof: Dictionary = first.result.duplicate(true)
	first.result.status = "modified client"
	host.call("_assert_equal", second.result.status, "verified", "receipts are independent")
	var receipt := {}
	var shapes := Cache.load_shapes(root, source, receipt, directory, proof)
	host.call(
		"_assert_equal",
		receipt.status,
		"hit",
		"verified files still require main-thread shape validation"
	)
	host.call("_assert_true", receipt.background_verified, "background receipt is explicit")
	host.call("_assert_equal", shapes.size(), 1, "complete original shape returned")
	mesh.position.x = 1.0
	host.call(
		"_assert_true",
		Cache.load_shapes(root, source, receipt, directory, proof).is_empty(),
		"transform change rejects preverified payload"
	)
	mesh.position.x = 0.0
	var wrong: Dictionary = proof.duplicate(true)
	wrong.source = "wrong source"
	host.call(
		"_assert_true",
		Cache.load_shapes(root, source, receipt, directory, wrong).is_empty(),
		"proof cannot move to another source"
	)
	wrong = proof.duplicate(true)
	wrong.engine = 0
	host.call(
		"_assert_true",
		Cache.load_shapes(root, source, receipt, directory, wrong).is_empty(),
		"wrong engine proof rejected"
	)
	var cache_path := Cache.cache_path(source, directory)
	var original_bytes := FileAccess.get_file_as_bytes(cache_path)
	var altered := original_bytes.duplicate()
	altered[altered.size() - 1] = int(altered[altered.size() - 1]) ^ 1
	var cache_file := FileAccess.open(cache_path, FileAccess.WRITE)
	cache_file.store_buffer(altered)
	cache_file.close()
	host.call(
		"_assert_true",
		Cache.load_shapes(root, source, receipt, directory, proof).is_empty(),
		"same-size cache changes are rejected before decoding"
	)
	cache_file = FileAccess.open(cache_path, FileAccess.WRITE)
	cache_file.store_buffer(original_bytes)
	cache_file.close()
	_write(source + ".import", "Fixture import")
	host.call(
		"_assert_true",
		Cache.load_shapes(root, source, receipt, directory, proof).is_empty(),
		"same-size import changes reject old proof"
	)
	_write(source + ".import", "fixture import")
	_write(source, "changed source with another size")
	host.call(
		"_assert_true",
		Cache.load_shapes(root, source, receipt, directory, proof).is_empty(),
		"changed source stamps reject proof"
	)
	var invalid: Dictionary = await verifier.verify(source, directory)
	host.call(
		"_assert_equal",
		invalid.status,
		"invalid",
		"later request rehashes source and rejects stale identity"
	)
	var missing: Dictionary = await verifier.verify(source, "user://missing-verifier-directory")
	host.call("_assert_equal", missing.status, "missing", "missing receipt fails safely")
	first.free()
	second.free()
	root.free()
	var path := Cache.cache_path(source, directory)
	for file in [source, source + ".import", path, path + ".json"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)


static func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
