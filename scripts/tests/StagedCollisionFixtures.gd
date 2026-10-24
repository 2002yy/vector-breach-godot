extends RefCounted

const LevelScene = preload("res://scenes/level/GrayboxLevel.tscn")


class CachedLevel:
	extends "res://scripts/level/GrayboxLevel.gd"
	var fixture_cache: Dictionary = {}

	func _load_runtime_collision_cache(_root: Node, _release: bool, _source: String) -> Dictionary:
		return fixture_cache


class PipelineLevel:
	extends "res://scripts/level/GrayboxLevel.gd"
	var collision_path := ""

	func _begin_level(id: String, errors: bool, began: int) -> Dictionary:
		if id != "partial-collision-fixture":
			return super._begin_level(id, errors, began)
		_load_generation += 1
		load_count += 1
		last_load_timings = {"id": id, "success": false}
		return {"id": id, "runtime_collision_scene": collision_path, "visual_scene": collision_path}


static func run(host: Node) -> void:
	for options in [[false, true], [true, true], [false, false]]:
		await _equivalence(host, options[0], options[1])
	await _empty(host)
	await _cancel(host)
	await _pipeline_cancel(host)


static func _source() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, -40, 0)
	root.rotation.y = 0.2
	for index in range(3):
		var mesh := MeshInstance3D.new()
		mesh.name = "COLLISION_ONLY_%d" % index
		mesh.mesh = BoxMesh.new()
		mesh.position.x = index * 3.0
		root.add_child(mesh)
	return root


static func _equivalence(host: Node, cached: bool, release: bool) -> void:
	var builder = LevelScene.instantiate()
	builder.set_script(CachedLevel)
	builder.load_on_ready = false
	host.add_child(builder)
	var source := _source()
	builder.get_node("VisualRoot").add_child(source)
	var expected := {}
	for mesh in source.get_children():
		var shape: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
		expected[String(source.get_path_to(mesh))] = shape.get_faces()
		if cached:
			builder.fixture_cache[String(source.get_path_to(mesh))] = shape
	var complete := []
	_build(builder, source, complete, release)
	host.call(
		"_assert_equal",
		source.get_child(0).get_child_count(),
		1,
		"first collision registers before yielding"
	)
	host.call(
		"_assert_equal",
		source.get_child(1).get_child_count(),
		0,
		"later mesh waits for another frame"
	)
	while complete.is_empty():
		await host.get_tree().process_frame
	host.call("_assert_true", complete[0], "collision registration completes")
	host.call(
		"_assert_equal",
		builder.last_load_timings.collision_yielded_frames,
		3,
		"one frame per original collision mesh"
	)
	host.call(
		"_assert_equal",
		builder.last_load_timings.collision_mesh_count,
		3,
		"no original mesh omitted"
	)
	await host.get_tree().physics_frame
	for mesh in source.get_children():
		var body: StaticBody3D = mesh.get_node("RuntimeCollision")
		var shape: ConcavePolygonShape3D = mesh.get_node("RuntimeCollision/CollisionShape3D").shape
		host.call(
			"_assert_true",
			mesh.mesh == null if release else mesh.mesh != null,
			"mesh lifetime follows release policy"
		)
		host.call(
			"_assert_equal",
			shape.get_faces(),
			expected[String(source.get_path_to(mesh))],
			"exact original triangles preserved"
		)
		host.call("_assert_equal", body.collision_layer, 1, "original layer preserved")
		host.call("_assert_equal", body.collision_mask, 1, "original mask preserved")
		host.call("_assert_true", not shape.backface_collision, "backface policy preserved")
		if cached:
			host.call(
				"_assert_true",
				shape == builder.fixture_cache[String(source.get_path_to(mesh))],
				"validated shape resource reused"
			)
		var at: Vector3 = mesh.global_position
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2, at - Vector3.UP * 2)
		var hit: Dictionary = mesh.get_world_3d().direct_space_state.intersect_ray(query)
		host.call(
			"_assert_true",
			hit.get("collider") == body,
			"registered original transform blocks real ray"
		)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.2
		capsule.height = 1.0
		var overlap := PhysicsShapeQueryParameters3D.new()
		overlap.shape = capsule
		overlap.transform.origin = at + Vector3.UP * 0.5
		var intersections: Array = mesh.get_world_3d().direct_space_state.intersect_shape(overlap)
		host.call(
			"_assert_true", not intersections.is_empty(), "registered collision blocks capsule"
		)
	builder.free()
	await host.get_tree().physics_frame


static func _build(builder: Node, source: Node, completed: Array, release: bool = true) -> void:
	var ok: bool = await builder.call(
		"_build_runtime_collision_async", source, false, release, "", builder._load_generation
	)
	completed.append(ok)


static func _cancel(host: Node) -> void:
	var builder = LevelScene.instantiate()
	builder.load_on_ready = false
	host.add_child(builder)
	var source := _source()
	builder.get_node("VisualRoot").add_child(source)
	var completed := []
	_build(builder, source, completed)
	builder.call("load_level", "gatehouse", false)
	while completed.is_empty():
		await host.get_tree().process_frame
	host.call("_assert_true", not completed[0], "superseded collider loop stops")
	host.call(
		"_assert_equal",
		builder.last_load_timings.id,
		"gatehouse",
		"old collision receipt cannot overwrite new map"
	)
	builder.free()
	await host.get_tree().process_frame


static func _empty(host: Node) -> void:
	var builder = LevelScene.instantiate()
	builder.load_on_ready = false
	host.add_child(builder)
	var root := Node3D.new()
	builder.get_node("VisualRoot").add_child(root)
	var ok: bool = await builder.call(
		"_build_runtime_collision_async", root, false, true, "", builder._load_generation
	)
	host.call("_assert_true", ok, "empty dedicated layer completes")
	host.call(
		"_assert_equal",
		builder.last_load_timings.collision_yielded_frames,
		0,
		"empty layer does not yield"
	)
	builder.free()
	await host.get_tree().process_frame
	builder = LevelScene.instantiate()
	builder.load_on_ready = false
	host.add_child(builder)
	root = _source()
	builder.get_node("VisualRoot").add_child(root)
	builder.call("_build_runtime_collision_async", root, false, true, "", builder._load_generation)
	builder.free()
	for frame in range(3):
		await host.get_tree().physics_frame
	var anchor := Node3D.new()
	host.add_child(anchor)
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, -38, 0), Vector3(0, -42, 0))
	var hit: Dictionary = anchor.get_world_3d().direct_space_state.intersect_ray(query)
	host.call("_assert_true", hit.is_empty(), "destroyed owner leaves no partial collision bodies")
	anchor.free()


static func _pipeline_cancel(host: Node) -> void:
	var path := "user://staged-collision-pipeline-%d.tscn" % Time.get_ticks_usec()
	var root := _source()
	for child in root.get_children():
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
	packed = null
	var builder = LevelScene.instantiate()
	builder.set_script(PipelineLevel)
	builder.load_on_ready = false
	builder.collision_path = path
	host.add_child(builder)
	var reader := host.get_node("/root/SceneReader")
	var before: int = reader.submitted_count
	builder.call("load_level_async", "partial-collision-fixture", false)
	host.call(
		"_assert_equal",
		reader.submitted_count,
		before,
		"partial collision cannot start visual read"
	)
	builder.call("load_level", "gatehouse", false)
	for frame in range(4):
		await host.get_tree().process_frame
	host.call(
		"_assert_equal",
		reader.submitted_count,
		before,
		"cancelled collision never submits old visual read"
	)
	host.call(
		"_assert_equal",
		builder.last_load_timings.id,
		"gatehouse",
		"async pipeline preserves new map receipt"
	)
	builder.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
