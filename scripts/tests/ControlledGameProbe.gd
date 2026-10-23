extends Node

const HostScene = preload("res://scenes/ControlledGame.tscn")
var _host: Control
var _game: Node3D
var _out := ""
var _level_id := ""
var _checks := {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--evidence-dir") + 1]
	_level_id = args[args.find("--test-level") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	_host = HostScene.instantiate()
	add_child(_host)
	_game = _host.game
	assert(_host.viewport.audio_listener_enable_3d)
	_checks["positional_audio_listener_enabled"] = true
	await _settle()
	_game.call("_on_map_selected", _game.call("find_level_option_index", _level_id))
	await _settle()
	assert(_host.runtime.configured and _host.runtime.level_id == _level_id)
	assert(not _host._bound.is_empty())
	_checks["initial_characters"] = _host._bound.size()
	_freeze_roster()
	await _capture("menu")
	await _menus()
	await _game.call("_on_start_pressed")
	await _settle()
	_freeze_roster()
	await _buy()
	await _hands_environment()
	await _resize_and_look()
	await _appearance_and_roster()
	await _spectator()
	await _map_exit()
	_host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var file := FileAccess.open(_out.path_join("game.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_checks, "\t"))
	print("CONTROLLED_GAME_OK ", _level_id)
	get_tree().quit()


func _settle() -> void:
	for frame in range(4):
		await get_tree().physics_frame
	var deadline := Time.get_ticks_msec() + 120000
	while _game._level_loading or _host.candidate_state in ["等待地图就绪", "校验并加载候选输入"]:
		assert(Time.get_ticks_msec() < deadline, "game candidate did not settle")
		await get_tree().process_frame
	for frame in range(4):
		await get_tree().process_frame


func _freeze_roster() -> void:
	for actor in _game.get_node("CombatSandbox").get_children():
		actor.set_physics_process(false)
		actor.set_process(false)


func _menus() -> void:
	var menu := _game.get_node("StartMenu")
	await _key(KEY_F1)
	assert(menu.get_node("PlayerHelp").visible, "root F1 must open help exactly once")
	await _capture("menu-help")
	await _key(KEY_F1)
	assert(not menu.get_node("PlayerHelp").visible)
	await _click(menu.find_child("MapCard", true, false))
	assert(menu.get_node("MapPicker").visible, "root mouse must reach map-card GUI")
	await _capture("map-picker")
	await _key(KEY_ESCAPE)
	assert(not menu.get_node("MapPicker").visible)
	await _click(menu.find_child("CTCard", true, false))
	assert(GameState.player_team == "CT")
	_checks["menu_keyboard_and_mouse"] = true


func _buy() -> void:
	assert(_game._buy_menu_open)
	await _key(KEY_F1)
	var buy: Node = _game.get_node("CombatHud").buy_menu
	assert(buy._help_copy.visible, "buying F1 must reach inline help")
	await _capture("buy-help")
	await _key(KEY_F1)
	assert(not buy._help_copy.visible)
	await _key(KEY_B)
	assert(not _game._buy_menu_open, "B must close once")
	await _key(KEY_B)
	assert(_game._buy_menu_open, "B must open once")
	await _capture("buy")
	_game.call("_on_player_ready")
	assert(not _game._buy_menu_open)
	_checks["buy_input"] = true


func _resize_and_look() -> void:
	var original := get_window().size
	get_window().size = Vector2i(1024, 768)
	for frame in range(15):
		await RenderingServer.frame_post_draw
	assert(_host.viewport.size == Vector2i(_host.size))
	_host.ssao.request_size(Vector2i(1280, 720))
	for frame in range(15):
		await RenderingServer.frame_post_draw
	assert(_host.viewport.size == Vector2i(1280, 720), "native game viewport resize")
	await _key(KEY_ESCAPE)
	assert(_game.menu_open)
	var menu := _game.get_node("StartMenu")
	for button in menu.find_children("HelpButton", "Button", true, false):
		if button.is_visible_in_tree():
			await _click(button)
			break
	assert(menu.get_node("PlayerHelp").visible, "resized GUI coordinates")
	await _capture("resized-menu")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	assert(not _game.menu_open)
	var player := _game.get_node("Player")
	var yaw: float = player.rotation.y
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(20, -10)
	event.position = Vector2(800, 450)
	var expected := get_viewport().get_final_transform().affine_inverse().basis_xform(
		event.relative
	)
	Input.parse_input_event(event)
	await get_tree().process_frame
	assert(is_equal_approx(player.rotation.y - yaw, -expected.x * player.mouse_sensitivity))
	_checks["captured_mouse_once"] = true
	_checks["resized_gui"] = true
	_checks["native_viewport_resize"] = true
	get_window().size = original
	_host.call("_resize")
	for frame in range(15):
		await RenderingServer.frame_post_draw
	assert(_host.viewport.size == Vector2i(_host.size))


func _appearance_and_roster() -> void:
	print("CONTROLLED_STEP appearance begin")
	var sandbox := _game.get_node("CombatSandbox")
	var actor: Node = sandbox.get_children()[0]
	var previous: int = actor.get_native_character().get_instance_id()
	var next := "t-elite" if actor._appearance_id != "t-elite" else "t-blackwolf"
	actor.call("_install_appearance", next)
	print("CONTROLLED_STEP appearance installed")
	await get_tree().process_frame
	assert(not _host._bound.has(previous))
	assert(_host._bound.has(actor.get_native_character().get_instance_id()))
	_checks["appearance_rebound"] = true
	print("CONTROLLED_STEP appearance checked")
	var old: Array = []
	for member in sandbox.get_children():
		if member.has_method("get_native_character"):
			old.append(member.get_native_character().get_instance_id())
	var bound_count: int = _host._bound.size()
	sandbox.call("load_for_level", _game.get_node("Level").get_current_level_data())
	print("CONTROLLED_STEP roster installed")
	await get_tree().process_frame
	await get_tree().process_frame
	_freeze_roster()
	assert(_host._bound.size() == bound_count)
	for id in old:
		assert(not _host._bound.has(id))
	_checks["round_roster_rebound"] = true
	await _capture("rebound")


func _hands_environment() -> void:
	var view := _game.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var hands: Node3D = view.hands
	var hidden: Array = []
	for node in _game.find_children("*", "CanvasLayer", true, false):
		hidden.append([node, node.visible])
		node.visible = false
	var player := _game.get_node("Player")
	player.set_physics_process(false)
	_game.set_process(false)
	view.set_process(false)
	hands.set_process(false)
	hands.animator.stop()
	var profiles := {}
	for profile in ["ct-st6", "ct-sas-officer", "ct-fbi", "t-phoenix", "t-elite", "t-blackwolf"]:
		var previous: Node3D = hands.get_native_hands()
		var old := previous.get_instance_id()
		hands.set_appearance_profile(profile)
		await get_tree().process_frame
		var visual: Node3D = hands.get_native_hands()
		assert(_host._bound.has(visual.get_instance_id()))
		if visual.get_instance_id() != old:
			assert(not _host._bound.has(old))
		var composite: RefCounted = _host._bound[visual.get_instance_id()]
		assert(not composite.materials.is_empty())
		for entry in composite._bindings:
			if entry.original is StandardMaterial3D:
				var expected: Color = entry.original.albedo_color.srgb_to_linear()
				print(
					"HANDS_TINT ",
					profile,
					" ",
					entry.original.resource_name,
					" expected=",
					expected,
					" actual=",
					entry.copy.get_shader_parameter("base_color")
				)
				var actual: Variant = entry.copy.get_shader_parameter("base_color")
				if actual is Color:
					assert(actual.is_equal_approx(expected), "plain adapter original tint")
				else:
					assert(actual is Vector4)
					assert(
						actual.is_equal_approx(
							Vector4(expected.r, expected.g, expected.b, expected.a)
						)
					)
			print(
				"HANDS_BIND ",
				profile,
				" ",
				entry.mesh.name,
				" ",
				entry.surface,
				" ",
				entry.copy.get_shader_parameter("source_body_enabled"),
				" ",
				entry.copy.get_shader_parameter("source_indirect_enabled")
			)
		# Recompute the same native pose once after replacing the rig.
		hands.call("_process", 0.0)
		composite.set_enabled(false)
		await _capture("hands-" + profile + "-off")
		var off: PackedByteArray = _host.viewport.get_texture().get_image().get_data()
		composite.set_enabled(true)
		for frame in range(30):
			await RenderingServer.frame_post_draw
		await _capture("hands-" + profile + "-on")
		var on: PackedByteArray = _host.viewport.get_texture().get_image().get_data()
		assert(off != on, "hands environment must affect actual rendered pixels: " + profile)
		composite.set_enabled(false)
		await _capture("hands-" + profile + "-restored")
		assert(off == _host.viewport.get_texture().get_image().get_data(), "exact hand fallback")
		for entry in composite._bindings:
			assert(entry.mesh.get_surface_override_material(entry.surface) == entry.previous)
		composite.set_enabled(true)
		profiles[profile] = {
			"materials": composite.materials.size(), "pixels_changed": true, "fallback_exact": true
		}
	hands.set_appearance_profile("")
	for entry in hidden:
		entry[0].visible = entry[1]
	player.set_physics_process(true)
	hands.set_process(true)
	view.set_process(true)
	_game.set_process(true)
	_checks["first_person_profiles"] = profiles


func _spectator() -> void:
	print("CONTROLLED_STEP spectator begin")
	RoundManager.set_live()
	_game.get_node("Player").call("apply_explosive_damage", 1000)
	var watch: Node = _game.spectator
	watch.call("tick")
	print("CONTROLLED_STEP spectator ticked")
	var first: Node = watch.target
	assert(first != null)
	await _key(KEY_BRACKETRIGHT)
	print("CONTROLLED_STEP spectator cycled")
	assert(watch.target != first, "spectator key must cycle once")
	await _key(KEY_BRACKETLEFT)
	assert(watch.target == first)
	var before: bool = watch.get_snapshot().first_person
	await _key(KEY_SPACE)
	watch.call("tick")
	await get_tree().process_frame
	print("CONTROLLED_STEP spectator first person")
	assert(watch.get_snapshot().first_person != before)
	await _capture("spectator")
	var spectator_hands: Node3D = watch._view_model.hands
	var spectator_id: int = spectator_hands.get_native_hands().get_instance_id()
	assert(_host._bound.has(spectator_id), "dynamic spectator hands must bind")
	await _key(KEY_BRACKETRIGHT)
	watch.call("tick")
	await get_tree().process_frame
	assert(_host._bound.has(spectator_hands.get_native_hands().get_instance_id()))
	await _capture("spectator-hands-switched")
	_checks["spectator_hands_bound_and_switched"] = true
	_checks["spectator_input"] = true
	await _key(KEY_ESCAPE)
	assert(_game.menu_open)
	await _key(KEY_ESCAPE)
	assert(not _game.menu_open and not _game.get_node("Player").controls_enabled)
	_checks["dead_pause_resume"] = true


func _map_exit() -> void:
	_game.get_node("Level").call("load_level", "gatehouse")
	await _settle()
	assert(not _host.runtime.configured and _host._bound.is_empty())
	await _capture("map-fallback")
	_game.get_node("Level").call("load_level", _level_id)
	for frame in range(2):
		await get_tree().physics_frame
	var deadline := Time.get_ticks_msec() + 120000
	while _host.runtime._pending.is_empty():
		assert(Time.get_ticks_msec() < deadline)
		await get_tree().process_frame
	_game.get_node("Level").call("load_level", "gatehouse")
	await _settle()
	assert(not _host.runtime.configured and _host._bound.is_empty())
	_checks["map_fallback_and_old_upload_canceled"] = true


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	point = (
		_host.get_global_transform_with_canvas()
		* (point * _host.size / Vector2(_host.viewport.size))
	)
	# parse_input_event enters the physical window before its canvas stretch.
	point = get_viewport().get_final_transform() * point
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _capture(label: String) -> void:
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png")) == OK)
