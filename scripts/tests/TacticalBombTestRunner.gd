extends Node

const ACTOR_SCENE = preload("res://scenes/combat/TacticalActor.tscn")
const C4_SCENE = preload("res://scenes/objective/C4Device.tscn")
const SANDBOX_SCENE = preload("res://scenes/combat/CombatSandbox.tscn")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("bot_carries_plants_c4_at_objective", _test_bot_carries_plants_c4_at_objective)
	await _run_test("ct_bot_defuses_planted_bomb", _test_ct_bot_defuses_planted_bomb)
	await _run_test("bot_targets_enemy_bot_not_only_player", _test_bot_targets_enemy_bot_not_only_player)
	await _run_test("teammate_report_shared_to_same_team", _test_teammate_report_shared_to_same_team)
	await _run_test("c4_drop_pickup_transfers_carrier", _test_c4_drop_pickup_transfers_carrier)
	await _run_test("combat_sandbox_assigns_bomb_carrier", _test_combat_sandbox_assigns_bomb_carrier)
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
