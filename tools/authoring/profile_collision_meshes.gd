extends SceneTree
## Authoring-only exact cached-shape registration timing; never edits source geometry.

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1 and not FileAccess.file_exists(args[0]))
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/inferno-classic-local.json")
	)
	var source: String = data.runtime_collision_scene
	var packed = load(source)
	var world := Node3D.new()
	root.add_child(world)
	var scene: Node = packed.instantiate()
	world.add_child(scene)
	await physics_frame
	var receipt := {}
	var cached: Dictionary = Cache.load_shapes(scene, source, receipt)
	assert(receipt.get("status") == "hit" and cached.size() == 49)
	var meshes: Dictionary = Cache.meshes(scene)
	var rows: Array = []
	var largest_mesh: Mesh
	var largest_shape: ConcavePolygonShape3D
	var largest_triangles := -1
	for path in meshes:
		var mesh: MeshInstance3D = meshes[path]
		var shape: ConcavePolygonShape3D = cached[path]
		var triangles := shape.get_faces().size() / 3
		if triangles > largest_triangles:
			largest_triangles = triangles
			largest_mesh = mesh.mesh
			largest_shape = shape
		var body := StaticBody3D.new()
		body.name = "RuntimeCollision"
		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		var began := Time.get_ticks_usec()
		collider.shape = shape
		var assigned := Time.get_ticks_usec()
		mesh.add_child(body)
		var body_added := Time.get_ticks_usec()
		body.add_child(collider)
		var registered := Time.get_ticks_usec()
		mesh.mesh = null
		var released := Time.get_ticks_usec()
		(
			rows
			. append(
				{
					"path": path,
					"triangles": triangles,
					"shape_assign_ms": (assigned - began) / 1000.0,
					"body_attach_ms": (body_added - assigned) / 1000.0,
					"shape_register_ms": (registered - body_added) / 1000.0,
					"mesh_release_ms": (released - registered) / 1000.0,
					"total_ms": (released - began) / 1000.0,
				}
			)
		)
		await physics_frame
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.total_ms > b.total_ms)
	var create_began := Time.get_ticks_usec()
	var uncached_shape := largest_mesh.create_trimesh_shape()
	var uncached_create_ms := (Time.get_ticks_usec() - create_began) / 1000.0
	assert(uncached_shape.get_faces() == largest_shape.get_faces())
	var output := FileAccess.open(args[0], FileAccess.WRITE)
	(
		output
		. store_string(
			(
				JSON
				. stringify(
					{
						"kind": "cached_original_collision_registration",
						"source": source,
						"source_sha256": FileAccess.get_sha256(source),
						"import_sha256": FileAccess.get_sha256(source + ".import"),
						"cache_sha256": FileAccess.get_sha256(Cache.cache_path(source)),
						"engine": Engine.get_version_info(),
						"cache_receipt": receipt,
						"meshes": rows,
						"largest_uncached_create_ms": uncached_create_ms,
						"largest_uncached_faces_equal_cached": true,
					},
					"\t"
				)
			)
		)
	)
	output.close()
	print("COLLISION_MESH_PROFILE_OK meshes=", rows.size())
	quit()
