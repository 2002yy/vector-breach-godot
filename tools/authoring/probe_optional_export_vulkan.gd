extends SceneTree

var host: Control
var game: Node3D
var output := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 4)
	assert(ProjectSettings.load_resource_pack(args[0], false))
	assert(ProjectSettings.load_resource_pack(args[1], false))
	if args[3] != "reserved":
		assert(ProjectSettings.load_resource_pack(args[3], false))
	output = args[2]
	assert(not DirAccess.dir_exists_absolute(output))
	DirAccess.make_dir_recursive_absolute(output)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: quit(2))
	host = load("res://scenes/ControlledGame.tscn").instantiate()
	root.add_child(host)
	game = host.game
	await _settle()
	var map_id := "dustline-depths-original-local"
	var args := OS.get_cmdline_user_args()
	var map_argument := args.find("--probe-map")
	if map_argument >= 0 and map_argument + 1 < args.size():
		map_id = args[map_argument + 1]
	game.call("_on_map_selected", game.call("find_level_option_index", map_id))
	game.call("_on_team_selected", "CT")
	await game.call("_on_start_pressed")
	await _settle()
	for actor in game.get_node("CombatSandbox").get_children():
		actor.set_physics_process(false)
	if not host.runtime.configured or host._bound.is_empty():
		await _capture("candidate-fallback")
		var failure := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
		failure.store_string(
			JSON.stringify(
				{
					"configured": false,
					"state": host.candidate_state,
					"viewport_size": str(host.viewport.size),
					"subviewport_msaa": host.viewport.msaa_3d,
					"root_msaa": root.msaa_3d,
					"diagnostics": _failure_diagnostics(),
					"context": "actual exported PCK in diagnostic editor host; not release EXE"
				},
				"\t"
			)
		)
		print("OPTIONAL_EXPORT_VULKAN_REJECTED ", host.candidate_state)
		quit(1)
		return
	game.call("_on_player_ready")
	await _capture("player-environment")
	var view := game.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	assert(host._bound.has(view.hands.get_native_hands().get_instance_id()))
	var record := {
		"map": map_id,
		"runtime_configured": host.runtime.configured,
		"bound_count": host._bound.size(),
		"player_hands_bound": true,
		"viewport_size": str(host.viewport.size),
		"subviewport_msaa": host.viewport.msaa_3d,
		"root_msaa": root.msaa_3d,
		"context":
		"editor Vulkan with actual exported PCK; diagnostic harness, not normal release EXE",
	}
	root.get_node("RoundManager").call("set_live")
	game.get_node("Player").call("apply_explosive_damage", 1000)
	var watch: Node = game.spectator
	watch.call("tick")
	assert(watch.target != null)
	if not watch.first_person:
		watch.call("toggle_mode")
	watch.call("tick")
	await process_frame
	assert(host._bound.has(watch._view_model.hands.get_native_hands().get_instance_id()))
	await _capture("spectator-environment")
	record["spectator_hands_bound"] = true
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	print("OPTIONAL_EXPORT_VULKAN_READY")
	quit(0)


func _settle() -> void:
	for frame in range(8):
		await process_frame
	var deadline := Time.get_ticks_msec() + 120000
	while game._level_loading or host.candidate_state in ["等待地图就绪", "校验并加载候选输入"]:
		assert(Time.get_ticks_msec() < deadline)
		await process_frame


func _capture(label: String) -> void:
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(host.viewport.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func _failure_diagnostics() -> Dictionary:
	var level: Dictionary = game.get_node("Level").call("get_current_level_data")
	var visual := game.get_node_or_null("Level/VisualRoot/LevelVisual") as Node3D
	var bundle: String = host._catalog.get(level.get("id", ""), "")
	var paths: Dictionary = (
		load("res://scripts/characters/SourceCharacterRuntimeInputs.gd").inspect(bundle, level)
	)
	var record := {"bundle": bundle, "input_contract_valid": not paths.is_empty()}
	if visual == null or paths.is_empty():
		return record
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(paths.alignment))
	record["visual_scene"] = visual.scene_file_path
	record["declared_visual_scene"] = receipt.get("visual_scene", "")
	record["raw_visual_present"] = FileAccess.file_exists(visual.scene_file_path)
	record["raw_visual_sha256"] = (
		FileAccess.get_sha256(visual.scene_file_path) if record.raw_visual_present else ""
	)
	record["expected_raw_visual_sha256"] = receipt.get("visual_sha256", "")
	record["same_viewport"] = visual.get_viewport() == host.runtime.get_viewport()
	record["alignment_receipt"] = paths.alignment
	var alignment: Transform3D = load("res://scripts/level/SourceVisualAlignment.gd").resolve(
		visual, level, paths.alignment
	)
	record["resolved_alignment_determinant"] = alignment.basis.determinant()
	return record
