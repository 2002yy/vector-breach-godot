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
	await _run_test("level_environment_overrides_restore_defaults", _test_level_environment_overrides_restore_defaults)
	await _run_test("weapon_view_model_tracks_switch_and_shot", _test_weapon_view_model_tracks_switch_and_shot)
	await _run_test("player_scale_matches_cs_reference", _test_player_scale_matches_cs_reference)
	await _run_test("player_input_maps_to_local_forward_and_right", _test_player_input_maps_to_local_forward_and_right)
	await _run_test("player_counter_strafe_and_air_control_are_bounded", _test_player_counter_strafe_and_air_control_are_bounded)
	await _run_test("player_traverses_authored_height_step", _test_player_traverses_authored_height_step)
	await _run_test("combat_audio_tracks_shot_hit_reload_and_switch", _test_combat_audio_tracks_shot_hit_reload_and_switch)
	await _run_test("player_mouse_look_bypasses_gui_consumption", _test_player_mouse_look_bypasses_gui_consumption)
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

func _assert_vec2_close(actual: Vector2, expected: Vector2, epsilon: float, message: String) -> void:
	if actual.distance_to(expected) <= epsilon:
		return
	_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])

func _assert_float_close(actual: float, expected: float, epsilon: float, message: String) -> void:
	if is_equal_approx(actual, expected) or absf(actual - expected) <= epsilon:
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
	var menu_panel: PanelContainer = start_menu.get_node("MenuPanel")
	var title_label: Label = start_menu.get_node("MenuPanel/Margin/VBox/Title")
	var start_button: Button = start_menu.get_node("MenuPanel/Margin/VBox/Buttons/StartButton")
	var resume_button: Button = start_menu.get_node("MenuPanel/Margin/VBox/Buttons/ResumeButton")
	var description_label: RichTextLabel = start_menu.get_node("MenuPanel/Margin/VBox/Description")
	var level: Node3D = main.get_node("Level")
	var status_panel: CanvasLayer = main.get_node("StatusPanel")

	_assert_true(bool(main.get("menu_open")), "main should start with menu open")
	_assert_true(not bool(main.get("game_started")), "main should start before gameplay begins")
	_assert_true(start_menu.visible, "start menu should be visible on boot")
	_assert_equal(map_select.item_count, 5, "headless start menu should list only the five publishable maps")
	_assert_equal((main.get("level_options") as Array).size(), 5, "local reference maps should stay out of automated headless runs")
	_assert_equal(title_label.text, "VECTOR BREACH", "menu should expose a concise tactical title")
	_assert_equal(start_button.text, "\u5f00\u59cb\u8bad\u7ec3", "initial primary action should clearly start training")
	_assert_float_close(menu_panel.anchor_bottom, 1.0, 0.001, "menu panel should remain a full-height left navigation surface")
	_assert_equal(map_select.selected, 1, "default selected map should be Foundry Depot")
	_assert_true(not resume_button.visible, "resume button should stay hidden before the first run")
	_assert_true(not status_panel.visible, "debug status panel should be hidden by default")
	_assert_equal(String(GameState.current_level_id), "depot", "boot should sync the portfolio map id into GameState")
	_assert_true(String(GameState.current_level_name).contains("Foundry Depot v2"), "boot should label the frozen portfolio map as Foundry Depot v2")
	_assert_true(description_label.text.contains("Foundry Depot v2"), "menu description should render the frozen Foundry baseline copy")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "depot", "level scene should load Foundry Depot on boot")
	_assert_equal(level.get_node("VisualRoot").get_child_count(), 1, "boot should instantiate the Foundry visual scene behind the menu")
	_assert_equal(String(RoundManager.get_state_name()), "Warmup", "boot should leave round manager in warmup/menu state")

	await _cleanup_main(main)

