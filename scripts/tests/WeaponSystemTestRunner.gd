extends Node3D

const WEAPON_SYSTEM_SCENE = preload("res://scenes/combat/WeaponSystem.tscn")
const RIFLE_PROFILE = preload("res://data/weapons/rifle.tres")
const PISTOL_PROFILE = preload("res://data/weapons/pistol.tres")
const TEST_PLAYER_SCENE = preload("res://scenes/tests/support/TestPlayerStub.tscn")
const TARGET_DUMMY_SCENE = preload("res://scenes/combat/TargetDummy.tscn")
const COMBAT_HUD_SCENE = preload("res://scenes/ui/CombatHud.tscn")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await get_tree().process_frame
	await _run_all_tests()
	if _failures.is_empty():
		print("[WeaponSystemTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return

	push_error("[WeaponSystemTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_all_tests() -> void:
	await _run_test("configure_default_loadout_syncs_snapshot", _test_configure_default_loadout_syncs_snapshot)
	await _run_test("pistol_hold_without_press_does_not_fire", _test_pistol_hold_without_press_does_not_fire)
	await _run_test("pistol_press_fires_once_then_requires_release", _test_pistol_press_fires_once_then_requires_release)
	await _run_test("rifle_hold_repeats_after_cooldown", _test_rifle_hold_repeats_after_cooldown)
	await _run_test("reload_ignored_when_mag_full", _test_reload_ignored_when_mag_full)
	await _run_test("reload_refills_mag_and_consumes_reserve", _test_reload_refills_mag_and_consumes_reserve)
	await _run_test("empty_mag_fire_triggers_reload", _test_empty_mag_fire_triggers_reload)
	await _run_test("switch_to_slot_cancels_reload_and_respects_equip_lock", _test_switch_to_slot_cancels_reload_and_respects_equip_lock)
	await _run_test("pattern_index_resets_after_recovery_delay", _test_pattern_index_resets_after_recovery_delay)
	await _run_test("hud_uses_familiar_information_zones", _test_hud_uses_familiar_information_zones)
	await _run_test("hits_dummy_registers_damage_and_updates_hud", _test_hits_dummy_registers_damage_and_updates_hud)
	await _run_test("kill_shot_registers_kill_and_updates_hud", _test_kill_shot_registers_kill_and_updates_hud)
	await _run_test("terrain_hit_does_not_increment_hit_count", _test_terrain_hit_does_not_increment_hit_count)
	await _run_test("invalid_profile_does_not_shift_runtime_slots", _test_invalid_profile_does_not_shift_runtime_slots)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before: int = _failures.size()
	var fixture: Dictionary = await _create_fixture()
	await callable.call(fixture)
	await _destroy_fixture(fixture)
	if _failures.size() == failed_before:
		_passes += 1
		print("[WeaponSystemTests] PASS %s" % test_name)

func _create_fixture() -> Dictionary:
	GameState.reset_runtime_state()
	GameState.set_menu_state(false)
	GameState.set_game_started(true)
	RoundManager.set_live()

	var player: CharacterBody3D = TEST_PLAYER_SCENE.instantiate()
	player.name = "TestPlayer"
	add_child(player)

	var weapon_system: Node = WEAPON_SYSTEM_SCENE.instantiate()
	weapon_system.name = "WeaponSystemUnderTest"
	weapon_system.set("weapon_profiles", [_clone_profile(RIFLE_PROFILE), _clone_profile(PISTOL_PROFILE)])
	add_child(weapon_system)
	weapon_system.call("configure_default_loadout")

	await get_tree().process_frame

	var weapon_profiles: Array = weapon_system.get("weapon_profiles")

	return {
		"player": player,
		"weapon_system": weapon_system,
		"rifle_profile": weapon_profiles[0],
		"pistol_profile": weapon_profiles[1],
		"cleanup_nodes": [weapon_system, player]
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	for node_variant in fixture.get("cleanup_nodes", []):
		if node_variant is Node:
			(node_variant as Node).queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func _clone_profile(profile_resource: Resource) -> Resource:
	var profile: Resource = profile_resource.duplicate(true)
	profile.set("spread_move_penalty_degrees", 0.0)
	profile.set("spread_air_penalty_degrees", 0.0)
	return profile

func _tick_weapon_system(weapon_system: Node, player: CharacterBody3D, total_time: float, fire_pressed: bool = false, fire_held: bool = false) -> void:
	var remaining: float = total_time
	if remaining <= 0.0:
		weapon_system.call("tick", 0.0, fire_pressed, fire_held, player)
		return

	while remaining > 0.0:
		var step: float = minf(remaining, 0.05)
		weapon_system.call("tick", step, fire_pressed, fire_held, player)
		fire_pressed = false
		remaining -= step

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_float_close(actual: float, expected: float, epsilon: float, message: String) -> void:
	if absf(actual - expected) <= epsilon:
		return
	_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])

func _current_state(weapon_system: Node) -> Dictionary:
	return weapon_system.call("_current_state")

func _weapon_states(weapon_system: Node) -> Array:
	return weapon_system.get("_weapon_states")

func _capture_shot_result(result: Dictionary, bucket: Array) -> void:
	bucket.append(result)

func _register_cleanup_node(fixture: Dictionary, node: Node) -> void:
	var cleanup_nodes: Array = fixture.get("cleanup_nodes", [])
	cleanup_nodes.append(node)
	fixture["cleanup_nodes"] = cleanup_nodes

func _spawn_target_dummy(fixture: Dictionary, max_health: int = 100) -> StaticBody3D:
	var dummy: StaticBody3D = TARGET_DUMMY_SCENE.instantiate()
	dummy.set("max_health", max_health)
	dummy.position = Vector3(0.0, 1.6, -10.0)
	add_child(dummy)
	_register_cleanup_node(fixture, dummy)
	return dummy

func _spawn_combat_hud(fixture: Dictionary) -> CanvasLayer:
	var hud: CanvasLayer = COMBAT_HUD_SCENE.instantiate()
	add_child(hud)
	_register_cleanup_node(fixture, hud)
	return hud

func _spawn_test_wall(fixture: Dictionary) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	wall.collision_layer = 1
	wall.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.5)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = Vector3(0.0, 1.6, -6.0)
	add_child(wall)
	_register_cleanup_node(fixture, wall)
	return wall

