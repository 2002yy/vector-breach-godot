extends SceneTree
## Controlled exported-gate test against a real product PCK; no source game fallback.

const MAPS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 3 and not FileAccess.file_exists(args[2]))
	var bootstrap = load(args[0])
	var mounted: String = bootstrap.bootstrap(true, args[1])
	assert(mounted == "mounted", "exact production bootstrap must mount adjacent sidecar")
	var rows := []
	var passed := true
	for map_id in MAPS:
		var main = load("res://scenes/Main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		var level = main.get_node("Level")
		var radar = main.get_node("CombatHud/HudRoot/Radar")
		var before: int = level.load_count
		var index: int = main.find_level_option_index(map_id)
		if index < 0:
			var option: Dictionary = main.level_options[0].duplicate(true)
			option.id = map_id
			option.name = map_id
			main.level_options.append(option)
			index = main.level_options.size() - 1
			main.get_node("StartMenu").call("set_map_options", main.level_options, index)
		main.call("_on_map_selected", index)
		await process_frame
		assert(level.load_count == before)
		var began := Time.get_ticks_usec()
		main.call("_on_start_pressed")
		var debug: Dictionary = {}
		while Time.get_ticks_usec() - began < 180000000:
			if main.get("_level_load_failed") and not main.get("_starting"):
				break
			debug = radar.get_debug_snapshot()
			if main.game_started and int(debug.atlas_layer) >= 0:
				break
			await process_frame
		# Record rejected gameplay identity without bypassing the gate.
		passed = passed and bool(main.game_started)
		rows.append(
			{
				"map": map_id,
				"identity_diagnostic": _diagnostic(map_id),
				"game_started": main.game_started,
				"load_failed": main.get("_level_load_failed"),
				"ready_us": Time.get_ticks_usec() - began,
				"load_delta": level.load_count - before,
				"radar": debug
			}
		)
		main.queue_free()
		await process_frame
		await process_frame
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	output.store_string(
		JSON.stringify(
			{
				"kind": "assembled_product_pck_Main_headless",
				"automatic_autoload_acceptance": false,
				"maps": rows
			},
			"\t"
		)
	)
	output.close()
	print("PACKAGED_MAIN_OK maps=3" if passed else "PACKAGED_MAIN_REJECTED maps=3")
	quit(0 if passed else 2)


func _diagnostic(map_id: String) -> Dictionary:
	var path := "res://data/levels/" + map_id + ".json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var source := String(data.runtime_collision_scene)
	var manifest := String(
		data.get("match_manifest", "res://data/levels/match-local/dustline.json")
	)
	return {
		"collision_path": source,
		"raw_collision_exists": FileAccess.file_exists(source),
		"manifest_path": manifest,
		"manifest_exists": FileAccess.file_exists(manifest),
		"input_stamps_empty":
		load("res://scripts/level/ClassicMatchLayout.gd").input_stamps(data).is_empty()
	}
