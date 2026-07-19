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
	await _run_test("start_game_enters_freeze_buy_state", _test_start_game_transitions_to_live_state)
	await _run_test("pause_then_resume_restores_live_state", _test_pause_then_resume_restores_live_state)
	await _run_test("level_environment_overrides_restore_defaults", _test_level_environment_overrides_restore_defaults)
	await _run_test("weapon_view_model_tracks_switch_and_shot", _test_weapon_view_model_tracks_switch_and_shot)
	await _run_test("player_scale_matches_cs_reference", _test_player_scale_matches_cs_reference)
	await _run_test("player_input_maps_to_local_forward_and_right", _test_player_input_maps_to_local_forward_and_right)
	await _run_test("player_counter_strafe_and_air_control_are_bounded", _test_player_counter_strafe_and_air_control_are_bounded)
	await _run_test("tactical_movement_solver_has_sharp_stops_and_bounded_air_control", _test_tactical_movement_solver_has_sharp_stops_and_bounded_air_control)
	await _run_test("classic_shift_walk_and_settings_apply", _test_classic_shift_walk_and_settings_apply)
	await _run_test("player_traverses_authored_height_step", _test_player_traverses_authored_height_step)
	await _run_test("player_uses_crouch_hull_without_double_jump", _test_player_uses_crouch_hull_without_double_jump)
	await _run_test("player_clears_classic_cs_height_tiers", _test_player_clears_classic_cs_height_tiers)
	await _run_test("rotating_radar_tracks_bounds_targets_and_heading", _test_rotating_radar_tracks_bounds_targets_and_heading)
	await _run_test("movement_and_radar_scale_are_map_invariant", _test_movement_and_radar_scale_are_map_invariant)
	await _run_test("combat_audio_tracks_shot_hit_reload_and_switch", _test_combat_audio_tracks_shot_hit_reload_and_switch)
	await _run_test("scoreboard_kill_feed_and_training_summary_work", _test_scoreboard_kill_feed_and_training_summary_work)
	await _run_test("player_mouse_look_bypasses_gui_consumption", _test_player_mouse_look_bypasses_gui_consumption)
	await _run_test("pause_menu_blocks_combat_commands", _test_pause_menu_blocks_combat_commands)
	await _run_test("freeze_allows_weapon_management", _test_freeze_allows_weapon_management)
	await _run_test("economy_escalates_losses_and_caps_money", _test_economy_escalates_losses_and_caps_money)
	await _run_test("knife_and_grenade_equipment_are_actionable", _test_knife_and_grenade_equipment_are_actionable)
	await _run_test("player_damage_tags_and_death_ends_round", _test_player_damage_tags_and_death_ends_round)
	await _run_test("buy_plant_defuse_round_loop", _test_buy_plant_defuse_round_loop)

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
	_assert_equal(title_label.text, "矢量突袭", "menu should expose a concise localized tactical title")
	_assert_equal(start_button.text, "\u5f00\u59cb\u8bad\u7ec3", "initial primary action should clearly start training")
	_assert_float_close(menu_panel.anchor_bottom, 1.0, 0.001, "menu panel should remain a full-height left navigation surface")
	_assert_equal(map_select.selected, 1, "default selected map should be Foundry Depot")
	_assert_true(not resume_button.visible, "resume button should stay hidden before the first run")
	_assert_true(not status_panel.visible, "debug status panel should be hidden by default")
	_assert_equal(String(GameState.current_level_id), "depot", "boot should sync the portfolio map id into GameState")
	_assert_true(String(GameState.current_level_name).contains("铸造仓库 v2"), "boot should expose the localized frozen map name")
	_assert_true(description_label.text.contains("铸造仓库 v2"), "menu description should render the localized frozen map copy")
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
	_assert_true(not bool(player.get("movement_enabled")), "freeze time should block movement while keeping mouse look enabled")
	_assert_equal(String(RoundManager.get_state_name()), "Freeze", "starting should enter the freeze/buy state")
	_assert_equal(snapshot.get("weapon_slot"), 1, "competitive loadout should start with the owned pistol")
	_assert_equal(snapshot.get("ammo_in_mag"), 12, "starting pistol should have a full magazine")
	_assert_true(bool(RoundManager.can_buy()), "freeze time should permit purchases")
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
	RoundManager.set_live()
	await get_tree().process_frame

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
	_assert_equal(initial_snapshot.get("weapon_slot"), 1, "the competitive view model should start on the pistol slot")
	_assert_true(not bool(initial_snapshot.get("rifle_visible", true)), "the unowned rifle should be hidden initially")
	_assert_true(bool(initial_snapshot.get("pistol_visible", false)), "the owned pistol should be visible initially")

	GameState.player_money = 4000
	main.call("_purchase_item", "rifle")
	var switched_snapshot: Dictionary = view_model.call("get_debug_snapshot")
	_assert_equal(switched_snapshot.get("weapon_slot"), 0, "buying a rifle should equip its view model")
	_assert_true(bool(switched_snapshot.get("rifle_visible", false)), "the purchased rifle model should become visible")
	_assert_true(not bool(switched_snapshot.get("pistol_visible", true)), "the pistol model should hide after equipping the rifle")

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

