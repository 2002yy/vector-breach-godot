extends Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1] + ".png"):
		get_tree().quit(1)
		return
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(args[0])
	if data.is_empty():
		get_tree().quit(1)
		return
	GameState.reset_runtime_state()
	RoundManager.set_warmup()
	var world := Node3D.new()
	add_child(world)
	var level = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.load_on_ready = false
	world.add_child(level)
	if not level.load_level(args[0]):
		get_tree().quit(1)
		return
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.23, 0.29, 0.34)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	world.add_child(sun)
	var start: Array = data.get("spawnHints", {}).get("T", [])
	if start.is_empty():
		start = [data.start[0], data.startHeight, data.start[1]]
	var origin := Vector3(float(start[0]), float(start[1]), float(start[2]))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = origin + Vector3.UP * 0.72
	camera.rotation_degrees.y = float(data.get("startYawDegrees", 0))
	camera.current = true
	var hud = load("res://scenes/ui/CombatHud.tscn").instantiate()
	add_child(hud)
	var targets: Array[Dictionary] = []
	for landmark in data.get("landmarks", []):
		if String(landmark.get("name", "")) in ["site-a", "site-b"]:
			targets.append(
				{
					"label": "A" if String(landmark.name) == "site-a" else "B",
					"x": landmark.x,
					"z": landmark.z
				}
			)
	var snapshot := {
		"level_id": args[0],
		"bounds": Vector2(float(data.get("arenaSizeX", 150)), float(data.get("arenaSizeZ", 150))),
		"range_meters": 32.0,
		"player_position": Vector2(origin.x, origin.z),
		"player_yaw": camera.rotation.y,
		"player_height": origin.y,
		"feet_height": origin.y - 0.9,
		"grounded": true,
		"local_team": "T",
		"targets": targets,
		"players":
		[
			{"team": "CT", "x": origin.x + 4, "z": origin.z, "spotted": false, "alive": true},
			{"team": "T", "x": origin.x - 4, "y": origin.y + 4, "z": origin.z - 3, "alive": true}
		],
		"c4": {"state": "dropped", "x": origin.x + 3, "z": origin.z - 4},
		"features": []
	}
	var radar: Control = hud.get_node("HudRoot/Radar")
	for frame in range(500):
		hud.update_radar(snapshot)
		await get_tree().process_frame
		if radar.get_debug_snapshot().atlas_status == "ready":
			break
	var debug: Dictionary = radar.get_debug_snapshot()
	if debug.atlas_status != "ready" or debug.atlas_layer < 0:
		push_error("Real radar atlas did not become ready")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(args[1] + ".png") != OK:
		get_tree().quit(1)
		return
	var stream := FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	stream.store_string(
		JSON.stringify(
			{
				"level": args[0],
				"radar": debug,
				"renderer": RenderingServer.get_current_rendering_driver_name(),
				"rendering_method": RenderingServer.get_current_rendering_method(),
				"lighting": "controlled_probe_only",
				"human_acceptance": false
			},
			"\t"
		)
	)
	stream.close()
	print("REAL_RADAR_VULKAN_OK ", args[0])
	get_tree().quit(0)