func _test_map_selection_updates_game_state_and_menu_copy() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()

	var start_menu: CanvasLayer = main.get_node("StartMenu")
	var map_select: OptionButton = start_menu.get_node("MenuPanel/Margin/VBox/Controls/MapRow/MapSelect")
	var description_label: RichTextLabel = start_menu.get_node("MenuPanel/Margin/VBox/Description")
	var reforged_index := int(main.call("find_level_option_index", "foundry-reforged"))
	_assert_true(reforged_index >= 0, "Foundry Reforged should be available as a shipped map")
	if reforged_index < 0:
		await _cleanup_main(main)
		return
	map_select.select(reforged_index)
	main.call("_on_map_selected", reforged_index)
	await get_tree().process_frame

	_assert_equal(int(main.get("selected_level_index")), reforged_index, "main should store the newly selected level index")
	_assert_equal(String(GameState.current_level_id), "foundry-reforged", "selecting Reforged should update GameState level id")
	_assert_true(String(GameState.current_level_name).contains("\u91cd\u6784"), "selecting Reforged should update GameState level name")
	_assert_true(description_label.text.contains("\u91cd\u6784"), "menu description should update to the Reforged copy")

	await _cleanup_main(main)

func _test_start_game_transitions_to_live_state() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()

	var reforged_index := int(main.call("find_level_option_index", "foundry-reforged"))
	_assert_true(reforged_index >= 0, "Foundry Reforged should be available to the start flow")
	if reforged_index < 0:
		await _cleanup_main(main)
		return
	main.call("_on_map_selected", reforged_index)
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
	_assert_equal(String(GameState.current_level_id), "foundry-reforged", "starting from map selection should load Reforged")
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "foundry-reforged", "level scene should swap to Reforged on start")
	_assert_true(GameState.player_spawn != Vector3.ZERO, "starting the game should populate a non-zero player spawn")
	_assert_vec2_close(
		Vector2(player.global_position.x, player.global_position.z),
		Vector2(GameState.player_spawn.x, GameState.player_spawn.z),
		0.06,
		"player reset should use the selected level spawn coordinates"
	)
	_assert_true(
		player.global_position.y > 0.4 and player.global_position.y <= GameState.player_spawn.y + 0.06,
		"player should remain between the floor and spawn height while initial gravity settles"
	)
	_assert_float_close(player.rotation.y, GameState.player_spawn_yaw_radians, 0.001, "starting should face the player along the authored route heading")
	_assert_equal(String(RoundManager.get_state_name()), "Live", "starting should move round manager into live state")
	_assert_equal(snapshot.get("weapon_slot"), 0, "starting should configure the default rifle slot")
	_assert_equal(snapshot.get("ammo_in_mag"), 30, "starting should configure full rifle ammo")
	_assert_true(bool(GameState.game_started), "GameState should reflect started gameplay")
	_assert_true(not bool(GameState.menu_open), "GameState should reflect closed menu after start")
	var combat_sandbox: Node3D = main.get_node("CombatSandbox")
	_assert_equal(combat_sandbox.get_child_count(), 5, "Reforged should spawn its dedicated off-route combat targets")

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