func _test_tactical_movement_solver_has_sharp_stops_and_bounded_air_control() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	player.velocity = Vector3.ZERO
	var launch: Vector3 = player.call("simulate_tactical_horizontal_velocity", Vector3.ZERO, Vector3.RIGHT, 6.2, true, 0.1)
	_assert_true(launch.x > 3.5 and launch.x < 6.2, "tactical acceleration should feel immediate without snapping to full speed")
	player.velocity = Vector3(6.2, 0.0, 0.0)
	var released: Vector3 = player.call("simulate_tactical_horizontal_velocity", player.velocity, Vector3.ZERO, 6.2, true, 0.1)
	_assert_true(released.length() < 2.5, "releasing movement should enter the accurate deadzone quickly")
	player.velocity = Vector3(5.0, 0.0, 0.0)
	var countered: Vector3 = player.call("simulate_tactical_horizontal_velocity", player.velocity, Vector3.LEFT, 6.2, true, 0.1)
	_assert_true(countered.x < 0.0, "opposite input should cross zero quickly for deliberate counter-strafing")
	player.velocity = Vector3(5.5, 0.0, 0.0)
	var air_turn: Vector3 = player.call("simulate_tactical_horizontal_velocity", player.velocity, Vector3.FORWARD, 6.2, false, 0.25)
	_assert_true(air_turn.z < 0.0, "air input should still allow a limited trajectory correction")
	_assert_true(air_turn.length() <= float(player.get("air_speed_cap")) + 0.001, "air input must not create bunny-hop speed gain")
	GameState.current_weapon_slot = 0
	_assert_float_close(float(player.call("get_equipped_movement_multiplier")), 0.94, 0.001, "rifle should move slower than the pistol")
	GameState.current_weapon_slot = 1
	_assert_float_close(float(player.call("get_equipped_movement_multiplier")), 1.0, 0.001, "pistol should retain baseline movement speed")
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
		if player.global_position.z < -0.55:
			break
	Input.action_release("move_forward")
	for _frame in range(4):
		await get_tree().physics_frame
	_assert_true(player.global_position.z < 0.6, "forward movement should continue across a 20 cm authored stair step")
	_assert_true(player.global_position.y >= 101.04, "the player capsule should settle on top of the authored stair step (y=%.3f probe=%s)" % [player.global_position.y, str(player.get("_last_step_probe"))])
	await _cleanup_main(main)

