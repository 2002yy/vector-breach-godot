extends "res://tools/authoring/audit_classic_jumps.gd"
## Bounded geometry-first shortlist. No movement profile participates in selection.


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
	assert(
		(
			FileAccess.get_sha256(
				String(data.get("match_manifest", "res://data/levels/match-local/dustline.json"))
			)
			== parent.identity.layout_sha256
		)
	)
	assert(Engine.get_version_info().hash == parent.identity.engine_hash)
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
	var candidates: Array[Dictionary] = []
	var rises: Array = parent.survey.rises.duplicate(true)
	for record in rises:
		record["objective_distance"] = _objective_distance(
			Survey.vector(record.target_feet), layout
		)
	rises.sort_custom(func(a, b): return a.objective_distance < b.objective_distance)
	for record in rises:
		if candidates.size() == 2 or record.objective_distance > 12.0:
			break
		var point := Survey.make_case("critical_landing", record)
		point.id = "objective_rise_%02d" % candidates.size()
		point["coverage_role"] = "objective_rise"
		point["objective_distance"] = record.objective_distance
		var proof := Survey.body_corridor(
			space, Survey.vector(point.start) - Vector3.UP * 0.9, Survey.vector(point.target_feet)
		)
		if proof.clear_arcs > 0:
			point["corridor"] = proof
			candidates.append(point)
	var nodes: Array = []
	for index in range(layout.navigationGraph.points.size()):
		nodes.append(
			{
				"node": index,
				"point": layout.navigationGraph.points[index],
				"distance":
				_objective_distance(Survey.vector(layout.navigationGraph.points[index]), layout)
			}
		)
	nodes.sort_custom(func(a, b): return a.distance < b.distance)
	var examined := 0
	var gaps: Array[Dictionary] = []
	for node in nodes.slice(0, mini(128, nodes.size())):
		examined += 1
		var ground := Survey.floor_at(space, Survey.vector(node.point) - Vector3.UP * 1.8)
		if ground.is_empty() or not Survey.capsule_clear(space, ground.position):
			continue
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			for distance in [2.4, 3.0, 3.6]:
				var goal := Survey.floor_at(space, ground.position + direction * distance)
				if (
					goal.is_empty()
					or absf(goal.position.y - ground.position.y) > 0.15
					or not Survey.capsule_clear(space, goal.position)
				):
					continue
				var lower := 0
				for fraction in [0.25, 0.5, 0.75]:
					var middle := Survey.floor_at(
						space, ground.position.lerp(goal.position, fraction)
					)
					if middle.is_empty() or ground.position.y - middle.position.y > 0.6:
						lower += 1
				if lower < 2:
					continue
				var record := {
					"node": node.node,
					"feet": Survey.array(ground.position),
					"target_feet": Survey.array(goal.position),
					"direction": Survey.array(direction)
				}
				var point := Survey.make_case("edge", record)
				point.id = "gap_%02d" % gaps.size()
				point["coverage_role"] = "gap_edge"
				point["objective_distance"] = _objective_distance(goal.position, layout)
				point["corridor"] = Survey.body_corridor(
					space, Survey.vector(point.start) - Vector3.UP * 0.9, goal.position
				)
				if point.corridor.clear_arcs > 0:
					gaps.append(point)
				if gaps.size() >= 1:
					break
			if gaps.size() >= 1:
				break
		if gaps.size() >= 1:
			break
	candidates.append_array(gaps)
	var output := {
		"schema": 1,
		"formal_qualification": false,
		"level": parent.level,
		"identity": parent.identity,
		"parent_sha256": FileAccess.get_sha256(args[0]),
		"survey_sha256": FileAccess.get_sha256("res://tools/authoring/survey_tactical_jumps.gd"),
		"scan_policy":
		{
			"objective_nodes_limit": 128,
			"directions": 4,
			"distances": [2.4, 3.0, 3.6],
			"lower_middle_samples_required": 2,
			"gap_floor_drop": 0.6,
			"objective_rise_radius": 12.0
		},
		"nodes_examined": examined,
		"gap_found": not gaps.is_empty(),
		"cases": candidates
	}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	stage.queue_free()
	await process_frame
	print("TACTICAL_JUMP_SURVEY_OK cases=", candidates.size(), " gap_found=", not gaps.is_empty())
	quit(0)


func _objective_distance(point: Vector3, layout: Dictionary) -> float:
	var nearest := INF
	for objective in layout.objectives:
		nearest = minf(nearest, point.distance_to(Vector3(objective.x, objective.y, objective.z)))
	return nearest
