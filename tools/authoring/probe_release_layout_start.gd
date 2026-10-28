extends Node
## Diagnostic release launcher; normal Main gameplay gate is preserved.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	assert(not OS.has_feature("editor"))
	var layout_script = load("res://scripts/level/ClassicMatchLayout.gd")
	if layout_script == null:
		get_tree().quit(11)
		return
	if (
		layout_script.get_source_code()
		!= FileAccess.get_file_as_string("res://scripts/level/ClassicMatchLayout.gd")
	):
		get_tree().quit(12)
		return
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var index: int = main.find_level_option_index(args[0])
	var injected := index < 0
	if injected:
		var option: Dictionary = main.level_options[0].duplicate(true)
		option.id = args[0]
		option.name = args[0]
		main.level_options.append(option)
		index = main.level_options.size() - 1
		main.get_node("StartMenu").set_map_options(main.level_options, index)
	main.call("_on_map_selected", index)
	var began := Time.get_ticks_usec()
	main.call("_on_start_pressed")
	var radar = main.get_node("CombatHud/HudRoot/Radar")
	var debug: Dictionary = {}
	while Time.get_ticks_usec() - began < 120000000:
		debug = radar.get_debug_snapshot()
		if main.game_started and int(debug.atlas_layer) >= 0:
			break
		if main.get("_level_load_failed") and not main.get("_starting"):
			break
		await get_tree().process_frame
	var result := {
		"map": args[0],
		"kind": "release_binary_assembled_candidate",
		"editor": OS.has_feature("editor"),
		"layout_source_sha256": FileAccess.get_sha256("res://scripts/level/ClassicMatchLayout.gd"),
		"helper_source_sha256":
		FileAccess.get_sha256("res://scripts/level/ExportedLayoutIdentity.gd"),
		"headless_option_injected": injected,
		"game_started": main.game_started,
		"load_failed": main.get("_level_load_failed"),
		"duration_us": Time.get_ticks_usec() - began,
		"radar": debug
	}
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	var passed: bool = main.game_started and not main.get("_level_load_failed")
	print("RELEASE_LAYOUT_MAIN_OK " if passed else "RELEASE_LAYOUT_MAIN_FAILED ", args[0])
	get_tree().quit(0 if passed else 2)
