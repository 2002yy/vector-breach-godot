extends Node3D

const WEAPON_SYSTEM_SCENE = preload("res://scenes/combat/WeaponSystem.tscn")
const RIFLE_PROFILE = preload("res://data/weapons/rifle.tres")
const PISTOL_PROFILE = preload("res://data/weapons/pistol.tres")
const TEST_PLAYER_SCENE = preload("res://scenes/tests/support/TestPlayerStub.tscn")

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
		"pistol_profile": weapon_profiles[1]
	}

func _destroy_fixture(fixture: Dictionary) -> void:
	var weapon_system: Node = fixture.get("weapon_system", null)
	if weapon_system != null:
		weapon_system.queue_free()
	var player: Node = fixture.get("player", null)
	if player != null:
		player.queue_free()
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