func _test_level_environment_overrides_restore_defaults() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var environment_node: WorldEnvironment = main.get_node("WorldEnvironment")
	var sun: DirectionalLight3D = main.get_node("Sun")
	var default_sky := environment_node.environment.sky
	var default_sun_color := sun.light_color
	var default_sun_rotation := sun.rotation

	main.call("_apply_level_environment", {
		"environment": {
			"ambient_light_energy": 0.3,
			"ambient_light_color": [0.5, 0.6, 0.7],
			"sun_energy": 0.65,
			"sun_color": [1.0, 0.8, 0.6],
			"sun_rotation_degrees": [-52.0, -34.0, 0.0],
			"sun_shadow_enabled": true,
			"sky_mode": "physical",
			"sky_energy_multiplier": 0.72,
			"sky_turbidity": 13.5,
			"sky_ground_color": [0.11, 0.13, 0.14],
			"sky_mie_coefficient": 0.009,
			"sky_rayleigh_coefficient": 1.45,
			"sky_sun_disk_scale": 0.65,
			"fog_enabled": true,
			"fog_density": 0.0012,
			"tonemap": "aces",
			"tonemap_exposure": 1.05,
			"ssao_enabled": true,
			"ssao_radius": 1.8,
			"ssao_intensity": 1.35
		}
	})
	_assert_float_close(environment_node.environment.ambient_light_energy, 0.3, 0.001, "level data should override ambient light energy")
	_assert_float_close(sun.light_energy, 0.65, 0.001, "level data should override sun energy")
	_assert_true(sun.shadow_enabled, "level data should enable the single directional shadow caster")
	_assert_true(environment_node.environment.sky.sky_material is PhysicalSkyMaterial, "level data should build the configured physical sky")
	var physical_sky := environment_node.environment.sky.sky_material as PhysicalSkyMaterial
	_assert_float_close(physical_sky.turbidity, 13.5, 0.001, "level data should apply the physical sky turbidity")
	_assert_float_close(physical_sky.sun_disk_scale, 0.65, 0.001, "level data should apply the physical sun disk scale")
	_assert_true(environment_node.environment.fog_enabled, "level data should enable lightweight distance fog")
	_assert_true(environment_node.environment.ssao_enabled, "level data should enable ambient occlusion")
	_assert_float_close(environment_node.environment.ssao_radius, 1.8, 0.001, "level data should apply the authored SSAO radius")
	_assert_equal(environment_node.environment.tonemap_mode, Environment.TONE_MAPPER_ACES, "level data should select ACES tonemapping")
	main.call("_apply_level_environment", {
		"environment": {
			"sky_panorama": "res://assets/environment/overcast_soil_puresky_1k.hdr",
			"sky_energy_multiplier": 0.62
		}
	})
	_assert_true(environment_node.environment.sky.sky_material is PanoramaSkyMaterial, "level data should retain a pure-sky panorama option")

	main.call("_apply_level_environment", {})
	_assert_float_close(environment_node.environment.ambient_light_energy, 0.7, 0.001, "maps without overrides should restore default ambient light")
	_assert_float_close(sun.light_energy, 1.4, 0.001, "maps without overrides should restore default sun energy")
	_assert_true(environment_node.environment.sky == default_sky, "maps without overrides should restore the procedural sky")
	_assert_true(sun.light_color.is_equal_approx(default_sun_color), "maps without overrides should restore default sun color")
	_assert_vec3_close(sun.rotation, default_sun_rotation, 0.001, "maps without overrides should restore default sun rotation")
	_assert_true(not environment_node.environment.fog_enabled, "maps without overrides should restore default fog state")
	_assert_true(not environment_node.environment.ssao_enabled, "maps without overrides should restore default SSAO state")

	await _cleanup_main(main)

func _test_weapon_view_model_tracks_switch_and_shot() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()

	var weapon_system: Node = main.get_node("WeaponSystem")
	var view_model: Node3D = main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var initial_snapshot: Dictionary = view_model.call("get_debug_snapshot")
	_assert_true(view_model.visible, "starting gameplay should show the first-person weapon view model")
	_assert_equal(initial_snapshot.get("weapon_slot"), 0, "the view model should start on the rifle slot")
	_assert_true(bool(initial_snapshot.get("rifle_visible", false)), "the rifle model should be visible for slot 1")
	_assert_true(not bool(initial_snapshot.get("pistol_visible", true)), "the pistol model should be hidden for slot 1")

	weapon_system.call("switch_to_slot", 1)
	var switched_snapshot: Dictionary = view_model.call("get_debug_snapshot")
	_assert_equal(switched_snapshot.get("weapon_slot"), 1, "the WeaponSystem switch signal should select the pistol view model")
	_assert_true(not bool(switched_snapshot.get("rifle_visible", true)), "the rifle model should hide after switching to slot 2")
	_assert_true(bool(switched_snapshot.get("pistol_visible", false)), "the pistol model should show after switching to slot 2")

	main.call("_on_shot_resolved", {"hit": false})
	var shot_snapshot: Dictionary = view_model.call("get_debug_snapshot")
	_assert_true(float(shot_snapshot.get("shot_kick", 0.0)) > 0.0, "a resolved shot should trigger view model recoil")

	await _cleanup_main(main)

func _test_player_scale_matches_cs_reference() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var collision: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule: CapsuleShape3D = collision.shape as CapsuleShape3D
	var camera_pivot: Node3D = player.get_node("CameraPivot")

	_assert_true(capsule != null, "player should use a capsule collision hull")
	if capsule != null:
		_assert_float_close(capsule.height, 1.8, 0.001, "standing player collision should be approximately 1.8 meters tall")
		_assert_float_close(capsule.radius, 0.4, 0.001, "player collision width should stay close to the CS reference hull")
	_assert_float_close(float(player.get("standing_height")), 0.9, 0.001, "player origin should remain centered over the standing hull")
	_assert_float_close(camera_pivot.position.y + float(player.get("standing_height")), 1.62, 0.001, "standing eye height should be approximately 1.62 meters")
	_assert_true(float(player.get("max_step_height")) <= 0.42, "automatic step-up should not climb waist-high graybox blocks")

	await _cleanup_main(main)

