extends SceneTree

const Sweep = preload("res://tools/authoring/ChainCapsuleSweep.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(
		manifest.level
	)
	var source := String(data.runtime_collision_scene)
	assert(FileAccess.get_sha256(source) == manifest.identity.collision_sha256)
	assert(FileAccess.get_sha256(source + ".import") == manifest.identity.collision_import_sha256)
	assert(
		(
			FileAccess.get_sha256("res://data/levels/%s.json" % manifest.level)
			== manifest.identity.level_sha256
		)
	)
	assert(FileAccess.get_sha256(String(data.match_manifest)) == manifest.identity.layout_sha256)
	assert(Engine.get_version_info().hash == manifest.identity.engine_hash)
	for path in manifest.runtime_sha256:
		assert(FileAccess.get_sha256(path) == manifest.runtime_sha256[path])
	for path in manifest.probe_sha256:
		assert(FileAccess.get_sha256("res://" + path) == manifest.probe_sha256[path])
	assert(FileAccess.get_sha256("res://scenes/player/Player.tscn") == manifest.actor_scene_sha256)
	var actor := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
	var shape: CollisionShape3D = actor.get_node("CollisionShape3D")
	assert(shape.shape is CapsuleShape3D and shape.position == Sweep.vec(manifest.local_offset))
	assert(is_equal_approx(shape.shape.radius, manifest.radius))
	actor.free()
	var stage := Node3D.new()
	root.add_child(stage)
	var geometry := (load(source) as PackedScene).instantiate()
	stage.add_child(geometry)
	var builder := (load("res://scenes/level/GrayboxLevel.tscn") as PackedScene).instantiate()
	builder.load_on_ready = false
	stage.add_child(builder)
	builder.call("_build_runtime_collision", geometry, true, true, source)
	for frame in 5:
		await physics_frame
	var space := stage.get_world_3d().direct_space_state
	var rows: Array[Dictionary] = []
	var queries := 0
	for case in manifest.cases:
		var results: Array[Dictionary] = []
		for segment in case.segments:
			var result := Sweep.sweep(space, segment, manifest.radius)
			queries += result.query_count
			results.append(result)
		rows.append({"id": case.id, "segments": results})
	var output := {
		"manifest_sha256": FileAccess.get_sha256(args[0]),
		"identity": manifest.identity,
		"probe_sha256": manifest.probe_sha256,
		"runtime_sha256": manifest.runtime_sha256,
		"results": rows,
		"collision_queries": queries,
	}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("INFERNO_CHAIN_CAPSULE_WRITTEN queries=", queries)
	quit(0)
