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

	var manifest = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://assets/local_reference/radar/" + args[0] + "/v4/atlas.json"
		)
	)
	var stages: Array = []
	var base_layer: int = preload("res://scripts/ui/RadarAtlas.gd").nearest_layer(
		manifest.layers, origin.y - 0.9
	)
	if base_layer < 0:
		base_layer = 0
	var next_layer := mini(base_layer + 1, manifest.layers.size() - 1)
	if next_layer == base_layer:
		next_layer = maxi(0, base_layer - 1)
	for entry in [
		["first_visible", base_layer], ["cold_next", next_layer], ["cache_return", base_layer]
	]:
		var stage_start := Time.get_ticks_usec()
		var rows: Array = []
		var verified_usec := -1
		var visible := false
		snapshot.feet_height = float(manifest.layers[entry[1]].height)
		for frame in range(500):
			var call_start := Time.get_ticks_usec()
			hud.update_radar(snapshot)
			var call_us := Time.get_ticks_usec() - call_start
			var debug_now: Dictionary = radar.get_debug_snapshot()
			if debug_now.atlas_status == "ready" and verified_usec < 0:
				verified_usec = Time.get_ticks_usec() - stage_start
			await RenderingServer.frame_post_draw
			rows.append(
				{
					"frame": frame,
					"wall_us": Time.get_ticks_usec() - call_start,
					"update_us": call_us,
					"layer": debug_now.atlas_layer
				}
			)
			if int(debug_now.atlas_layer) == int(entry[1]):
				visible = true
				break
			await get_tree().process_frame
		stages.append(
			{
				"stage": entry[0],
				"verified_us": verified_usec,
				"first_draw_us": Time.get_ticks_usec() - stage_start,
				"visible": visible,
				"rows": rows
			}
		)
		if not visible:
			push_error("Timed radar stage never visible")
			get_tree().quit(1)
			return
	var debug: Dictionary = radar.get_debug_snapshot()
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
				"stages": stages,
				"metric":
				"CPU wall through frame_post_draw, not GPU timestamp; controlled snapshot heights",
				"renderer": RenderingServer.get_current_rendering_driver_name(),
				"rendering_method": RenderingServer.get_current_rendering_method(),
				"lighting": "controlled_probe_only",
				"human_acceptance": false
			},
			"\t"
		)
	)
	stream.close()
	print("RADAR_VULKAN_TIMING_OK ", args[0])
	get_tree().quit(0)
