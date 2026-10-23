extends Node

var _main: Node3D
var _out := ""
var _receipt := {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--evidence-dir") + 1]
	var target: String = args[args.find("--test-level") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var began := Time.get_ticks_usec()
	var scene: PackedScene = load("res://scenes/Main.tscn")
	_receipt["main_resource_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	var phase := Time.get_ticks_usec()
	_main = scene.instantiate()
	add_child(_main)
	_receipt["instantiate_ready_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	var level := _main.get_node("Level")
	assert(level.load_count == 0 and level.get_current_level_data().is_empty())
	await _capture("boot")
	print("LOBBY_READY_ZERO_LOADS")
	_receipt["selection_ms"] = {}
	for id in ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]:
		phase = Time.get_ticks_usec()
		_main.call("_on_map_selected", _main.call("find_level_option_index", id))
		_receipt.selection_ms[id] = (Time.get_ticks_usec() - phase) / 1000.0
		assert(level.load_count == 0 and level.get_node("VisualRoot").get_child_count() == 0)
		assert(_main.get_node("StartMenu/MapBackground").texture != null)
		await _capture("selected-" + id)
	if "--menu-only" in args:
		print("LAZY_MENUS_ONLY_OK")
		get_tree().quit()
		return
	_main.call("_on_map_selected", _main.call("find_level_option_index", target))
	_main.call("_on_team_selected", "CT")
	_main.call("_on_start_pressed")
	_main.call("_on_start_pressed")
	await RenderingServer.frame_post_draw
	assert(_main._starting and level.load_count == 0, "loading screen precedes engine work")
	assert(get_viewport().get_texture().get_image().save_png(_out.path_join("loading.png")) == OK)
	while _main._starting:
		await get_tree().process_frame
	assert(level.load_count == 1 and level.get_current_level_data().id == target)
	assert(_main.game_started and _main.last_start_timings.success)
	_receipt["start"] = _main.last_start_timings.duplicate(true)
	_receipt["boot_and_cards_loads"] = 0
	_receipt["actual_start_loads"] = level.load_count
	for actor in _main.get_node("CombatSandbox").get_children():
		actor.set_physics_process(false)
	await _capture("buy-ready")
	if "--capture-background" in args:
		await _clean_background()
		await get_tree().process_frame
		print("BACKGROUND_CAPTURE_OK ", target)
		get_tree().quit()
		return
	_main.call("_open_menu", false)
	_main.call("_return_to_map_selection")
	_main.call("_on_map_selected", _main.call("find_level_option_index", "training-range"))
	assert(level.load_count == 1 and level.get_current_level_data().id == target)
	assert(not level.visible and not _main.get_node("Player").is_physics_processing())
	_receipt["return_selection_does_not_reload"] = true
	await _capture("return-selection")
	_main.queue_free()
	await get_tree().process_frame
	var file := FileAccess.open(_out.path_join("loading.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_receipt, "\t"))
	print("LAZY_LOBBY_OK ", target)
	get_tree().quit()


func _capture(label: String) -> void:
	for frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png")) == OK)


func _clean_background() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			child.hide()
	var weapon := _main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var sandbox := _main.get_node("CombatSandbox")
	var device := _main.get_node("C4Device")
	weapon.hide()
	sandbox.hide()
	device.hide()
	_main.get_node("StartMenu").call(
		"frame_map_preview", _main.get_node("Level").get_current_level_data()
	)
	for frame in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(
		get_viewport().get_texture().get_image().save_png(_out.path_join("background.png")) == OK
	)
