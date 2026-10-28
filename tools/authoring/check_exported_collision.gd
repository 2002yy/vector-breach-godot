extends SceneTree
## Run only in an empty project; assets must come from mounted exported packs.

const SOURCES := {
	"dust": "res://assets/models/dustline/dustline_depths.glb",
	"mirage": "res://assets/local_reference/classic_maps/mirage/official/player_collision.glb",
	"inferno": "res://assets/local_reference/classic_maps/inferno/official/player_collision.glb"
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 2)
	assert(not FileAccess.file_exists(args[-1]), "use a fresh result path")
	for source in SOURCES.values():
		assert(not ResourceLoader.exists(source), "isolated project required")
	for path in args.slice(0, args.size() - 1):
		assert(ProjectSettings.load_resource_pack(path, true), path)
	var rows := []
	for label in SOURCES:
		var source: String = SOURCES[label]
		assert(not FileAccess.file_exists(source), "raw source must be absent")
		var packed = load(source)
		assert(packed is PackedScene, source)
		var world := Node3D.new()
		root.add_child(world)
		var scene = packed.instantiate()
		world.add_child(scene)
		var meshes: Array = scene.find_children("*", "MeshInstance3D", true, false)
		var count := 0
		var centers: Array[Vector3] = []
		for node in meshes:
			if not String(node.name).begins_with("COLLISION_") or node.mesh == null:
				continue
			var shape = node.mesh.create_trimesh_shape()
			assert(shape != null)
			var body := StaticBody3D.new()
			var collider := CollisionShape3D.new()
			collider.shape = shape
			node.add_child(body)
			body.add_child(collider)
			if centers.size() < 32:
				centers.append(node.global_transform * node.mesh.get_aabb().get_center())
			count += 1
		assert(count > 0, label)
		await physics_frame
		await physics_frame
		var hits := 0
		for center in centers:
			var query := PhysicsRayQueryParameters3D.create(
				center + Vector3.UP * 100.0, center - Vector3.UP * 100.0, 1
			)
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and scene.is_ancestor_of(hit.collider):
				hits += 1
		assert(hits > 0, label)
		rows.append(
			{
				"map": label,
				"source": source,
				"meshes": meshes.size(),
				"shapes": count,
				"rays": centers.size(),
				"hits": hits
			}
		)
		world.queue_free()
		await process_frame
	var output := FileAccess.open(args[-1], FileAccess.WRITE)
	output.store_string(JSON.stringify({"maps": rows, "isolated": true}, "\t"))
	output.close()
	print("EXPORTED_COLLISION_OK maps=3")
	quit()
