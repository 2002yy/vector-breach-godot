extends SceneTree

const Sweep = preload("res://tools/authoring/ObservedPathSweep.gd")


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
	assert(FileAccess.get_sha256("res://scenes/player/Player.tscn") == manifest.actor_scene_sha256)
	var actor := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
	var actor_shape: CollisionShape3D = actor.get_node("CollisionShape3D")
	assert(actor_shape.position == Vector3.ZERO and actor_shape.shape is CapsuleShape3D)
	var radius: float = actor_shape.shape.radius
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
	var count := 0
	for case in manifest.cases:
		var row: Dictionary = Sweep.sweep(space, case.poses, radius)
		row["id"] = case.id
		count += row.query_count
		rows.append(row)
	var probes := {}
	for path in manifest.probe_sha256:
		var value := FileAccess.get_sha256("res://" + path)
		assert(value == manifest.probe_sha256[path])
		probes[path] = value
	var output := {
		"schema": 1,
		"results": rows,
		"manifest_sha256": FileAccess.get_sha256(args[0]),
		"identity": manifest.identity,
		"probe_sha256": probes,
		"collision_queries": count,
		"capsule_radius": radius,
		"local_shape_offset": [0, 0, 0],
		"margin": 0.001
	}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("OBSERVED_INFERNO_SWEEP_WRITTEN ", rows.size(), " cases ", count, " queries")
	quit(0)
