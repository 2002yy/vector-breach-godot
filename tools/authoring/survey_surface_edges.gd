extends "res://tools/authoring/audit_classic_jumps.gd"
## Bounded ray columns near authored anchors; surface accessibility remains unproven.


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2 and not FileAccess.file_exists(args[1]))
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
	var anchors: Array[Vector3] = []
	for objective in layout.objectives:
		anchors.append(Vector3(objective.x, objective.y, objective.z))
	for record in parent.survey.flat:
		anchors.append(Survey.vector(record.feet))
	for record in parent.survey.drops:
		anchors.append(Survey.vector(record.feet))
	var candidates: Array[Dictionary] = []
	var diagnostics := {"columns": 0, "clear_surfaces": 0, "lower_goals": 0, "sweeps": 0}
	var seen := {}
	for anchor_index in range(anchors.size()):
		for x in [-2.0, -1.0, 0.0, 1.0, 2.0]:
			for z in [-2.0, -1.0, 0.0, 1.0, 2.0]:
				if diagnostics.columns >= 1024 or candidates.size() >= 8:
					break
				diagnostics.columns += 1
				var at := anchors[anchor_index] + Vector3(x, 0, z)
				var ray := PhysicsRayQueryParameters3D.create(
					at + Vector3.UP * 2.2, at - Vector3.UP * 0.3, 1
				)
				var ground := space.intersect_ray(ray)
				if (
					ground.is_empty()
					or ground.normal.y < 0.95
					or not Survey.capsule_clear(space, ground.position)
				):
					continue
				diagnostics.clear_surfaces += 1
				for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					for distance in [0.8, 1.2, 1.6]:
						var goal_at: Vector3 = ground.position + direction * distance
						var goal_ray := PhysicsRayQueryParameters3D.create(
							goal_at + Vector3.UP * 0.15, goal_at - Vector3.UP * 2.1, 1
						)
						var goal := space.intersect_ray(goal_ray)
						if (
							goal.is_empty()
							or goal.normal.y < 0.95
							or not Survey.capsule_clear(space, goal.position)
						):
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
						var sweep := space.cast_motion(query)
						if sweep[0] < 0.999:
							continue
						diagnostics.sweeps += 1
						var key := str(ground.position.snapped(Vector3.ONE * 0.01)) + str(direction)
						if seen.has(key):
							continue
						seen[key] = true
						candidates.append(
							{
								"node": anchor_index,
								"feet": Survey.array(ground.position),
								"near_feet": Survey.array(goal.position),
								"target_feet": Survey.array(goal.position),
								"direction": Survey.array(direction),
								"height_change": drop,
								"anchor_offset": [x, z],
								"surface_accessibility": "unproven",
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
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	assert(file != null)
	file.store_string(
		JSON.stringify(
			{
				"identity": parent.identity,
				"parent_sha256": FileAccess.get_sha256(args[0]),
				"survey_sha256":
				FileAccess.get_sha256("res://tools/authoring/survey_surface_edges.gd"),
				"formal_qualification": false,
				"surface_accessibility": "unproven",
				"diagnostics": diagnostics,
				"candidates": candidates,
				"policy":
				{
					"column_limit": 1024,
					"candidate_limit": 8,
					"offsets": [-2, -1, 0, 1, 2],
					"distances": [0.8, 1.2, 1.6],
					"goal_ray_up": 0.15
				}
			},
			"\t"
		)
	)
	file.close()
	stage.queue_free()
	await process_frame
	print("SURFACE_EDGE_SURVEY_WRITTEN candidates=", candidates.size())
	quit(0)