func _await_world_ready() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func _test_configure_default_loadout_syncs_snapshot(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(snapshot.get("weapon_slot"), 0, "default loadout should start on rifle slot")
	_assert_equal(snapshot.get("ammo_in_mag"), 30, "rifle should start with full magazine")
	_assert_equal(snapshot.get("ammo_reserve"), 90, "rifle should start with configured reserve ammo")
	_assert_equal(GameState.current_weapon_slot, 0, "GameState should mirror current weapon slot")

func _test_pistol_hold_without_press_does_not_fire(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var pistol_profile: Resource = fixture["pistol_profile"]
	weapon_system.call("switch_to_slot", 1)
	_tick_weapon_system(weapon_system, player, float(pistol_profile.get("equip_duration")))
	var before_ammo: int = int(weapon_system.call("get_runtime_snapshot").get("ammo_in_mag", 0))
	_tick_weapon_system(weapon_system, player, 0.1, false, true)
	var after_ammo: int = int(weapon_system.call("get_runtime_snapshot").get("ammo_in_mag", 0))
	_assert_equal(after_ammo, before_ammo, "semi-auto pistol should not fire from held input alone")

func _test_pistol_press_fires_once_then_requires_release(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var pistol_profile: Resource = fixture["pistol_profile"]
	weapon_system.call("switch_to_slot", 1)
	_tick_weapon_system(weapon_system, player, float(pistol_profile.get("equip_duration")))
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	var first_snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(first_snapshot.get("ammo_in_mag"), 11, "pistol should consume one round on click")
	_tick_weapon_system(weapon_system, player, 0.35, false, true)
	var second_snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(second_snapshot.get("ammo_in_mag"), 11, "pistol should not chain-fire while button stays held")

func _test_rifle_hold_repeats_after_cooldown(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	_tick_weapon_system(weapon_system, player, 0.01, false, true)
	_tick_weapon_system(weapon_system, player, 0.12, false, true)
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(snapshot.get("ammo_in_mag"), 28, "auto rifle should fire again once cooldown expires while held")

func _test_reload_ignored_when_mag_full(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	weapon_system.call("request_reload")
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_true(not bool(snapshot.get("is_reloading", false)), "reload should stay idle when magazine is already full")
	_assert_equal(String(GameState.weapon_status_text), "", "full-mag reload request should not push HUD status")

func _test_reload_refills_mag_and_consumes_reserve(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var rifle_profile: Resource = fixture["rifle_profile"]
	var state: Dictionary = _current_state(weapon_system)
	state["ammo_in_mag"] = 20
	state["ammo_reserve"] = 5
	weapon_system.call("_store_current_state", state)
	weapon_system.call("request_reload")
	_assert_true(bool(weapon_system.call("get_runtime_snapshot").get("is_reloading", false)), "reload should start for partial rifle mag")
	_tick_weapon_system(weapon_system, player, float(rifle_profile.get("reload_duration")) + 0.05, false, false)
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(snapshot.get("ammo_in_mag"), 25, "reload should top off using available reserve ammo")
	_assert_equal(snapshot.get("ammo_reserve"), 0, "reload should consume the reserve used to fill the magazine")
	_assert_true(not bool(snapshot.get("is_reloading", false)), "reload should finish after timer elapses")

func _test_empty_mag_fire_triggers_reload(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var state: Dictionary = _current_state(weapon_system)
	state["ammo_in_mag"] = 0
	state["ammo_reserve"] = 7
	weapon_system.call("_store_current_state", state)
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(snapshot.get("ammo_in_mag"), 0, "empty-mag trigger pull should not underflow ammo")
	_assert_true(bool(snapshot.get("is_reloading", false)), "empty-mag trigger pull should begin reload when reserve exists")

func _test_switch_to_slot_cancels_reload_and_respects_equip_lock(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var pistol_profile: Resource = fixture["pistol_profile"]
	var rifle_state: Dictionary = _current_state(weapon_system)
	rifle_state["ammo_in_mag"] = 10
	rifle_state["ammo_reserve"] = 20
	weapon_system.call("_store_current_state", rifle_state)
	weapon_system.call("request_reload")
	weapon_system.call("switch_to_slot", 1)
	var states_after_switch: Array = _weapon_states(weapon_system)
	_assert_true(not bool((states_after_switch[0] as Dictionary).get("is_reloading", false)), "switching away should cancel reload on previous weapon")
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	var equip_locked_snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(equip_locked_snapshot.get("ammo_in_mag"), 12, "equip lock should block firing immediately after switch")
	_tick_weapon_system(weapon_system, player, float(pistol_profile.get("equip_duration")) + 0.02, false, false)
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	var post_equip_snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(post_equip_snapshot.get("ammo_in_mag"), 11, "weapon should fire once equip duration has elapsed")

func _test_pattern_index_resets_after_recovery_delay(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var rifle_profile: Resource = fixture["rifle_profile"]
	_tick_weapon_system(weapon_system, player, 0.01, false, true)
	var early_state: Dictionary = _current_state(weapon_system)
	_assert_equal(early_state.get("pattern_index"), 1, "first rifle shot should advance pattern index")
	_tick_weapon_system(weapon_system, player, float(rifle_profile.get("pattern_reset_delay")) - 0.1, false, false)
	var mid_state: Dictionary = _current_state(weapon_system)
	_assert_equal(mid_state.get("pattern_index"), 1, "pattern should not reset before recovery delay completes")
	_tick_weapon_system(weapon_system, player, 0.2, false, false)
	var recovered_state: Dictionary = _current_state(weapon_system)
	_assert_equal(recovered_state.get("pattern_index"), 0, "pattern should reset after enough idle recovery time")

func _test_hud_uses_familiar_information_zones(fixture: Dictionary) -> void:
	var hud: CanvasLayer = _spawn_combat_hud(fixture)
	GameState.player_health = 74
	GameState.sync_weapon_state("\u624b\u67aa", 4, 24, "", 0.0, 0.0, 1)
	hud.call("update_display", GameState.get_hud_snapshot())

	var hud_root: Control = hud.get_node("HudRoot")
	var health_value: Label = hud.get_node("HudRoot/BottomLeft/Margin/Row/HealthText/Value")
	var weapon_label: Label = hud.get_node("HudRoot/BottomRight/Margin/Row/WeaponBlock/Weapon")
	var magazine_label: Label = hud.get_node("HudRoot/BottomRight/Margin/Row/AmmoMagazine")
	var reserve_label: Label = hud.get_node("HudRoot/BottomRight/Margin/Row/AmmoReserve")
	var round_state_label: Label = hud.get_node("HudRoot/TopCenter/Margin/Stack/RoundState")
	var round_panel: PanelContainer = hud.get_node("HudRoot/TopCenter")
	var health_panel: PanelContainer = hud.get_node("HudRoot/BottomLeft")
	var ammo_panel: PanelContainer = hud.get_node("HudRoot/BottomRight")

	_assert_true(hud_root.visible, "combat HUD should be visible during live play")
	_assert_equal(health_value.text, "74", "health should use a concise numeric value in the lower-left zone")
	_assert_true(weapon_label.text.contains("[2]") and weapon_label.text.contains("\u624b\u67aa"), "weapon slot and name should stay together in the lower-right zone")
	_assert_equal(magazine_label.text, "4", "magazine count should remain the dominant ammo number")
	_assert_equal(reserve_label.text, "24", "reserve count should remain separate from magazine ammo")
	_assert_equal(round_state_label.text, "LIVE", "round state should use the compact classic HUD label")
	_assert_float_close(round_panel.anchor_left, 0.5, 0.001, "round context should stay centered at the top")
	_assert_float_close(health_panel.anchor_bottom, 1.0, 0.001, "health should stay anchored to the lower-left")
	_assert_float_close(ammo_panel.anchor_left, 1.0, 0.001, "ammo should stay anchored to the lower-right")

	GameState.set_menu_state(true)
	hud.call("update_display", GameState.get_hud_snapshot())
	_assert_true(not hud_root.visible, "combat HUD should hide while the menu is open")

func _test_hits_dummy_registers_damage_and_updates_hud(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var hud: CanvasLayer = _spawn_combat_hud(fixture)
	_spawn_target_dummy(fixture, 100)
	var shot_results: Array = []
	weapon_system.connect("shot_resolved", Callable(self, "_capture_shot_result").bind(shot_results), CONNECT_ONE_SHOT)
	await _await_world_ready()
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	_assert_equal(shot_results.size(), 1, "dummy hit test should emit exactly one shot result")
	var result: Dictionary = shot_results[0] if not shot_results.is_empty() else {}
	var damage_result: Dictionary = result.get("damage_result", {}) as Dictionary
	_assert_true(bool(result.get("hit", false)), "firing at dummy should register a world hit")
	_assert_true(bool(damage_result.get("hit", false)), "firing at dummy should include damage result")
	_assert_equal(int(GameState.hit_count), 1, "dummy hit should increment GameState hit counter")
	_assert_equal(int(GameState.kill_count), 0, "non-lethal dummy hit should not increment kill counter")
	hud.call("update_display", GameState.get_hud_snapshot())
	var magazine_label: Label = hud.get_node("HudRoot/BottomRight/Margin/Row/AmmoMagazine")
	var reserve_label: Label = hud.get_node("HudRoot/BottomRight/Margin/Row/AmmoReserve")
	var stats_label: Label = hud.get_node("HudRoot/TopRight/Margin/Stats")
	_assert_equal(magazine_label.text, "29", "HUD magazine should reflect one rifle round spent after hit")
	_assert_equal(reserve_label.text, "90", "HUD reserve should remain unchanged after a normal shot")
	_assert_true(stats_label.text.contains("HITS 1"), "HUD stats should show one registered hit")

func _test_kill_shot_registers_kill_and_updates_hud(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var rifle_profile: Resource = fixture["rifle_profile"]
	rifle_profile.set("damage", 100)
	var hud: CanvasLayer = _spawn_combat_hud(fixture)
	_spawn_target_dummy(fixture, 40)
	var shot_results: Array = []
	weapon_system.connect("shot_resolved", Callable(self, "_capture_shot_result").bind(shot_results), CONNECT_ONE_SHOT)
	await _await_world_ready()
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	_assert_equal(shot_results.size(), 1, "kill shot test should emit exactly one shot result")
	var result: Dictionary = shot_results[0] if not shot_results.is_empty() else {}
	var damage_result: Dictionary = result.get("damage_result", {}) as Dictionary
	_assert_true(bool(damage_result.get("killed", false)), "kill shot should flag damage result as killed")
	_assert_equal(int(GameState.hit_count), 1, "kill shot should still count as a hit")
	_assert_equal(int(GameState.kill_count), 1, "kill shot should increment GameState kill counter")
	hud.call("update_display", GameState.get_hud_snapshot())
	var stats_label: Label = hud.get_node("HudRoot/TopRight/Margin/Stats")
	_assert_true(stats_label.text.contains("HITS 1"), "HUD stats should keep hit counter after kill shot")
	_assert_true(stats_label.text.contains("KILLS 1"), "HUD stats should show one kill after lethal hit")

func _test_terrain_hit_does_not_increment_hit_count(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var player: CharacterBody3D = fixture["player"]
	var hud: CanvasLayer = _spawn_combat_hud(fixture)
	_spawn_test_wall(fixture)
	var shot_results: Array = []
	weapon_system.connect("shot_resolved", Callable(self, "_capture_shot_result").bind(shot_results), CONNECT_ONE_SHOT)
	await _await_world_ready()
	_tick_weapon_system(weapon_system, player, 0.01, true, true)
	_assert_equal(shot_results.size(), 1, "terrain hit test should emit exactly one shot result")
	var result: Dictionary = shot_results[0] if not shot_results.is_empty() else {}
	var damage_result: Dictionary = result.get("damage_result", {}) as Dictionary
	_assert_true(bool(result.get("hit", false)), "terrain collider should still count as a world hit")
	_assert_true(damage_result.is_empty(), "terrain hit should not include target damage payload")
	_assert_equal(int(GameState.hit_count), 0, "terrain hit should not increment GameState hit counter")
	_assert_equal(int(GameState.kill_count), 0, "terrain hit should not increment kill counter")
	hud.call("update_display", GameState.get_hud_snapshot())
	var stats_label: Label = hud.get_node("HudRoot/TopRight/Margin/Stats")
	_assert_true(stats_label.text.contains("HITS 0"), "HUD stats should stay at zero hits after terrain shot")

func _test_invalid_profile_does_not_shift_runtime_slots(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture["weapon_system"]
	var rifle_profile: Resource = fixture["rifle_profile"]
	var pistol_profile: Resource = fixture["pistol_profile"]
	weapon_system.set("weapon_profiles", [Resource.new(), rifle_profile, pistol_profile])
	weapon_system.call("configure_default_loadout", false)

	var rifle_snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(rifle_snapshot.get("weapon_name"), rifle_profile.get("display_name"), "invalid resources should not displace the valid rifle from runtime slot 0")
	weapon_system.call("switch_to_slot", 1)
	var pistol_snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
	_assert_equal(pistol_snapshot.get("weapon_name"), pistol_profile.get("display_name"), "runtime slot 1 should still map to the pistol after invalid resources are skipped")