func _test_classic_shift_walk_and_settings_apply() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var hud: CanvasLayer = main.get_node("CombatHud")
	_assert_float_close(float(player.call("resolve_move_speed", false)), 6.2, 0.001, "default movement should use the classic run speed")
	_assert_float_close(float(player.call("resolve_move_speed", true)), 3.2, 0.001, "holding Shift should reduce speed for quiet walking")
	player.set("is_crouching", true)
	_assert_float_close(float(player.call("resolve_move_speed", false)), 2.2, 0.001, "crouching should remain slower than quiet walking")
	player.set("is_crouching", false)
	var original_settings: Dictionary = UserSettings.get_snapshot()
	UserSettings.apply_snapshot({
		"mouse_sensitivity_multiplier": 1.5,
		"master_volume": 0.65,
		"crosshair_gap": 10.0,
		"crosshair_size": 9.0,
		"dynamic_crosshair": false,
	}, false)
	_assert_float_close(float(player.get("mouse_sensitivity")), 0.0033, 0.00001, "sensitivity setting should update the player controller")
	_assert_float_close(float(hud.get("crosshair_gap_base")), 10.0, 0.001, "crosshair gap setting should update the HUD")
	_assert_true(not bool(hud.get("_dynamic_crosshair")), "crosshair dynamic setting should update the HUD")
	UserSettings.apply_snapshot(original_settings, false)
	await _cleanup_main(main)

func _test_player_uses_crouch_hull_without_double_jump() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var collision: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule := collision.shape as CapsuleShape3D
	player.call("set_controls_enabled", true)
	Input.action_press("crouch")
	for _frame in range(3):
		await get_tree().physics_frame
	_assert_true(bool(player.get("is_crouching")), "held crouch should enter the crouched stance")
	_assert_float_close(capsule.height, 1.2, 0.001, "crouch should shrink the player collision hull to 1.2 meters")
	Input.action_press("jump")
	for _frame in range(2):
		await get_tree().physics_frame
	Input.action_release("jump")
	var first_jump_velocity := player.velocity.y
	for _frame in range(5):
		await get_tree().physics_frame
	var velocity_before_second_press := player.velocity.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	_assert_true(first_jump_velocity > float(player.get("jump_velocity")), "crouch-jump should use the dedicated higher impulse")
	_assert_true(player.velocity.y < velocity_before_second_press, "pressing jump in mid-air must not add a second jump impulse")
	Input.action_release("crouch")
	await _cleanup_main(main)

func _test_player_clears_classic_cs_height_tiers() -> void:
	var tiers := [
		{"height": 0.4, "jump": true, "crouch": false, "start_z": 2.0},
		{"height": 0.65, "jump": true, "crouch": false, "start_z": 2.0},
		{"height": 0.8, "jump": true, "crouch": false, "start_z": 2.1},
		{"height": 1.3, "jump": true, "crouch": false, "start_z": 2.55},
		{"height": 1.55, "jump": true, "crouch": true, "start_z": 1.75},
	]
	for tier_variant in tiers:
		var tier: Dictionary = tier_variant as Dictionary
		var reached := await _run_height_tier(float(tier.height), bool(tier.jump), bool(tier.crouch), float(tier.start_z))
		_assert_true(reached, "player should clear the %.2f m tier with the authored stance" % float(tier.height))

func _run_height_tier(height: float, should_jump: bool, crouch_jump: bool, start_z: float) -> bool:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var fixture := Node3D.new()
	fixture.name = "HeightTierFixture"
	main.add_child(fixture)
	_add_static_box(fixture, Vector3(0.0, 99.95, 0.0), Vector3(8.0, 0.1, 14.0))
	_add_static_box(fixture, Vector3(0.0, 100.0 + height * 0.5, -2.0), Vector3(3.0, height, 4.0))
	player.global_position = Vector3(0.0, 100.9, start_z)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.call("set_controls_enabled", true)
	for _frame in range(3):
		await get_tree().physics_frame
	if crouch_jump:
		Input.action_press("crouch")
		for _frame in range(2):
			await get_tree().physics_frame
	Input.action_press("move_forward")
	if should_jump:
		Input.action_press("jump")
		for _frame in range(2):
			await get_tree().physics_frame
		Input.action_release("jump")
	var movement_released := false
	for _frame in range(100):
		await get_tree().physics_frame
		if not movement_released and player.global_position.z < -1.25:
			Input.action_release("move_forward")
			movement_released = true
	Input.action_release("move_forward")
	Input.action_release("jump")
	Input.action_release("crouch")
	var reached := player.global_position.z < -0.25 and player.global_position.y >= 100.9 + height - 0.09
	await _cleanup_main(main)
	return reached

