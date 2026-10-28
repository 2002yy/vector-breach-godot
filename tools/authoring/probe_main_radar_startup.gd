extends SceneTree
## Real Main start flow; wall clock observations, not GPU timestamps or human acceptance.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2 and not FileAccess.file_exists(args[1] + ".json"))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var level = main.get_node("Level")
	var radar = main.get_node("CombatHud/HudRoot/Radar")
	var before: int = level.load_count
	var index: int = main.find_level_option_index(args[0])
	assert(index >= 0)
	main.call("_on_map_selected", index)
	await process_frame
	await process_frame
	assert(level.load_count == before, "menu selection must not load a map")
	var began := Time.get_ticks_usec()
	main.call("_on_start_pressed")
	var events: Array = []
	var previous := ""
	var started_us := -1
	var visible_us := -1
	var rows: Array = []
	while Time.get_ticks_usec() - began < 180000000:
		var frame_start := Time.get_ticks_usec()
		var debug: Dictionary = radar.get_debug_snapshot()
		var atlas = radar.get("_atlas")
		var state := str([main.get("_starting"), main.game_started, atlas.status, atlas.generation])
		if state != previous:
			events.append({"us": frame_start - began, "state": state})
			previous = state
		if main.game_started and started_us < 0:
			started_us = frame_start - began
		await RenderingServer.frame_post_draw
		rows.append(Time.get_ticks_usec() - frame_start)
		if main.game_started and radar.is_visible_in_tree() and int(debug.atlas_layer) >= 0:
			visible_us = Time.get_ticks_usec() - began
			break
		await process_frame
	assert(visible_us >= 0)
	var buy_open: bool = main.get("_buy_menu_open")
	main.call("_on_player_ready")
	await process_frame
	await RenderingServer.frame_post_draw
	assert(get_root().get_texture().get_image().save_png(args[1] + ".png") == OK)
	var file := FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"level": args[0],
				"kind": "actual_Main_source_Vulkan",
				"selection_load_delta": level.load_count - before - 1,
				"game_started_us": started_us,
				"radar_drawn_us": visible_us,
				"buy_open_when_drawn": buy_open,
				"events": events,
				"frame_wall_us": rows,
				"start_timings": main.last_start_timings,
				"radar": radar.get_debug_snapshot()
			},
			"\t"
		)
	)
	file.close()
	print("MAIN_RADAR_STARTUP_OK ", args[0])
	quit()
