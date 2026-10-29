extends SceneTree
## Authoring experiment only: preserve every triangle, vertex value and winding.

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")


func _initialize() -> void:
	_run.call_deferred()


func _queries(mesh: MeshInstance3D, faces: PackedVector3Array) -> Array:
	var rows := []
	var space := root.world_3d.direct_space_state
	var indices: Array[int] = []
	for index in range(32):
		indices.append((index * 44941 % (faces.size() / 3)) * 3)
	var bounds := mesh.mesh.get_aabb()
	var seams := []
	for index in range(1024):
		var first := (index * 1409 % (faces.size() / 3)) * 3
		var local := (faces[first] + faces[first + 1] + faces[first + 2]) / 3.0
		var distance := INF
		for edge in range(1, 4):
			distance = minf(
				distance, absf(local.x - bounds.position.x - bounds.size.x * edge / 4.0)
			)
			distance = minf(
				distance, absf(local.z - bounds.position.z - bounds.size.z * edge / 4.0)
			)
		seams.append({"first": first, "distance": distance})
	seams.sort_custom(func(a, b): return a.distance < b.distance)
	for index in range(32):
		indices.append(seams[index].first)
	for first in indices:
		var a := mesh.global_transform * faces[first]
		var b := mesh.global_transform * faces[first + 1]
		var c := mesh.global_transform * faces[first + 2]
		var normal := (b - a).cross(c - a).normalized()
		var center := (a + b + c) / 3.0
		var ray := PhysicsRayQueryParameters3D.create(center + normal * 0.2, center - normal * 0.2)
		ray.hit_back_faces = true
		var hit := space.intersect_ray(ray)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.2
		capsule.height = 1.2
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = center + Vector3.UP * 0.3
		rows.append(
			{"ray": not hit.is_empty(), "capsule": not space.intersect_shape(query, 1).is_empty()}
		)
	return rows


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1 and not FileAccess.file_exists(args[0]))
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/inferno-classic-local.json")
	)
	var source: String = data.runtime_collision_scene
	var scene: Node3D = load(source).instantiate()
	root.add_child(scene)
	await physics_frame
	var receipt := {}
	var cached: Dictionary = Cache.load_shapes(scene, source, receipt)
	assert(receipt.get("status") == "hit")
	var meshes: Dictionary = Cache.meshes(scene)
	var chosen := ""
	var largest := 0
	for path in cached:
		if cached[path].get_faces().size() > largest:
			chosen = path
			largest = cached[path].get_faces().size()
	var mesh: MeshInstance3D = meshes[chosen]
	var original: ConcavePolygonShape3D = cached[chosen]
	var backface := original.backface_collision
	var faces := original.get_faces()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	mesh.add_child(body)
	var baseline := CollisionShape3D.new()
	baseline.shape = original
	var began := Time.get_ticks_usec()
	body.add_child(baseline)
	var baseline_ms := (Time.get_ticks_usec() - began) / 1000.0
	await physics_frame
	await physics_frame
	var reference := _queries(mesh, faces)
	body.remove_child(baseline)
	baseline.free()
	original = null
	cached.clear()
	await physics_frame
	var bounds := mesh.mesh.get_aabb()
	var chunks: Array[PackedVector3Array] = []
	var ids: Array[PackedInt32Array] = []
	for index in range(16):
		chunks.append(PackedVector3Array())
		ids.append(PackedInt32Array())
	began = Time.get_ticks_usec()
	for first in range(0, faces.size(), 3):
		var center := (faces[first] + faces[first + 1] + faces[first + 2]) / 3.0
		var x := clampi(int((center.x - bounds.position.x) / maxf(bounds.size.x, 0.001) * 4), 0, 3)
		var z := clampi(int((center.z - bounds.position.z) / maxf(bounds.size.z, 0.001) * 4), 0, 3)
		var bucket := z * 4 + x
		ids[bucket].append(first / 3)
		for offset in range(3):
			chunks[bucket].append(faces[first + offset])
	var partition_ms := (Time.get_ticks_usec() - began) / 1000.0
	var coverage := PackedByteArray()
	coverage.resize(faces.size() / 3)
	var reconstructed := PackedVector3Array()
	reconstructed.resize(faces.size())
	var rows := []
	var originals_hash := HashingContext.new()
	originals_hash.start(HashingContext.HASH_SHA256)
	originals_hash.update(faces.to_byte_array())
	for index in range(16):
		for local in range(ids[index].size()):
			var triangle := ids[index][local]
			assert(coverage[triangle] == 0)
			coverage[triangle] = 1
			for offset in range(3):
				assert(chunks[index][local * 3 + offset] == faces[triangle * 3 + offset])
				reconstructed[triangle * 3 + offset] = chunks[index][local * 3 + offset]
		if chunks[index].is_empty():
			continue
		began = Time.get_ticks_usec()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = backface
		shape.set_faces(chunks[index])
		var create_ms := (Time.get_ticks_usec() - began) / 1000.0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		began = Time.get_ticks_usec()
		body.add_child(collider)
		var attach_ms := (Time.get_ticks_usec() - began) / 1000.0
		rows.append(
			{
				"bucket": index,
				"triangles": ids[index].size(),
				"create_ms": create_ms,
				"attach_ms": attach_ms
			}
		)
		await physics_frame
	assert(not coverage.has(0))
	assert(reconstructed.to_byte_array() == faces.to_byte_array())
	await physics_frame
	var candidate := _queries(mesh, faces)
	var same := 0
	for index in range(reference.size()):
		if reference[index] == candidate[index]:
			same += 1
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"kind": "authoring_exact_triangle_split",
				"source": source,
				"source_sha256": FileAccess.get_sha256(source),
				"cache_receipt": receipt,
				"mesh": chosen,
				"triangles": faces.size() / 3,
				"original_faces_sha256": originals_hash.finish().hex_encode(),
				"coverage_exact_once": true,
				"vertex_and_winding_equal": true,
				"bitwise_source_order_reconstruction_equal": true,
				"backface_collision": backface,
				"query_sampling":
				"32 distributed plus32 nearest interior cell-plane centroids from1024 candidates",
				"partition_ms": partition_ms,
				"baseline_cached_attach_ms": baseline_ms,
				"chunks": rows,
				"query_pairs_equal": same,
				"query_pairs": reference.size(),
				"baseline_queries": reference,
				"candidate_queries": candidate,
				"production_changed": false
			},
			"\t"
		)
	)
	file.close()
	print(
		"EXACT_TRIANGLE_SPLIT_OK triangles=",
		faces.size() / 3,
		" queries=",
		same,
		"/",
		reference.size()
	)
	quit()