func _test_rotating_radar_tracks_bounds_targets_and_heading() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var reforged_index := int(main.call("find_level_option_index", "foundry-reforged"))
	main.call("_on_map_selected", reforged_index)
	main.call("_on_start_pressed")
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	player.rotation.y = 0.75
	var radar_snapshot: Dictionary = main.call("_build_radar_snapshot")
	var radar: Control = main.get_node("CombatHud/HudRoot/Radar")
	radar.call("set_snapshot", radar_snapshot)
	var debug_snapshot: Dictionary = radar.call("get_debug_snapshot")
	_assert_vec2_close(debug_snapshot.get("bounds", Vector2.ZERO), Vector2(50.0, 40.0), 0.001, "radar should use the authored Foundry map bounds")
	_assert_equal(debug_snapshot.get("target_count"), 2, "Foundry radar should expose both objective zones")
	_assert_float_close(float(debug_snapshot.get("range_meters", 0.0)), 24.0, 0.001, "radar should use the shared 24 meter local range")
	_assert_true(int(debug_snapshot.get("feature_count", 0)) > 0, "radar should expose nearby authored map geometry")
	_assert_float_close(float(debug_snapshot.get("width_fraction", 0.0)), 0.48, 0.001, "Foundry radar diameter should cover 48 percent of map width")
	_assert_float_close(float(debug_snapshot.get("height_fraction", 0.0)), 0.6, 0.001, "Foundry radar diameter should cover 60 percent of map height")
	_assert_float_close(float(debug_snapshot.get("player_yaw", 0.0)), 0.75, 0.001, "radar should track player heading for map rotation")
	_assert_vec2_close(debug_snapshot.get("player_position", Vector2.ZERO), Vector2(player.global_position.x, player.global_position.z), 0.001, "radar should track the live player position")
	await _cleanup_main(main)

func _test_movement_and_radar_scale_are_map_invariant() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = main.get_node("Player")
	var baseline_profile: Dictionary = player.call("get_movement_profile")
	for level_id in ["test-collision-room", "depot", "gatehouse", "core-vault", "foundry-reforged"]:
		level.call("load_level", level_id)
		await get_tree().process_frame
		var current_profile: Dictionary = player.call("get_movement_profile")
		var radar_snapshot: Dictionary = main.call("_build_radar_snapshot")
		_assert_equal(current_profile, baseline_profile, "%s should retain the shared movement profile" % level_id)
		_assert_float_close(float(radar_snapshot.get("range_meters", 0.0)), 24.0, 0.001, "%s should retain the shared radar range" % level_id)
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
	main.call("_on_player_footstep", Vector3(1.0, 0.0, 2.0), "metal", true)
	main.call("_on_player_landed", Vector3(1.0, 0.0, 2.0), "concrete", 0.8)
	var snapshot: Dictionary = audio.call("get_debug_snapshot")
	_assert_equal(snapshot.get("shots"), 1, "shot feedback should count the resolved shot")
	_assert_equal(snapshot.get("hits"), 1, "hit feedback should layer an impact cue")
	_assert_equal(snapshot.get("reloads"), 1, "reload start should play a mechanical cue")
	_assert_equal(snapshot.get("switches"), 1, "weapon switching should play an equip cue")
	_assert_equal(snapshot.get("footsteps"), 1, "quiet material footsteps should reach the movement audio channel")
	_assert_equal(snapshot.get("landings"), 1, "landing impacts should reach the movement audio channel")
	_assert_equal(snapshot.get("players"), 4, "combat audio should separate shot, impact, movement, and mechanical channels")
	_assert_equal(snapshot.get("spatial_players"), 3, "shot, impact, and movement sounds should be spatialized")
	await _cleanup_main(main)

