extends "res://tools/authoring/audit_classic_jumps.gd"

var feedback_route: Array[Vector3] = []
var discovering := false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 3 and args[0] in ["discover", "replay"])
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	rate = int(args[3]) if args.size() > 3 else 60
	Engine.physics_ticks_per_second = rate
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
	assert(Engine.get_version_info().hash == manifest.identity.engine_hash)
	assert(FileAccess.get_sha256(String(data.match_manifest)) == manifest.identity.layout_sha256)
	var layout: Dictionary = preload("res://scripts/level/ClassicMatchLayout.gd").load_authored(
		data
	)
	assert(not layout.is_empty())
	stage = Node3D.new()
	root.add_child(stage)
	var geometry := (load(source) as PackedScene).instantiate()
	collision_root = geometry
	stage.add_child(geometry)
	var builder := (load("res://scenes/level/GrayboxLevel.tscn") as PackedScene).instantiate()
	builder.load_on_ready = false
	stage.add_child(builder)
	builder.call("_build_runtime_collision", geometry, true, true, source)
	for frame in range(5):
		await physics_frame
	space = stage.get_world_3d().direct_space_state
	var output := {
		"schema": 3,
		"level": manifest.level,
		"identity": manifest.identity,
		"manifest_sha256": FileAccess.get_sha256(args[1]),
		"physics_hz": rate,
		"runtime_sha256": {},
		"results": []
	}
	for file in [
		"res://scripts/player/PlayerController.gd", "res://scripts/player/ClassicMovementRules.gd"
	]:
		output.runtime_sha256[file] = FileAccess.get_sha256(file)
	if args[0] == "discover":
		var point: Dictionary = (
			manifest.cases.filter(func(p): return p.id == "run_up")[0].duplicate(true)
		)
		var graph: Dictionary = layout.navigationGraph
		var astar := AStar3D.new()
		for index in range(graph.points.size()):
			astar.add_point(index, Survey.vector(graph.points[index]))
		for link in graph.links:
			astar.connect_points(
				int(link.from), int(link.to), bool(link.get("bidirectional", true))
			)
		var source_id := astar.get_closest_point(Survey.vector(point.start))
		var goal_id := astar.get_closest_point(Survey.vector(point.target_feet) + Vector3.UP * 0.9)
		var ids := astar.get_id_path(source_id, goal_id)
		assert(not ids.is_empty())
		for id in ids:
			feedback_route.append(astar.get_point_position(id) - Vector3.UP * 0.06)
		feedback_route.append(Survey.vector(point.target_feet) + Vector3.UP * 0.9)
		output["route_nodes"] = Array(ids)
		output["route_waypoints"] = feedback_route.map(func(p): return Survey.array(p))
		discovering = true
		point.duration = 12.0
		for mode in ["no_jump", "walk"]:
			var result := await _trial(point, "current", mode)
			result["control_type"] = "feedback_discovery_not_acceptance"
			output.results.append(result)
	else:
		for point in manifest.cases:
			for scheme in ["current", "legacy_16", "modern_cs"]:
				output.results.append(
					await _trial(point, scheme, String(point.get("trial_mode", "jump")))
				)
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	stage.queue_free()
	await process_frame
	await process_frame
	print("MIRAGE_ROUTE_INPUTS_WRITTEN ", args[2])
	quit(0)


func _trial_script() -> Script:
	return load("res://tools/authoring/MovementRoutePlayer.gd")


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var result: Dictionary = await super._trial(point, scheme, mode)
	await process_frame
	var support: Array[Dictionary] = []
	var entry: Dictionary = result.target_entry
	if not entry.is_empty():
		var feet := Survey.vector(entry.position) - Vector3.UP * 0.9
		for offset in [
			Vector3.ZERO,
			Vector3.LEFT * 0.3,
			Vector3.RIGHT * 0.3,
			Vector3.FORWARD * 0.3,
			Vector3.BACK * 0.3
		]:
			var ray := PhysicsRayQueryParameters3D.create(
				feet + offset + Vector3.UP * 0.2, feet + offset - Vector3.UP * 0.3, 1
			)
			var hit := space.intersect_ray(ray)
			if (
				not hit.is_empty()
				and hit.collider is Node
				and collision_root.is_ancestor_of(hit.collider)
				and hit.normal.y >= 0.7
			):
				support.append(
					{
						"position": Survey.array(hit.position),
						"normal": Survey.array(hit.normal),
						"body": str(hit.collider.get_path())
					}
				)
	result["goal_entry_support"] = support
	result["route_arrival_reached"] = not support.is_empty()
	return result


func _configure_trial_player(
	player: CharacterBody3D, _point: Dictionary, _scheme: String, mode: String
) -> void:
	player.feedback = discovering
	player.feedback_walk = mode == "walk"
	player.waypoints = feedback_route


func _record(sample: Dictionary) -> void:
	super._record(sample)
	var row: Dictionary = samples[-1]
	row["input"] = {
		"at": sample.input.sample_time,
		"direction": [sample.input.direction.x, sample.input.direction.y],
		"jump": sample.input.jump,
		"crouch": sample.input.crouch,
		"walk": sample.input.walk
	}
	row["speed_limit"] = trial_player.resolve_final_move_speed(sample.input.walk)
	row["crouching"] = trial_player.is_crouching
	row["capsule_height"] = trial_player.get_node("CollisionShape3D").shape.height
