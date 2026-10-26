extends "res://tools/authoring/audit_classic_jumps.gd"
## Geometry-only bounded shortlist; horizontal standing capsule must clear the approach.


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	var parent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(
		parent.level
	)
	var source := String(data.runtime_collision_scene)
	assert(FileAccess.get_sha256(source) == parent.identity.collision_sha256)
	assert(FileAccess.get_sha256(source + ".import") == parent.identity.collision_import_sha256)
	assert(
		(
			FileAccess.get_sha256("res://data/levels/%s.json" % parent.level)
			== parent.identity.level_sha256
		)
	)
	assert(Engine.get_version_info().hash == parent.identity.engine_hash)
	var layout_path := String(
		data.get("match_manifest", "res://data/levels/match-local/dustline.json")
	)
	assert(FileAccess.get_sha256(layout_path) == parent.identity.layout_sha256)
	var layout: Dictionary = preload("res://scripts/level/ClassicMatchLayout.gd").load_authored(
		data
	)
	stage = Node3D.new()
	root.add_child(stage)
	var geometry := (load(source) as PackedScene).instantiate()
	stage.add_child(geometry)
	var builder := (load("res://scenes/level/GrayboxLevel.tscn") as PackedScene).instantiate()
	builder.load_on_ready = false
	stage.add_child(builder)
	builder.call("_build_runtime_collision", geometry, true, true, source)
	for frame in range(5):
		await physics_frame
	space = stage.get_world_3d().direct_space_state
	var points: Array = layout.navigationGraph.points
	var stride := maxi(1, int(ceil(float(points.size()) / 1024.0)))
	var candidates: Array[Dictionary] = []
	var examined := 0
	var diagnostics := {"clear_starts": 0, "lower_goals": 0, "clear_initial": 0, "clear_sweeps": 0}
	for index in range(0, points.size(), stride):
		examined += 1
		var ground := Survey.floor_at(space, Survey.vector(points[index]) - Vector3.UP * 1.8)
		if ground.is_empty() or not Survey.capsule_clear(space, ground.position):
			continue
		diagnostics.clear_starts += 1
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			for distance in [1.0, 1.6]:
				var goal := Survey.floor_at(
					space, ground.position + direction * distance - Vector3.UP * 0.2
				)
				if goal.is_empty() or not Survey.capsule_clear(space, goal.position):
					continue
				var drop: float = goal.position.y - ground.position.y
				if drop > -0.5 or drop < -2.0:
					continue
				diagnostics.lower_goals += 1
				var shape := CapsuleShape3D.new()
				shape.radius = 0.4
				shape.height = 1.8
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = shape
				query.collision_mask = 1
				query.margin = 0.001
				query.transform.origin = ground.position + Vector3.UP * 0.94
				query.motion = direction * distance
				if not space.intersect_shape(query, 1).is_empty():
					continue
				diagnostics.clear_initial += 1
				var sweep := space.cast_motion(query)
				if sweep[0] < 0.999:
					continue
				diagnostics.clear_sweeps += 1
				candidates.append(
					{
						"node": index,
						"feet": Survey.array(ground.position),
						"direction": Survey.array(direction),
						"target_feet": Survey.array(goal.position),
						"near_feet": Survey.array(goal.position),
						"height_change": drop,
						"horizontal_sweep":
						{
							"radius": 0.4,
							"height": 1.8,
							"clearance": 0.04,
							"distance": distance,
							"free_fraction": sweep[0]
						}
					}
				)
				break
			if candidates.size() >= 8:
				break
		if candidates.size() >= 8:
			break
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	assert(file != null)
	file.store_string(
		JSON.stringify(
			{
				"identity": parent.identity,
				"parent_sha256": FileAccess.get_sha256(args[0]),
				"survey_sha256":
				FileAccess.get_sha256("res://tools/authoring/survey_walkoff_edges.gd"),
				"nodes_examined": examined,
				"node_limit": 1024,
				"stride": stride,
				"diagnostics": diagnostics,
				"candidates": candidates,
				"formal_qualification": false
			},
			"\t"
		)
	)
	file.close()
	stage.queue_free()
	await process_frame
	print("WALKOFF_SURVEY_WRITTEN candidates=", candidates.size())
	quit(0)
