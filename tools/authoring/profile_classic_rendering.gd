extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(12)
	var sun := main.get_node("Sun") as DirectionalLight3D
	var original_distance := sun.directional_shadow_max_distance
	var original_mode := sun.directional_shadow_mode
	main.call("_on_map_selected", main.call("find_level_option_index", args[0]))
	main.call("_on_team_selected", "CT")
	await main.call("_on_start_pressed")
	await _frames(30)
	main.call("_on_player_ready")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var results: Array = []
	results.append(await _sample("active_installed_profile", args[1]))
	for actor in main.get_node("CombatSandbox").get_children():
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("Player").set_physics_process(false)
	results.append(await _sample("paused_installed_profile", args[1]))
	sun.directional_shadow_max_distance = original_distance
	sun.directional_shadow_mode = original_mode
	root.use_occlusion_culling = false
	results.append(await _sample("paused_original_shadows_no_culling", args[1]))
	root.use_occlusion_culling = true
	results.append(await _sample("paused_occlusion_only", args[1]))
	for light in main.find_children("*", "DirectionalLight3D", true, false):
		print(
			(
				"SUN_DEFAULTS="
				+ str([light.directional_shadow_mode, light.directional_shadow_max_distance])
			)
		)
		light.directional_shadow_max_distance = 60.0
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	results.append(await _sample("occlusion_shadows_60m_two_cascades", args[1]))
	for light in main.find_children("*", "DirectionalLight3D", true, false):
		light.directional_shadow_max_distance = 40.0
	results.append(await _sample("occlusion_shadows_40m_two_cascades", args[1]))
	for light in main.find_children("*", "DirectionalLight3D", true, false):
		light.shadow_enabled = false
	results.append(await _sample("no_sun_shadows", args[1]))
	root.scaling_3d_scale = 0.5
	results.append(await _sample("half_resolution_no_shadows", args[1]))
	main.get_node("Level/VisualRoot/LevelVisual").visible = false
	results.append(await _sample("no_map_visual", args[1]))
	var file := FileAccess.open(args[1].path_join("profile.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"map": args[0],
				"ai": "active first sample; paused for subsequent render isolation",
				"samples": results
			},
			"\t"
		)
	)
	file.close()
	print("CLASSIC_RENDER_PROFILE_OK")
	quit(0)


func _sample(label: String, directory: String) -> Dictionary:
	await _frames(90)
	var samples: Array = []
	for index in range(6):
		await create_timer(1.0).timeout
		samples.append(
			{
				"fps": Engine.get_frames_per_second(),
				"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
				"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
				"gpu_ms":
				RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
				"render_cpu_ms":
				RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			}
		)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	print(label + " " + JSON.stringify(samples[-1]))
	return {"case": label, "frames": samples}


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame
