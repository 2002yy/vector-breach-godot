extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_all_tests()
	if _failures.is_empty():
		print("[MainStateFlowTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return

	push_error("[MainStateFlowTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_all_tests() -> void:
	await _run_test("initial_boot_shows_menu_and_default_map", _test_initial_boot_shows_menu_and_default_map)
	await _run_test("map_selection_updates_game_state_and_menu_copy", _test_map_selection_updates_game_state_and_menu_copy)
	await _run_test("start_game_transitions_to_live_state", _test_start_game_transitions_to_live_state)
	await _run_test("pause_then_resume_restores_live_state", _test_pause_then_resume_restores_live_state)
	await _run_test("player_input_maps_to_local_forward_and_right", _test_player_input_maps_to_local_forward_and_right)
	await _run_test("pause_menu_blocks_combat_commands", _test_pause_menu_blocks_combat_commands)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before: int = _failures.size()
	await callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[MainStateFlowTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_vec3_close(actual: Vector3, expected: Vector3, epsilon: float, message: String) -> void:
	if actual.distance_to(expected) <= epsilon:
		return
	_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])

func _instantiate_main() -> Node3D:
	GameState.reset_runtime_state()
	GameState.set_menu_state(true)
	GameState.set_game_started(false)
	RoundManager.set_warmup()
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	return main

func _cleanup_main(main: Node3D) -> void:
	main.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func _await_main_ready() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

func _test_initial_boot_shows_menu_and_default_map() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()

	var start_menu: CanvasLayer = main.get_node("StartMenu")
	var map_select: OptionButton = start_menu.get_node("MenuPanel/Margin/VBox/Controls/MapRow/MapSelect")
	var resume_button: Button = start_menu.get_node("MenuPanel/Margin/VBox/Buttons/ResumeButton")
	var description_label: RichTextLabel = start_menu.get_node("MenuPanel/Margin/VBox/Description")
	var level: Node3D = main.get_node("Level")
	var status_panel: CanvasLayer = main.get_node("StatusPanel")

	_assert_true(bool(main.get("menu_open")), "main should start with menu open")
	_assert_true(not bool(main.get("game_started")), "main should start before gameplay begins")
	_assert_true(start_menu.visible, "start menu should be visible on boot")
	_assert_equal(map_select.item_count, 4, "start menu should list all shipped maps")
	_assert_equal(map_select.selected, 0, "default selected map should be the first entry")
	_assert_true(not resume_button.visible, "resume button should stay hidden before the first run")
	_assert_true(not status_panel.visible, "debug status panel should be hidden by default")
	_assert_equal(String(GameState.current_level_id), "test-collision-room", "boot should sync default level id into GameState")
	_assert_equal(String(GameState.current_level_name), "测试碰撞房", "boot should sync default level name into GameState")
	_assert_true(description_label.text.contains("测试碰撞房"), "menu description should render the default map copy")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "test-collision-room", "level scene should load the default test room on boot")
	_assert_equal(String(RoundManager.get_state_name()), "Warmup", "boot should leave round manager in warmup/menu state")

	await _cleanup_main(main)

func _test_map_selection_updates_game_state_and_menu_copy() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()

	var start_menu: CanvasLayer = main.get_node("StartMenu")
	var map_select: OptionButton = start_menu.get_node("MenuPanel/Margin/VBox/Controls/MapRow/MapSelect")
	var description_label: RichTextLabel = start_menu.get_node("MenuPanel/Margin/VBox/Description")
	map_select.select(2)
	main.call("_on_map_selected", 2)
	await get_tree().process_frame

	_assert_equal(int(main.get("selected_level_index")), 2, "main should store the newly selected level index")
	_assert_equal(String(GameState.current_level_id), "gatehouse", "selecting map 3 should update GameState level id")
	_assert_equal(String(GameState.current_level_name), "门厅区", "selecting map 3 should update GameState level name")
	_assert_true(description_label.text.contains("门厅区"), "menu description should update to the selected map")

	await _cleanup_main(main)