func _test_player_mouse_look_bypasses_gui_consumption() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	var player: CharacterBody3D = main.get_node("Player")
	var camera_pivot: Node3D = player.get_node("CameraPivot")
	player.call("set_controls_enabled", true)
	player.call("set_movement_enabled", false)
	player.call("set_mouse_capture_enabled", true)
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

func _test_scoreboard_kill_feed_and_training_summary_work() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	var hud: CanvasLayer = main.get_node("CombatHud")
	var scoreboard: PanelContainer = hud.get_node("HudRoot/Scoreboard")
	Input.action_press("show_scoreboard")
	await get_tree().process_frame
	_assert_true(scoreboard.visible, "holding Tab should reveal the scoreboard during live play")
	Input.action_release("show_scoreboard")
	hud.call("add_kill_feed", "YOU", "TARGET", "RIFLE")
	_assert_equal(hud.get_node("HudRoot/KillFeed").get_child_count(), 1, "a kill should add a transient kill-feed entry")
	GameState.set_training_target_count(1)
	GameState.register_hit(true)
	RoundManager.end_round("T", "ELIMINATION")
	hud.call("update_display", GameState.get_hud_snapshot())
	_assert_true(hud.get_node("HudRoot/TrainingEnd").visible, "round completion should show the training summary")
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

func _test_freeze_allows_weapon_management() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	_assert_equal(String(RoundManager.get_state_name()), "Freeze", "fixture should remain in freeze")
	var weapon_system: Node = main.get_node("WeaponSystem")
	var state: Dictionary = weapon_system.call("_current_state")
	state["ammo_in_mag"] = maxi(0, int(state.get("ammo_in_mag", 12)) - 3)
	weapon_system.call("_store_current_state", state)
	var reload_event := InputEventAction.new()
	reload_event.action = "reload_weapon"
	reload_event.pressed = true
	main.call("_unhandled_input", reload_event)
	_assert_true(bool((weapon_system.call("get_runtime_snapshot") as Dictionary).get("is_reloading", false)), "freeze should allow reloading an owned weapon")
	await _cleanup_main(main)

func _test_economy_escalates_losses_and_caps_money() -> void:
	GameState.reset_runtime_state()
	GameState.player_team = "T"
	GameState.player_money = 0
	RoundManager.bomb_site = ""
	GameState.complete_round("CT", "ELIMINATION")
	_assert_equal(GameState.player_money, 1400, "first loss should grant the base loss bonus")
	GameState.complete_round("CT", "ELIMINATION")
	_assert_equal(GameState.player_money, 3300, "second consecutive loss should escalate to 1900")
	GameState.player_money = 15900
	GameState.register_hit(true, "knife")
	_assert_equal(GameState.player_money, GameState.MAX_MONEY, "knife reward should respect the money cap")

func _test_player_damage_tags_and_death_ends_round() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	RoundManager.set_live()
	await get_tree().process_frame
	var player: CharacterBody3D = main.get_node("Player")
	_assert_equal(int(player.call("calculate_fall_damage", 9.5)), 0, "short falls should not damage the player")
	_assert_true(int(player.call("calculate_fall_damage", 15.0)) > 0, "high-impact falls should deal armor-bypassing damage")
	GameState.player_armor = 100
	var damage_result: Dictionary = player.call("apply_hitscan_damage", 20, player.global_position, 0.5, false)
	_assert_equal(damage_result.get("remaining_health"), 90, "armor penetration should split incoming damage from health")
	_assert_true(float(player.call("resolve_move_speed", false)) < 3.1, "taking damage should apply classic tagging slowdown")
	var death_result: Dictionary = player.call("apply_hitscan_damage", 250, player.global_position, 1.0, false)
	_assert_true(bool(death_result.get("killed", false)), "lethal damage should mark the player dead")
	_assert_true(bool(player.get("is_dead")), "player controller should retain the dead state")
	_assert_equal(String(RoundManager.get_state_name()), "Round End", "player death should end the round")
	_assert_equal(String(RoundManager.round_winner), "CT", "player death should award the CT side")
	await _cleanup_main(main)

