extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const SWEEP_STEP_METERS := 0.2
const SPRINT_SPEED := 6.2
const CASES := [
	{
		"id": "gatehouse",
		"routes": ["westApproach", "midToA", "eastApproach"],
		"rotation": "defenderRotation",
		"height": 1.05,
	},
	{
		"id": "core-vault",
		"routes": ["westOuter", "vaultWest", "eastOuter"],
		"rotation": "defenderRotation",
		"height": 1.05,
	},
]

func _ready() -> void:
	var results: Array = []
	var succeeded := true
	for case_variant in CASES:
		var result := await _run_case(case_variant as Dictionary)
		results.append(result)
		succeeded = succeeded and bool(result.get("success", false))
	print("MAP_TIMING_PLAYTEST=" + JSON.stringify(results))
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
	for _frame in range(12):
		await get_tree().physics_frame

	var player := main.get_node("Player") as CharacterBody3D
	var level := main.get_node("Level") as Node3D
	var level_data: Dictionary = level.call("get_current_level_data")
	var routes: Dictionary = level_data.get("routes", {}) as Dictionary
	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	_disable_combat_actors(main.get_node("CombatSandbox") as Node3D)

	var sweeps: Dictionary = {}
	var center_height := float(test_case.get("height", 1.05))
	for route_name_variant in test_case.get("routes", []):
		var route_name := String(route_name_variant)
		sweeps[route_name] = _sweep_route(player, routes.get(route_name, []) as Array, 6, center_height)
	sweeps["rotation"] = _sweep_route(
		player,
		routes.get(String(test_case.get("rotation", "")), []) as Array,
		-1,
		center_height
	)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://%s-map-timing.png" % level_id)
	var image_error := get_viewport().get_texture().get_image().save_png(output_path)
	var all_clear := true
	for result_variant in sweeps.values():
		all_clear = all_clear and bool((result_variant as Dictionary).get("clear", false))
	var result := {
		"level": level_id,
		"success": all_clear and image_error == OK,
		"sweeps": sweeps,
		"image": output_path,
	}
	main.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	return result

func _disable_combat_actors(sandbox: Node3D) -> void:
	if sandbox == null:
		return
	for child in sandbox.get_children():
		if child is CharacterBody3D:
			var actor := child as CharacterBody3D
			actor.collision_layer = 0
			actor.collision_mask = 0
			if actor.has_node("CollisionShape3D"):
				(actor.get_node("CollisionShape3D") as CollisionShape3D).disabled = true

func _sweep_route(player: CharacterBody3D, points: Array, end_index: int, center_height: float) -> Dictionary:
	if points.size() < 2:
		return {"clear": false, "error": "invalid route"}
	var final_index := points.size() - 1 if end_index < 0 else mini(end_index, points.size() - 1)
	var start: Array = points[0] as Array
	player.global_position = Vector3(float(start[0]), center_height, float(start[1]))
	player.velocity = Vector3.ZERO
	var distance := 0.0
	for point_index in range(final_index):
		var from_point: Array = points[point_index] as Array
		var to_point: Array = points[point_index + 1] as Array
		var segment := Vector2(
			float(to_point[0]) - float(from_point[0]),
			float(to_point[1]) - float(from_point[1])
		)
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		var direction := segment / segment_length
		var moved := 0.0
		while moved < segment_length - 0.001:
			var step := minf(SWEEP_STEP_METERS, segment_length - moved)
			var collision := player.move_and_collide(Vector3(direction.x * step, 0.0, direction.y * step))
			if collision != null:
				var collider: Object = collision.get_collider()
				return {
					"clear": false,
					"distanceMeters": snappedf(distance + moved, 0.01),
					"blockedSegment": point_index,
					"collider": String(collider.name) if collider != null else "unknown",
					"blockedPosition": collision.get_position(),
				}
			moved += step
		distance += segment_length
	return {
		"clear": true,
		"distanceMeters": snappedf(distance, 0.01),
		"timeSeconds": snappedf(distance / SPRINT_SPEED, 0.01),
		"sweepStepMeters": SWEEP_STEP_METERS,
	}
