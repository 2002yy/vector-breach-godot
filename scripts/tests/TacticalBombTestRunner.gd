extends Node

const ACTOR_SCENE = preload("res://scenes/combat/TacticalActor.tscn")
const C4_SCENE = preload("res://scenes/objective/C4Device.tscn")
const SANDBOX_SCENE = preload("res://scenes/combat/CombatSandbox.tscn")
const WEAPON_PICKUP_SCRIPT = preload("res://scripts/combat/WorldWeaponPickup.gd")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("bot_carries_plants_c4_at_objective", _test_bot_carries_plants_c4_at_objective)
	await _run_test("ct_bot_defuses_planted_bomb", _test_ct_bot_defuses_planted_bomb)
	await _run_test("bot_targets_enemy_bot_not_only_player", _test_bot_targets_enemy_bot_not_only_player)
	await _run_test("teammate_report_shared_to_same_team", _test_teammate_report_shared_to_same_team)
	await _run_test("c4_drop_pickup_transfers_carrier", _test_c4_drop_pickup_transfers_carrier)
	await _run_test("combat_sandbox_assigns_bomb_carrier", _test_combat_sandbox_assigns_bomb_carrier)
	await _run_test("bot_buys_grenades_and_defuse_kit_in_freeze", _test_bot_buys_grenades_and_defuse_kit_in_freeze)
	await _run_test("bot_throws_smoke_toward_objective_before_plant", _test_bot_throws_smoke_toward_objective_before_plant)
	await _run_test("bot_uses_he_in_combat", _test_bot_uses_he_in_combat)
	await _run_test("bot_uses_flash_in_combat", _test_bot_uses_flash_in_combat)
	await _run_test("bot_picks_up_dropped_weapon", _test_bot_picks_up_dropped_weapon)
	await _run_test("combat_sandbox_splits_t_roles_between_sites", _test_combat_sandbox_splits_t_roles_between_sites)
	await _run_test("bot_economy_mode_changes_freeze_buying", _test_bot_economy_mode_changes_freeze_buying)
	await _run_test("bot_weapon_inventory_tracks_reserve", _test_bot_weapon_inventory_tracks_reserve)
	await _run_test("bot_grenade_velocity_scales_with_distance", _test_bot_grenade_velocity_scales_with_distance)
	await _run_test("refrag_report_goes_to_nearest_teammate", _test_refrag_report_goes_to_nearest_teammate)
	await _run_test("bot_saves_gun_when_low_health_and_eco", _test_bot_saves_gun_when_low_health_and_eco)
	if _failures.is_empty():
		print("[TacticalBombTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return
	push_error("[TacticalBombTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_test(test_name: String, callable: Callable) -> void:
	var before := _failures.size()
	await callable.call()
	if _failures.size() == before:
		_passes += 1
		print("[TacticalBombTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _make_fixture() -> Dictionary:
	GameState.reset_runtime_state()
	GameState.player_team = "CT"
	GameState.player_spawn = Vector3.ZERO
	RoundManager.set_warmup()
	var world := Node3D.new()
	add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	floor_shape.shape = box
	floor.position = Vector3(0.0, -0.1, 0.0)
	floor.add_child(floor_shape)
	world.add_child(floor)
	var c4 := C4_SCENE.instantiate() as Node3D
	c4.position = Vector3(0.0, 0.5, 0.0)
	world.add_child(c4)
	await get_tree().physics_frame
	return {"world": world, "c4": c4}

func _make_actor(world: Node3D, actor_name: String, team: String, position: Vector3, extra: Dictionary = {}) -> CharacterBody3D:
	var actor := ACTOR_SCENE.instantiate() as CharacterBody3D
	actor.position = position
	world.add_child(actor)
	var record := {
		"name": actor_name, "team": team, "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05,
	}
	for key in extra:
		record[key] = extra[key]
	actor.call("configure_from_record", record)
	return actor

func _cleanup_fixture(fixture: Dictionary) -> void:
	for group_name in ["grenade_projectiles", "smoke_volumes", "weapon_pickups"]:
		for node_variant in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node_variant):
				(node_variant as Node).queue_free()
	(fixture.world as Node).queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func _test_bot_carries_plants_c4_at_objective() -> void:
	var fixture := await _make_fixture()
	var c4 := fixture.c4 as Node3D
	c4.call("set_carried", "T")
	var actor := _make_actor(fixture.world as Node3D, "T安包手", "T", Vector3(0.0, 1.15, 6.0))
	var brain := actor.get_node("TacticalBotBrain")
	brain.call("set_c4_device", c4)
	brain.call("configure_objective", "plant", Vector3(0.0, 1.15, 0.0), "A", true)
	RoundManager.set_live()
	RoundManager.bomb_carried = true
	for _frame in range(320):
		await get_tree().physics_frame
	var objective := (actor.call("get_combat_snapshot") as Dictionary).get("objective", {}) as Dictionary
	_assert_equal(String(RoundManager.get_state_name()), "Bomb Planted", "T bomb carrier should complete a continuous plant interaction")
	_assert_equal(String(c4.get("device_state")), "planted", "planted C4 should move to the planted world state")
	_assert_true(not bool(objective.get("carrier", true)), "carrier flag should clear after planting")
	await _cleanup_fixture(fixture)

func _test_ct_bot_defuses_planted_bomb() -> void:
	var fixture := await _make_fixture()
	var c4 := fixture.c4 as Node3D
	RoundManager.set_live()
	RoundManager.bomb_carried = true
	RoundManager.plant_bomb("A")
	c4.call("plant_at", Vector3(0.0, 0.5, 0.0), "A")
	var actor := _make_actor(fixture.world as Node3D, "CT拆弹手", "CT", Vector3(0.0, 1.15, 6.0), {"defuseKit": true})
	var brain := actor.get_node("TacticalBotBrain")
	brain.call("set_c4_device", c4)
	brain.call("configure_objective", "defuse", Vector3(0.0, 1.15, 0.0), "A", false)
	for _frame in range(450):
		await get_tree().physics_frame
	_assert_equal(String(RoundManager.get_state_name()), "Round End", "CT bot defuse should close the round")
	_assert_equal(String(RoundManager.round_winner), "CT", "successful AI defuse should award CT")
	await _cleanup_fixture(fixture)

func _test_bot_targets_enemy_bot_not_only_player() -> void:
	var fixture := await _make_fixture()
	var t_actor := _make_actor(fixture.world as Node3D, "T目标", "T", Vector3(0.0, 1.15, -6.0))
	var ct_actor := _make_actor(fixture.world as Node3D, "CT射手", "CT", Vector3(0.0, 1.15, 0.0))
	RoundManager.set_live()
	var shots_seen := 0
	var t_health_seen := 100
	for _frame in range(240):
		await get_tree().physics_frame
		if is_instance_valid(ct_actor):
			var ai := (ct_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
			shots_seen = maxi(shots_seen, int(ai.get("shots", 0)))
		if is_instance_valid(t_actor):
			t_health_seen = mini(t_health_seen, int(t_actor.get("current_health")))
	_assert_true(shots_seen > 0, "CT bot should acquire and fire at the T bot, not only the local player")
	_assert_true(t_health_seen < 100, "bot-vs-bot hitscan should use the shared actor damage path")
	await _cleanup_fixture(fixture)

func _test_teammate_report_shared_to_same_team() -> void:
	var fixture := await _make_fixture()
	var listener := _make_actor(fixture.world as Node3D, "CT听报告", "CT", Vector3(0.0, 1.15, 8.0))
	var brain := listener.get_node("TacticalBotBrain")
	brain.call("notify_teammate_report", Vector3(4.0, 1.0, 4.0), "T")
	RoundManager.set_live()
	for _frame in range(30):
		await get_tree().physics_frame
	var ai := (listener.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("teammate_reports", 0)) >= 1, "teammate report should stay in the listener memory")
	_assert_equal(String(ai.get("state", "")), "INVESTIGATE", "shared teammate report should trigger investigation")
	_assert_true(listener.global_position.x > 0.1 or listener.global_position.z < 7.9, "listener should move toward the shared report")
	await _cleanup_fixture(fixture)

func _test_c4_drop_pickup_transfers_carrier() -> void:
	var fixture := await _make_fixture()
	var c4 := fixture.c4 as Node3D
	c4.call("set_carried", "T")
	var carrier := _make_actor(fixture.world as Node3D, "T原携带者", "T", Vector3(0.0, 1.15, 2.0))
	var pickup := _make_actor(fixture.world as Node3D, "T接手", "T", Vector3(0.0, 1.15, 1.5))
	carrier.get_node("TacticalBotBrain").call("set_c4_device", c4)
	carrier.get_node("TacticalBotBrain").call("configure_objective", "plant", Vector3(0.0, 1.15, 10.0), "A", true)
	pickup.get_node("TacticalBotBrain").call("set_c4_device", c4)
	pickup.get_node("TacticalBotBrain").call("configure_objective", "plant", Vector3(0.0, 1.15, 10.0), "A", false)
	RoundManager.set_live()
	RoundManager.bomb_carried = true
	var drop_position := carrier.global_position
	carrier.call("apply_hitscan_damage", 1000, drop_position + Vector3.UP * 0.6, 1.0, false, "CT", Vector3.ZERO)
	await get_tree().physics_frame
	c4.call("drop_at", drop_position)
	RoundManager.bomb_carried = false
	for _frame in range(60):
		await get_tree().physics_frame
	var objective := (pickup.call("get_combat_snapshot") as Dictionary).get("objective", {}) as Dictionary
	_assert_true(bool(objective.get("carrier", false)), "nearby T bot should pick up the dropped C4 and become carrier")
	_assert_equal(String(c4.get("device_state")), "carried", "dropped C4 should return to the carried state after pickup")
	_assert_true(bool(RoundManager.bomb_carried), "RoundManager should track the transferred bomb carrier")
	await _cleanup_fixture(fixture)

func _test_combat_sandbox_assigns_bomb_carrier() -> void:
	var fixture := await _make_fixture()
	var sandbox := SANDBOX_SCENE.instantiate() as Node3D
	(fixture.world as Node3D).add_child(sandbox)
	sandbox.call("set_c4_device", fixture.c4 as Node3D)
	var level_data := {
		"id": "bomb-test",
		"objectives": [{"id": "site-a", "x": 0.0, "z": -10.0}],
		"routes": {
			"attack": [[0.0, 6.0], [0.0, -10.0]],
			"defend": [[0.0, -10.0]],
		},
		"aiRouteProfiles": {},
		"teamActors": [
			{"name": "T1", "team": "T", "route": "attack", "x": 0.0, "z": 6.0, "aiEnabled": true},
			{"name": "T2", "team": "T", "route": "attack", "x": 2.0, "z": 6.0, "aiEnabled": true},
		],
		"combatTargets": [
			{"name": "CT1", "team": "enemy", "route": "defend", "x": 0.0, "z": -8.0, "aiEnabled": true},
		],
	}
	sandbox.call("load_for_level", level_data)
	await get_tree().physics_frame
	var carrier_found := false
	for child in sandbox.get_children():
		if child is CharacterBody3D and String((child as CharacterBody3D).get("team")) == "T":
			var snapshot := (child as CharacterBody3D).call("get_combat_snapshot") as Dictionary
			var objective := snapshot.get("objective", {}) as Dictionary
			if bool(objective.get("carrier", false)):
				carrier_found = true
	_assert_true(carrier_found, "CombatSandbox should designate one T bot as bomb carrier when the player is CT")
	_assert_equal(String((fixture.c4 as Node3D).get("device_state")), "carried", "C4 should start carried by the T side")
	await _cleanup_fixture(fixture)

func _test_bot_buys_grenades_and_defuse_kit_in_freeze() -> void:
	var fixture := await _make_fixture()
	var t_actor := _make_actor(fixture.world as Node3D, "T经济兵", "T", Vector3(0.0, 1.15, 4.0), {"aiMoney": 5000})
	var ct_actor := _make_actor(fixture.world as Node3D, "CT经济兵", "CT", Vector3(0.0, 1.15, 8.0), {"aiMoney": 2000})
	RoundManager.start_round()
	for _frame in range(12):
		await get_tree().physics_frame
	var t_ai := (t_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	var ct_ai := (ct_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(((t_ai.get("grenades", {}) as Dictionary).get("smoke_grenade", 0))) == 1, "T bot should buy a smoke grenade during freeze")
	_assert_true(int(t_ai.get("money", 800)) < 5000, "freeze purchases should consume bot money")
	_assert_true(bool(((ct_actor.call("get_combat_snapshot") as Dictionary).get("objective", {}) as Dictionary).get("defuse_kit", false)), "CT bot should buy a defuse kit during freeze")
	await _cleanup_fixture(fixture)

func _test_bot_throws_smoke_toward_objective_before_plant() -> void:
	var fixture := await _make_fixture()
	var c4 := fixture.c4 as Node3D
	c4.call("set_carried", "T")
	var actor := _make_actor(fixture.world as Node3D, "T烟雾手", "T", Vector3(0.0, 1.15, 6.0), {"aiGrenades": {"smoke_grenade": 1}})
	var brain := actor.get_node("TacticalBotBrain")
	brain.call("set_c4_device", c4)
	brain.call("configure_objective", "plant", Vector3(0.0, 1.15, 0.0), "A", true)
	RoundManager.set_live()
	RoundManager.bomb_carried = true
	for _frame in range(20):
		await get_tree().physics_frame
	var smoke_thrown := false
	for projectile_variant in get_tree().get_nodes_in_group("grenade_projectiles"):
		if String(projectile_variant.get("grenade_type")) == "smoke_grenade":
			smoke_thrown = true
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(smoke_thrown or int(((ai.get("grenades", {}) as Dictionary).get("smoke_grenade", 1))) == 0, "T bot should throw smoke toward the objective before planting")
	await _cleanup_fixture(fixture)

func _test_bot_uses_he_in_combat() -> void:
	var fixture := await _make_fixture()
	_make_actor(fixture.world as Node3D, "T目标", "T", Vector3(0.0, 1.15, -6.0))
	var ct_actor := _make_actor(fixture.world as Node3D, "CT投弹手", "CT", Vector3(0.0, 1.15, 0.0), {"aiGrenades": {"he_grenade": 1}})
	RoundManager.set_live()
	for _frame in range(150):
		await get_tree().physics_frame
	var he_thrown := false
	for projectile_variant in get_tree().get_nodes_in_group("grenade_projectiles"):
		if String(projectile_variant.get("grenade_type")) == "he_grenade":
			he_thrown = true
	var ai := (ct_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(he_thrown or int(((ai.get("grenades", {}) as Dictionary).get("he_grenade", 1))) == 0, "CT bot should throw HE at a close visible enemy")
	await _cleanup_fixture(fixture)

func _test_bot_uses_flash_in_combat() -> void:
	var fixture := await _make_fixture()
	_make_actor(fixture.world as Node3D, "T目标", "T", Vector3(0.0, 1.15, -6.0))
	var ct_actor := _make_actor(fixture.world as Node3D, "CT闪光手", "CT", Vector3(0.0, 1.15, 0.0), {"aiGrenades": {"flash_grenade": 1}})
	RoundManager.set_live()
	for _frame in range(60):
		await get_tree().physics_frame
	var flash_thrown := false
	for projectile_variant in get_tree().get_nodes_in_group("grenade_projectiles"):
		if String(projectile_variant.get("grenade_type")) == "flash_grenade":
			flash_thrown = true
	var ai := (ct_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(flash_thrown or int(((ai.get("grenades", {}) as Dictionary).get("flash_grenade", 1))) == 0, "CT bot should throw a flash at a close visible enemy")
	await _cleanup_fixture(fixture)

func _test_bot_picks_up_dropped_weapon() -> void:
	var fixture := await _make_fixture()
	var actor := _make_actor(fixture.world as Node3D, "T拾枪兵", "T", Vector3(0.0, 1.15, 0.0))
	var pickup := WEAPON_PICKUP_SCRIPT.new()
	(fixture.world as Node3D).add_child(pickup)
	pickup.configure({"weapon_id": "rifle", "slot_index": 0, "ammo_in_mag": 45, "ammo_reserve": 30}, actor.global_position)
	RoundManager.set_live()
	for _frame in range(20):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(not is_instance_valid(pickup), "nearby bot should consume the dropped weapon pickup")
	_assert_true(int(ai.get("ammo", 0)) >= 45, "pickup should refill the bot primary weapon ammo")
	await _cleanup_fixture(fixture)

func _test_combat_sandbox_splits_t_roles_between_sites() -> void:
	var fixture := await _make_fixture()
	var sandbox := SANDBOX_SCENE.instantiate() as Node3D
	(fixture.world as Node3D).add_child(sandbox)
	sandbox.call("set_c4_device", fixture.c4 as Node3D)
	var level_data := {
		"id": "role-test",
		"objectives": [{"id": "site-a", "x": 0.0, "z": -10.0}, {"id": "site-b", "x": 10.0, "z": -10.0}],
		"routes": {"attack": [[0.0, 6.0], [0.0, -10.0]], "defend": [[0.0, -10.0]]},
		"aiRouteProfiles": {},
		"teamActors": [
			{"name": "T1", "team": "T", "route": "attack", "x": 0.0, "z": 6.0, "aiEnabled": true},
			{"name": "T2", "team": "T", "route": "attack", "x": 2.0, "z": 6.0, "aiEnabled": true},
			{"name": "T3", "team": "T", "route": "attack", "x": 4.0, "z": 6.0, "aiEnabled": true},
		],
		"combatTargets": [{"name": "CT1", "team": "CT", "route": "defend", "x": 0.0, "z": -8.0, "aiEnabled": true}],
	}
	sandbox.call("load_for_level", level_data)
	await get_tree().physics_frame
	var roles: Array = []
	var diversion_target_x := INF
	for child in sandbox.get_children():
		if child is CharacterBody3D and String((child as CharacterBody3D).get("team")) == "T":
			var objective := ((child as CharacterBody3D).call("get_combat_snapshot") as Dictionary).get("objective", {}) as Dictionary
			roles.append(String(objective.get("role", "")))
			if String(objective.get("role", "")) == "diversion":
				diversion_target_x = float((objective.get("target", Vector3.ZERO) as Vector3).x)
	_assert_true("plant" in roles and "support" in roles and "diversion" in roles, "T roles should split between plant, support, and diversion")
	_assert_true(diversion_target_x > 5.0, "diversion role should target the second objective site")
	await _cleanup_fixture(fixture)

func _test_bot_economy_mode_changes_freeze_buying() -> void:
	var fixture := await _make_fixture()
	var force_actor := _make_actor(fixture.world as Node3D, "T强起", "T", Vector3(0.0, 1.15, 2.0), {"aiMoney": 5000})
	var eco_actor := _make_actor(fixture.world as Node3D, "T存钱", "T", Vector3(0.0, 1.15, 4.0), {"aiMoney": 1200})
	RoundManager.start_round()
	for _frame in range(12):
		await get_tree().physics_frame
	var force_ai := (force_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	var eco_ai := (eco_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_equal(String(force_ai.get("economy_mode", "")), "force", "high money should select a force-buy economy mode")
	_assert_true(int(((force_ai.get("grenades", {}) as Dictionary).get("smoke_grenade", 0))) == 1, "force buy should include a smoke grenade")
	_assert_equal(String(eco_ai.get("economy_mode", "")), "eco", "low money should select an eco/save mode")
	_assert_true(int(((eco_ai.get("grenades", {}) as Dictionary).get("smoke_grenade", 0))) == 0, "eco mode should save money instead of buying grenades")
	await _cleanup_fixture(fixture)

func _test_bot_weapon_inventory_tracks_reserve() -> void:
	var fixture := await _make_fixture()
	var actor := _make_actor(fixture.world as Node3D, "T库存兵", "T", Vector3(0.0, 1.15, 0.0))
	var record := actor.get_node("TacticalBotBrain").call("get_weapon_pickup_record") as Dictionary
	_assert_equal(String(record.get("weapon_id", "")), "rifle", "default bot inventory should report the primary rifle")
	_assert_equal(int(record.get("ammo_in_mag", 0)), 30, "bot inventory should track current magazine ammo")
	_assert_equal(int(record.get("ammo_reserve", 0)), 90, "bot inventory should track rifle reserve ammo separately")
	await _cleanup_fixture(fixture)

func _test_bot_grenade_velocity_scales_with_distance() -> void:
	var close_fixture := await _make_fixture()
	var close_actor := _make_actor(close_fixture.world as Node3D, "T近投", "T", Vector3(0.0, 1.15, 0.0), {"aiGrenades": {"smoke_grenade": 1}})
	var close_brain := close_actor.get_node("TacticalBotBrain")
	close_brain.call("_throw_ai_grenade", "smoke_grenade", Vector3(0.0, 1.15, 5.0))
	await get_tree().physics_frame
	var close_speed := 0.0
	for projectile_variant in get_tree().get_nodes_in_group("grenade_projectiles"):
		close_speed = maxf(close_speed, (projectile_variant as RigidBody3D).linear_velocity.length())
	await _cleanup_fixture(close_fixture)

	var far_fixture := await _make_fixture()
	var far_actor := _make_actor(far_fixture.world as Node3D, "T远投", "T", Vector3(0.0, 1.15, 0.0), {"aiGrenades": {"smoke_grenade": 1}})
	var far_brain := far_actor.get_node("TacticalBotBrain")
	far_brain.call("_throw_ai_grenade", "smoke_grenade", Vector3(0.0, 1.15, 20.0))
	await get_tree().physics_frame
	var far_speed := 0.0
	for projectile_variant in get_tree().get_nodes_in_group("grenade_projectiles"):
		far_speed = maxf(far_speed, (projectile_variant as RigidBody3D).linear_velocity.length())
	_assert_true(far_speed > close_speed, "longer AI grenade throws should use higher launch speed")
	await _cleanup_fixture(far_fixture)

func _test_refrag_report_goes_to_nearest_teammate() -> void:
	var fixture := await _make_fixture()
	var sandbox := SANDBOX_SCENE.instantiate() as Node3D
	(fixture.world as Node3D).add_child(sandbox)
	sandbox.call("set_c4_device", fixture.c4 as Node3D)
	var level_data := {
		"id": "refrag-test",
		"objectives": [{"id": "site-a", "x": 0.0, "z": -10.0}],
		"routes": {"attack": [[0.0, 6.0], [0.0, -10.0]], "defend": [[0.0, -10.0]]},
		"aiRouteProfiles": {},
		"teamActors": [{"name": "T1", "team": "T", "route": "attack", "x": 0.0, "z": -6.0, "aiEnabled": true}],
		"combatTargets": [
			{"name": "CT近", "team": "CT", "route": "defend", "x": 0.0, "z": 2.0, "aiEnabled": true},
			{"name": "CT远", "team": "CT", "route": "defend", "x": 0.0, "z": 8.0, "aiEnabled": true},
		],
	}
	sandbox.call("load_for_level", level_data)
	await get_tree().physics_frame
	var near_actor: CharacterBody3D
	var far_actor: CharacterBody3D
	for child in sandbox.get_children():
		if child is CharacterBody3D and String((child as CharacterBody3D).get("name")) == "CT近":
			near_actor = child as CharacterBody3D
		elif child is CharacterBody3D and String((child as CharacterBody3D).get("name")) == "CT远":
			far_actor = child as CharacterBody3D
	sandbox.call("_broadcast_teammate_report", Vector3(0.0, 1.0, 0.0), "T", "CT", far_actor)
	for _frame in range(6):
		await get_tree().physics_frame
	var near_ai := (near_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	var far_ai := (far_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(near_ai.get("teammate_reports", 0)) >= 1, "nearest teammate should receive the refrag report")
	_assert_equal(int(far_ai.get("teammate_reports", 0)), 0, "distant teammate should not receive the same report")
	await _cleanup_fixture(fixture)

func _test_bot_saves_gun_when_low_health_and_eco() -> void:
	var fixture := await _make_fixture()
	var actor := _make_actor(fixture.world as Node3D, "T保枪兵", "T", Vector3(0.0, 1.15, 0.0), {"aiMoney": 1200})
	var brain := actor.get_node("TacticalBotBrain")
	brain.set("economy_mode", "eco")
	actor.set("current_health", 25)
	RoundManager.set_live()
	for _frame in range(40):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(bool(ai.get("saving_gun", false)), "low-health eco bot should enter save-gun retreat")
	_assert_true(actor.global_position.z > 0.4, "save-gun retreat should move the bot backward to preserve its weapon")
	await _cleanup_fixture(fixture)
