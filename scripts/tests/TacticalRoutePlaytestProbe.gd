extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const CASES := [
	{
		"id": "gatehouse",
		"camera": Vector3(0.0, 2.2, -50.0),
		"target": Vector3(0.0, 1.2, -30.0),
	},
	{
		"id": "core-vault",
		"camera": Vector3(0.0, 2.2, -38.0),
		"target": Vector3(0.0, 1.2, -18.0),
	},
]

func _ready() -> void:
	var results: Array = []
	var succeeded := true
	for case_variant in CASES:
		var result := await _run_case(case_variant as Dictionary)
		results.append(result)
		succeeded = succeeded and bool(result.get("success", false))
	print("TACTICAL_ROUTE_PLAYTEST=" + JSON.stringify(results))
	get_tree().quit(0 if succeeded else 1)

func _run_case(test_case: Dictionary) -> Dictionary:
	var level_id := String(test_case.get("id", ""))
	var main := MAIN_SCENE.instantiate() as Node3D
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var map_index := int(main.call("find_level_option_index", level_id))
	if map_index < 0:
		main.queue_free()
		return {"level": level_id, "success": false, "reason": "missing-map-option"}
	main.call("_on_map_selected", map_index)
	main.call("_on_start_pressed")
	for _frame in range(8):
		await get_tree().physics_frame

	var player := main.get_node("Player") as CharacterBody3D
	var sandbox := main.get_node("CombatSandbox") as Node3D
	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	player.set("is_dead", true)
	player.global_position = test_case.get("camera", Vector3.ZERO) as Vector3
	player.velocity = Vector3.ZERO
	player.look_at(test_case.get("target", Vector3.ZERO) as Vector3, Vector3.UP)
	player.get_node("CameraPivot").rotation.x = 0.0
	player.reset_physics_interpolation()

	var bots: Array[CharacterBody3D] = []
	var initial_positions: Dictionary = {}
	for candidate in sandbox.get_children():
		if candidate is CharacterBody3D:
			var actor := candidate as CharacterBody3D
			var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
			if bool(ai.get("enabled", false)):
				bots.append(actor)
				initial_positions[actor.get_instance_id()] = actor.global_position
	var maximum_displacements: Dictionary = {}
	for bot in bots:
		maximum_displacements[bot.get_instance_id()] = 0.0
	RoundManager.set_live()
	for _frame in range(300):
		await get_tree().physics_frame
		for bot in bots:
			var initial_position: Vector3 = initial_positions.get(bot.get_instance_id(), bot.global_position)
			maximum_displacements[bot.get_instance_id()] = maxf(
				float(maximum_displacements.get(bot.get_instance_id(), 0.0)),
				bot.global_position.distance_to(initial_position)
			)

	var minimum_moved := INF
	var minimum_maximum_displacement := INF
	var minimum_nodes := 999999
	var minimum_links := 999999
	var maximum_recoveries := 0
	var bot_results: Array = []
	for bot in bots:
		var snapshot := bot.call("get_combat_snapshot") as Dictionary
		var ai := snapshot.get("ai", {}) as Dictionary
		var initial_position: Vector3 = initial_positions.get(bot.get_instance_id(), bot.global_position)
		var moved := bot.global_position.distance_to(initial_position)
		minimum_moved = minf(minimum_moved, moved)
		var maximum_displacement := float(maximum_displacements.get(bot.get_instance_id(), 0.0))
		minimum_maximum_displacement = minf(minimum_maximum_displacement, maximum_displacement)
		minimum_nodes = mini(minimum_nodes, int(ai.get("navigation_nodes", 0)))
		minimum_links = mini(minimum_links, int(ai.get("navigation_links", 0)))
		maximum_recoveries = maxi(maximum_recoveries, int(ai.get("stuck_recoveries", 0)))
		bot_results.append({
			"name": snapshot.get("name", ""),
			"moved": moved,
			"maximumDisplacement": maximum_displacement,
			"state": ai.get("state", ""),
			"position": [bot.global_position.x, bot.global_position.y, bot.global_position.z],
			"recoveries": ai.get("stuck_recoveries", 0),
		})

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://%s-tactical-routes.png" % level_id)
	var image_error := get_viewport().get_texture().get_image().save_png(output_path)
	var success := (
		bots.size() == 3
		and minimum_maximum_displacement >= 2.0
		and minimum_nodes >= 12
		and minimum_links >= 12
		and image_error == OK
	)
	var result := {
		"level": level_id,
		"success": success,
		"bots": bots.size(),
		"minimumMoved": minimum_moved,
		"minimumMaximumDisplacement": minimum_maximum_displacement,
		"minimumNavigationNodes": minimum_nodes,
		"minimumNavigationLinks": minimum_links,
		"maximumRecoveries": maximum_recoveries,
		"botResults": bot_results,
		"image": output_path,
	}
	main.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	return result