func _test_start_game_transitions_to_live_state() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()

	main.call("_on_map_selected", 1)
	await get_tree().process_frame
	main.call("_on_start_pressed")
	await _await_main_ready()

	var start_menu: CanvasLayer = main.get_node("StartMenu")
	var player: CharacterBody3D = main.get_node("Player")
	var weapon_system: Node = main.get_node("WeaponSystem")
	var level: Node3D = main.get_node("Level")
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")

	_assert_true(bool(main.get("game_started")), "start flow should mark the game as started")
	_assert_true(not bool(main.get("menu_open")), "start flow should close the menu")
	_assert_true(not start_menu.visible, "start menu should hide after starting")
	_assert_true(bool(player.get("controls_enabled")), "player controls should enable after starting")
	_assert_true(bool(player.get("mouse_capture_enabled")), "mouse capture should enable after starting")
	_assert_equal(String(GameState.current_level_id), "depot", "starting from map selection should load the selected level id")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "depot", "level scene should swap to depot on start")
	_assert_true(GameState.player_spawn != Vector3.ZERO, "starting the game should populate a non-zero player spawn")
	_assert_vec3_close(player.global_position, GameState.player_spawn, 0.06, "player reset should move the player near the level spawn after initial physics step")
	_assert_equal(String(RoundManager.get_state_name()), "Live", "starting should move round manager into live state")
	_assert_equal(snapshot.get("weapon_slot"), 0, "starting should configure the default rifle slot")
	_assert_equal(snapshot.get("ammo_in_mag"), 30, "starting should configure full rifle ammo")
	_assert_true(bool(GameState.game_started), "GameState should reflect started gameplay")
	_assert_true(not bool(GameState.menu_open), "GameState should reflect closed menu after start")

	await _cleanup_main(main)

func _test_pause_then_resume_restores_live_state() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()

	var start_menu: CanvasLayer = main.get_node("StartMenu")
	var resume_button: Button = start_menu.get_node("MenuPanel/Margin/VBox/Buttons/ResumeButton")
	var player: CharacterBody3D = main.get_node("Player")

	main.call("_open_menu", false)
	await get_tree().process_frame
	_assert_true(bool(main.get("menu_open")), "opening pause menu should flip menu_open back on")
	_assert_true(start_menu.visible, "pause menu should become visible")
	_assert_true(resume_button.visible, "resume button should be shown once a run exists")
	_assert_true(not bool(player.get("controls_enabled")), "opening pause menu should disable controls")
	_assert_true(not bool(player.get("mouse_capture_enabled")), "opening pause menu should release mouse capture")
	_assert_equal(String(RoundManager.get_state_name()), "Paused/Menu", "pause menu should move round manager to paused/menu")

	main.call("_on_resume_pressed")
	await get_tree().process_frame
	_assert_true(not bool(main.get("menu_open")), "resume should close the menu again")
	_assert_true(not start_menu.visible, "resume should hide the menu")
	_assert_true(bool(player.get("controls_enabled")), "resume should restore controls")
	_assert_true(bool(player.get("mouse_capture_enabled")), "resume should restore mouse capture")
	_assert_equal(String(RoundManager.get_state_name()), "Live", "resume should restore live round state")

	await _cleanup_main(main)

func _test_player_input_maps_to_local_forward_and_right() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")

	var forward: Vector3 = player.call("get_world_move_direction", Vector2(0.0, -1.0))
	var right: Vector3 = player.call("get_world_move_direction", Vector2(1.0, 0.0))
	_assert_vec3_close(forward, Vector3.FORWARD, 0.001, "forward input should follow the player's local forward axis")
	_assert_vec3_close(right, Vector3.RIGHT, 0.001, "right input should follow the player's local right axis")

	await _cleanup_main(main)

func _test_pause_menu_blocks_combat_commands() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()

	var weapon_system: Node = main.get_node("WeaponSystem")
	var state: Dictionary = weapon_system.call("_current_state")
	state["ammo_in_mag"] = 20
	weapon_system.call("_store_current_state", state)
	main.call("_open_menu", false)

	var reload_event := InputEventAction.new()
	reload_event.action = "reload_weapon"
	reload_event.pressed = true
	main.call("_unhandled_input", reload_event)
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_true(not bool(snapshot.get("is_reloading", false)), "reload input should be ignored while the pause menu is open")

	await _cleanup_main(main)
