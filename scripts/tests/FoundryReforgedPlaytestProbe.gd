extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "foundry-reforged"
const SWEEP_STEP_METERS := 0.2

func _ready() -> void:
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var target_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if target_index < 0:
		push_error("Foundry Reforged playtest probe could not find its map option")
		get_tree().quit(1)
		return
	main.call("_on_map_selected", target_index)
	main.call("_on_start_pressed")
	for _frame in range(12):
		await get_tree().physics_frame

	var player: CharacterBody3D = main.get_node("Player")
	var level: Node3D = main.get_node("Level")
	var level_data: Dictionary = level.call("get_current_level_data")
	var routes: Dictionary = level_data.get("routes", {}) as Dictionary
	var metrics: Dictionary = level_data.get("metrics", {}) as Dictionary
	var sprint_speed := float(metrics.get("sprintSpeedMetersPerSecond", 6.2))
	var player_on_floor_at_spawn := player.is_on_floor()
	player.call("set_controls_enabled", false)
	player.set_physics_process(false)

	var sweeps: Dictionary = {}
	for audit_variant in level_data.get("contactAudits", []):
		var audit: Dictionary = audit_variant as Dictionary
		var route_name := String(audit.get("route", ""))
		sweeps[String(audit.get("id", route_name))] = _sweep_route(
			player,
			routes.get(route_name, []) as Array,
			int(audit.get("pointIndex", -1)),
			sprint_speed,
			1.05
		)
	sweeps["site-rotation"] = _sweep_route(
		player,
		routes.get("defenderRotation", []) as Array,
		-1,
		sprint_speed,
		1.3
	)

	var images := {
		"spawn": await _capture_route_view(player, "spawn", routes.get("aLong", []) as Array, 0, 1.05),
		"aLong": await _capture_route_view(player, "a-long", routes.get("aLong", []) as Array, 6, 1.05),
		"mid": await _capture_route_view(player, "mid", routes.get("mid", []) as Array, 6, 1.05),
		"bService": await _capture_route_view(player, "b-service", routes.get("bServiceDock", []) as Array, 6, 1.05),
		"bHigh": await _capture_route_view(player, "b-high", routes.get("bHigh", []) as Array, 2, 4.15),
		"aSpool": await _capture_target_view(player, "a-spool", Vector3(-16.0, 1.05, -28.0), Vector3(-12.0, 0.72, -25.5)),
		"bPump": await _capture_target_view(player, "b-pump", Vector3(-4.0, 1.05, 25.5), Vector3(0.0, 0.65, 28.0)),
		"bValve": await _capture_target_view(player, "b-valve", Vector3(9.5, 1.05, 25.5), Vector3(13.0, 0.75, 22.0))
	}
	var visual_root: Node3D = level.get_node("VisualRoot")
	var all_clear := true
	for result_variant in sweeps.values():
		all_clear = all_clear and bool((result_variant as Dictionary).get("clear", false))
	var images_saved := true
	for image_variant in images.values():
		images_saved = images_saved and not String(image_variant).is_empty()
	print("FOUNDRY_REFORGED_PLAYTEST=" + JSON.stringify({
		"level": String(level_data.get("id", "")),
		"revision": String(level_data.get("designRevision", "")),
		"playerOnFloorAtSpawn": player_on_floor_at_spawn,
		"mouseCaptured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"visualScenes": visual_root.get_child_count(),
		"sweeps": sweeps,
		"images": images
	}))
	get_tree().quit(0 if all_clear and images_saved and player_on_floor_at_spawn else 1)

func _sweep_route(
	player: CharacterBody3D,
	points: Array,
	end_index: int,
	speed: float,
	center_height: float
) -> Dictionary:
	if points.size() < 2 or speed <= 0.0:
		return {"clear": false, "error": "invalid route or speed"}
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
			var collision := player.move_and_collide(
				Vector3(direction.x * step, 0.0, direction.y * step)
			)
			if collision != null:
				var collider: Object = collision.get_collider()
				return {
					"clear": false,
					"distanceMeters": snappedf(distance + moved, 0.01),
					"blockedSegment": point_index,
					"collider": String(collider.name) if collider != null else "unknown"
				}
			moved += step
		distance += segment_length
	return {
		"clear": true,
		"distanceMeters": snappedf(distance, 0.01),
		"timeSeconds": snappedf(distance / speed, 0.01),
		"sweepStepMeters": SWEEP_STEP_METERS
	}

func _capture_route_view(
	player: CharacterBody3D,
	label: String,
	points: Array,
	point_index: int,
	center_height: float
) -> String:
	if point_index < 0 or point_index >= points.size():
		return ""
	var position_point: Array = points[point_index] as Array
	var look_index := mini(point_index + 1, points.size() - 1)
	var look_point: Array = points[look_index] as Array
	player.global_position = Vector3(
		float(position_point[0]),
		center_height,
		float(position_point[1])
	)
	player.velocity = Vector3.ZERO
	player.look_at(Vector3(float(look_point[0]), center_height, float(look_point[1])), Vector3.UP)
	var camera_pivot: Node3D = player.get_node("CameraPivot")
	camera_pivot.rotation.x = 0.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path(
		"user://foundry-reforged-%s-first-person.png" % label
	)
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	return output_path if save_error == OK else ""

func _capture_target_view(
	player: CharacterBody3D,
	label: String,
	position: Vector3,
	target: Vector3
) -> String:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.look_at(target, Vector3.UP)
	var camera_pivot: Node3D = player.get_node("CameraPivot")
	camera_pivot.rotation.x = 0.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path(
		"user://foundry-reforged-%s-first-person.png" % label
	)
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	return output_path if save_error == OK else ""