func _test_knife_and_grenade_equipment_are_actionable() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	RoundManager.set_live()
	var equipment: Node = main.get_node("TacticalEquipment")
	equipment.call("select_knife")
	_assert_equal(GameState.current_weapon_slot, 2, "knife should occupy the third equipment slot")
	_assert_true(float(main.get_node("Player").call("get_equipped_movement_multiplier")) > 1.0, "holding the knife should grant the fastest movement tier")
	RoundManager.start_round()
	GameState.player_money = 1000
	main.call("_purchase_item", "he_grenade")
	RoundManager.set_live()
	_assert_true(bool(equipment.call("select_next_grenade")), "grenade slot should select a purchased grenade")
	var result := equipment.call("use_primary", main.get_node("Player")) as Dictionary
	_assert_true(bool(result.get("thrown", false)), "primary fire should throw the selected grenade")
	_assert_equal(result.get("type"), "he_grenade", "first grenade selection should use HE")
	await _cleanup_main(main)

func _test_buy_plant_defuse_round_loop() -> void:
	var main: Node3D = _instantiate_main()
	await _await_main_ready()
	main.call("_on_start_pressed")
	await _await_main_ready()
	var weapon_system: Node = main.get_node("WeaponSystem")
	GameState.player_money = 4000
	main.call("_purchase_item", "rifle")
	var purchased: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(purchased.get("weapon_slot"), 0, "buying a rifle during freeze should own and equip it")
	_assert_equal(GameState.player_money, 1300, "rifle purchase should deduct its classic-style price")
	RoundManager.set_live()
	await get_tree().process_frame
	var radar: Dictionary = main.call("_build_radar_snapshot")
	var targets: Array = radar.get("targets", [])
	_assert_true(not targets.is_empty(), "selected map should expose a bomb target")
	if not targets.is_empty():
		var target: Dictionary = targets[0]
		var player: CharacterBody3D = main.get_node("Player")
		player.global_position.x = float(target.get("x", 0.0))
		player.global_position.z = float(target.get("z", 0.0))
		Input.action_press("interact")
		_assert_true(bool(main.call("_try_plant_c4")), "T player should begin planting C4 inside an objective zone")
		main.call("_update_objective_interaction", 3.3)
		Input.action_release("interact")
		_assert_equal(String(RoundManager.get_state_name()), "Bomb Planted", "planting should enter the bomb timer state")
		GameState.player_team = "CT"
		GameState.player_defuse_kit = true
		Input.action_press("interact")
		_assert_true(bool(main.call("_try_begin_objective_interaction")), "CT should begin defusing while holding interact near C4")
		main.call("_update_objective_interaction", 5.1)
		Input.action_release("interact")
		_assert_equal(String(RoundManager.get_state_name()), "Round End", "defuse should close the round")
		_assert_equal(String(RoundManager.round_winner), "CT", "successful defuse should award CT")
		_assert_equal(GameState.friendly_score, 1, "CT score should increment after defuse")
		main.call("_on_round_restart_requested")
		await _await_main_ready()
		_assert_equal(String(RoundManager.get_state_name()), "Freeze", "round restart should return to freeze/buy time")
		_assert_equal(GameState.player_health, 100, "new round should restore player health")
		_assert_equal(weapon_system.call("get_runtime_snapshot").get("weapon_slot"), 0, "surviving player should retain the purchased rifle next round")
		GameState.player_team = "T"
		RoundManager.set_live()
		await get_tree().process_frame
		player.global_position.x = float(target.get("x", 0.0))
		player.global_position.z = float(target.get("z", 0.0))
		Input.action_press("interact")
		_assert_true(bool(main.call("_try_plant_c4")), "next round should provide a fresh carried C4")
		main.call("_update_objective_interaction", 3.3)
		Input.action_release("interact")
		RoundManager.call("_process", RoundManager.bomb_duration + 0.1)
		_assert_equal(String(RoundManager.round_winner), "T", "expired bomb timer should award T")
		_assert_equal(GameState.enemy_score, 1, "T score should increment after bomb explosion")
	await _cleanup_main(main)