func _test_player_input_maps_to_local_forward_and_right() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")

	var forward: Vector3 = player.call("get_world_move_direction", Vector2(0.0, -1.0))
	var right: Vector3 = player.call("get_world_move_direction", Vector2(1.0, 0.0))
	var expected_forward := (player.global_transform.basis * Vector3.FORWARD).normalized()
	var expected_right := (player.global_transform.basis * Vector3.RIGHT).normalized()
	_assert_vec3_close(forward, expected_forward, 0.001, "forward input should follow the player's local forward axis")
	_assert_vec3_close(right, expected_right, 0.001, "right input should follow the player's local right axis")

	await _cleanup_main(main)

func _test_player_counter_strafe_and_air_control_are_bounded() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	player.velocity = Vector3(5.0, 0.0, 0.0)
	var counter_response := float(player.call("get_movement_response_acceleration", Vector3.LEFT, true))
	var normal_response := float(player.call("get_movement_response_acceleration", Vector3.RIGHT, true))
	var air_response := float(player.call("get_movement_response_acceleration", Vector3.LEFT, false))
	_assert_true(counter_response > normal_response, "opposite input should brake faster for deliberate peeking")
	_assert_true(air_response < normal_response, "air control should stay below grounded acceleration")
	_assert_true(float(player.get("max_step_height")) >= 0.4, "step-up should clear authored 20 cm stair risers with margin")
	await _cleanup_main(main)

func _test_player_traverses_authored_height_step() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var fixture := Node3D.new()
	fixture.name = "MovementFixture"
	main.add_child(fixture)
	_add_static_box(fixture, Vector3(0.0, 99.95, 0.0), Vector3(8.0, 0.1, 12.0))
	_add_static_box(fixture, Vector3(0.0, 100.1, -1.0), Vector3(3.0, 0.2, 2.0))
	player.global_position = Vector3(0.0, 100.9, 2.4)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.call("set_controls_enabled", true)
	Input.action_press("move_forward")
	for _frame in range(45):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_assert_true(player.global_position.z < 0.6, "forward movement should continue across a 20 cm authored stair step")
	_assert_true(player.global_position.y >= 101.04, "the player capsule should settle on top of the authored stair step")
	await _cleanup_main(main)

func _add_static_box(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = position
	body.add_child(collision)
	parent.add_child(body)

func _test_combat_audio_tracks_shot_hit_reload_and_switch() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var audio: Node = main.get_node("CombatAudioFeedback")
	main.call("_on_shot_resolved", {"hit": true, "weapon_slot": 0})
	main.call("_on_reload_started")
	main.call("_on_reload_finished")
	main.call("_on_weapon_switched", "pistol", 1)
	var snapshot: Dictionary = audio.call("get_debug_snapshot")
	_assert_equal(snapshot.get("shots"), 1, "shot feedback should count the resolved shot")
	_assert_equal(snapshot.get("hits"), 1, "hit feedback should layer an impact cue")
	_assert_equal(snapshot.get("reloads"), 1, "reload start should play a mechanical cue")
	_assert_equal(snapshot.get("switches"), 1, "weapon switching should play an equip cue")
	_assert_equal(snapshot.get("players"), 3, "combat audio should use separate shot, impact, and mechanical players")
	await _cleanup_main(main)

func _test_player_mouse_look_bypasses_gui_consumption() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var camera_pivot: Node3D = player.get_node("CameraPivot")
	var yaw_before := player.rotation.y
	var pitch_before := camera_pivot.rotation.x
	var look_event := InputEventMouseMotion.new()
	look_event.relative = Vector2(40.0, -20.0)
	player.call("_input", look_event)
	_assert_true(not is_equal_approx(player.rotation.y, yaw_before), "captured mouse motion should rotate player yaw before GUI handling")
	_assert_true(not is_equal_approx(camera_pivot.rotation.x, pitch_before), "captured mouse motion should rotate camera pitch before GUI handling")

	main.call("_open_menu", false)
	var paused_yaw := player.rotation.y
	var paused_pitch := camera_pivot.rotation.x
	player.call("_input", look_event)
	_assert_float_close(player.rotation.y, paused_yaw, 0.0001, "pause menu should block mouse yaw")
	_assert_float_close(camera_pivot.rotation.x, paused_pitch, 0.0001, "pause menu should block mouse pitch")

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
