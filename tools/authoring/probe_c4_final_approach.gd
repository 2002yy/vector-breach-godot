extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2 and not FileAccess.file_exists(args[1]))
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for frame in range(5):
		await physics_frame
	var options: Array = main.get("level_options")
	var option: Dictionary = options[0].duplicate(true)
	option.id = "mirage-classic-local"
	option.name = "Mirage"
	options.append(option)
	main.set("selected_level_index", options.size() - 1)
	main.get_node("StartMenu").call("set_map_options", options, options.size() - 1)
	main.call("_on_team_selected", "T")
	await main.call("_on_start_pressed")
	assert(main.game_started)
	var actor: CharacterBody3D
	for candidate in main.get_node("CombatSandbox").get_children():
		if candidate is CharacterBody3D:
			candidate.set_physics_process(false)
			candidate.get_node("TacticalBotBrain").set_physics_process(false)
			if actor == null and candidate.get("team") == "T":
				actor = candidate
	main.get_node("Player").set_physics_process(false)
	var brain: Node = actor.get_node("TacticalBotBrain")
	var navigation = brain.get("_navigation")
	var c4: Node3D = main.get_node("C4Device")
	var results: Array = []
	for record in cases:
		actor.global_position = _vector(record.actor)
		c4.call("drop_at", _vector(record.c4))
		await physics_frame
		var actual := c4.global_position
		var rows: Array = []
		for offset in [0.0, 0.82]:
			var destination: Vector3 = actual + Vector3.UP * offset
			var start: int = navigation.nearest_index(actor.global_position)
			var goal: int = navigation.nearest_index(destination)
			var danger: Array[Dictionary] = []
			var path: Array = navigation.find_path(start, goal, danger)
			var points: Array = []
			var path_length := 0.0
			var previous := actor.global_position
			for index in path:
				points.append(str(navigation.points[index]))
				path_length += previous.distance_to(navigation.points[index])
				previous = navigation.points[index]
			path_length += previous.distance_to(destination)
			var motion := destination - actor.global_position
			motion.y = 0.0
			var supports: Array = []
			for sample in range(9):
				var at := actor.global_position.lerp(actual, float(sample) / 8.0) - Vector3.UP * 0.9
				var query := PhysicsRayQueryParameters3D.create(
					at + Vector3.UP * 0.5, at - Vector3.UP * 0.7, 1
				)
				query.exclude = [actor.get_rid()]
				var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
				supports.append(
					{
						"at": str(at),
						"hit": not hit.is_empty(),
						"position": str(hit.get("position", Vector3.INF)),
						"normal": str(hit.get("normal", Vector3.ZERO))
					}
				)
			rows.append(
				{
					"reconstructed_path_m": path_length,
					"direct_distance_m": actor.global_position.distance_to(actual),
					"local_corridor_allowed":
					preload("res://scripts/ai/C4LocalApproach.gd").allowed(actor, actual),
					"offset": offset,
					"start": start,
					"goal": goal,
					"path": path,
					"points": points,
					"direct_capsule_blocked": actor.test_move(actor.global_transform, motion),
					"ground_support": supports,
					"destination": str(destination)
				}
			)
		results.append(
			{
				"label": record.label,
				"actor": str(actor.global_position),
				"recorded_c4": record.c4,
				"actual_c4": str(actual),
				"can_pick_up": c4.call("can_pick_up", actor.global_position, "T"),
				"rows": rows
			}
		)
	var level: Dictionary = main.get_node("Level").call("get_current_level_data")
	var stamps := {"cases_sha": FileAccess.get_sha256(args[0])}
	for key in ["match_manifest", "collision_scene", "visual_scene"]:
		var source := String(level.get(key, ""))
		if FileAccess.file_exists(source):
			stamps[key] = {"path": source, "sha256": FileAccess.get_sha256(source)}
	var data := {
		"cases": results,
		"map_sha": FileAccess.get_sha256("res://data/levels/mirage-classic-local.json"),
		"stamps": stamps,
		"limitation":
		"Reconstructed fresh navigation; not original next node, blocked graph or RNG state"
	}
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(JSON.stringify(data, "\t"))
	output.close()
	print("C4_FINAL_APPROACH_PROBE_OK")
	quit(0)


func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
