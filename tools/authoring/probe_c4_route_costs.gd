extends SceneTree
## Reconstruct static graph costs for frozen real-match actors; not a replay.


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
	main.call("_on_team_selected", "CT")
	await main.call("_on_start_pressed")
	assert(main.game_started)
	var navigation := preload("res://scripts/ai/BotNavigationModel.gd").new()
	var level: Dictionary = main.get_node("Level").call("get_current_level_data")
	navigation.configure(main.get_node("CombatSandbox").call("_build_navigation_graph", level))
	for actor in main.get_node("CombatSandbox").get_children():
		if actor is CharacterBody3D and actor.has_node("TacticalBotBrain"):
			actor.set_physics_process(false)
	main.get_node("Player").set_physics_process(false)
	var results: Array = []
	for record in cases:
		var destination := _vector(record.c4_position) + Vector3.UP * 0.82
		var rows: Array = []
		for actor in record.actors:
			if actor.dead or actor.team != "T":
				continue
			var position := _vector(actor.position)
			var danger: Array[Dictionary] = []
			var path: Array = navigation.find_path(
				navigation.nearest_index(position), navigation.nearest_index(destination), danger
			)
			var length := 0.0
			var previous := position
			for index in path:
				length += previous.distance_to(navigation.points[index])
				previous = navigation.points[index]
			length += previous.distance_to(destination)
			rows.append(
				{
					"name": actor.name,
					"lease_owner": actor.lease_owner,
					"euclidean_m": position.distance_to(_vector(record.c4_position)),
					"fresh_graph_m": length,
					"reachable": not path.is_empty(),
					"nodes": path.size(),
					"recorded_state": actor.snapshot.state,
					"recorded_blocked": actor.snapshot.route_blocked
				}
			)
		results.append({"frame": record.frame, "remaining": record.remaining, "actors": rows})
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	(
		output
		. store_string(
			(
				JSON
				. stringify(
					{
						"cases_sha256": FileAccess.get_sha256(args[0]),
						"map_sha256":
						FileAccess.get_sha256("res://data/levels/mirage-classic-local.json"),
						"navigation_sha256":
						FileAccess.get_sha256("res://scripts/ai/BotNavigationModel.gd"),
						"results": results,
						"limit":
						"Fresh static graph without original danger/blocked-link state; no physical route proof"
					},
					"\t"
				)
			)
		)
	)
	output.close()
	print("C4_ROUTE_COSTS_OK")
	quit(0)


func _vector(text: String) -> Vector3:
	var values := text.trim_prefix("(").trim_suffix(")").split(",")
	assert(values.size() == 3)
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
