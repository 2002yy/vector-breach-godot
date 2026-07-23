extends Node

const ACTOR_SCENE = preload("res://scenes/combat/TacticalActor.tscn")
const PLAYER_SCENE = preload("res://scenes/player/Player.tscn")
const ShapeBuilder = preload("res://scripts/level/ShapeBuilder.gd")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("bot_configuration_uses_route_and_classic_timing", _test_bot_configuration_uses_route_and_classic_timing)
	await _run_test("freeze_holds_then_live_patrols", _test_freeze_holds_then_live_patrols)
	await _run_test("opponent_sound_triggers_investigation", _test_opponent_sound_triggers_investigation)
	await _run_test("visible_enemy_is_acquired_then_burst_fired", _test_visible_enemy_is_acquired_then_burst_fired)
	await _run_test("bot_uses_ladder_and_water_semantics", _test_bot_uses_ladder_and_water_semantics)
	if _failures.is_empty():
		print("[TacticalBotTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return
	push_error("[TacticalBotTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_test(test_name: String, callable: Callable) -> void:
	var before := _failures.size()
	await callable.call()
	if _failures.size() == before:
		_passes += 1
		print("[TacticalBotTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _make_fixture() -> Dictionary:
	GameState.reset_runtime_state()
	GameState.player_team = "T"
	GameState.player_spawn = Vector3.ZERO
	RoundManager.set_warmup()
	var world := Node3D.new()
	add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	floor_shape.shape = box
	floor.position = Vector3(0.0, -0.1, 0.0)
	floor.add_child(floor_shape)
	world.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 1.05, 0.0)
	world.add_child(player)
	player.call("set_controls_enabled", false)
	var actor := ACTOR_SCENE.instantiate() as CharacterBody3D
	actor.position = Vector3(0.0, 1.15, 6.0)
	world.add_child(actor)
	await get_tree().physics_frame
	return {"world": world, "player": player, "actor": actor}

func _cleanup_fixture(fixture: Dictionary) -> void:
	(fixture.world as Node).queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func _test_bot_configuration_uses_route_and_classic_timing() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.call("configure_from_record", {
		"name": "配置测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.28, "aiAimAcquisitionTime": 0.24,
		"routePoints": [[0.0, 6.0], [4.0, 6.0], [8.0, 6.0]],
	})
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(bool(ai.get("enabled", false)), "authored enemy record should enable its bot brain")
	_assert_equal(int(ai.get("route_points", 0)), 3, "bot should parse authored route anchors into its navigation path")
	_assert_equal(String(ai.get("state", "")), "HOLD", "bot should remain held before live round state")
	await _cleanup_fixture(fixture)

func _test_freeze_holds_then_live_patrols() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.global_position = Vector3(-6.0, 1.15, 5.0)
	actor.call("configure_from_record", {
		"name": "巡逻测试队友", "team": "friendly", "aiEnabled": true,
		"routePoints": [[-6.0, 5.0], [6.0, 5.0]],
	})
	RoundManager.start_round()
	var frozen_position := actor.global_position
	for _frame in range(12):
		await get_tree().physics_frame
	_assert_true(Vector2(actor.global_position.x - frozen_position.x, actor.global_position.z - frozen_position.z).length() < 0.05, "freeze time should hold bot horizontal movement")
	RoundManager.set_live()
	for _frame in range(30):
		await get_tree().physics_frame
	_assert_true(actor.global_position.distance_to(frozen_position) > 0.35, "live round should release the bot onto its route")
	await _cleanup_fixture(fixture)

func _test_opponent_sound_triggers_investigation() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.global_position = Vector3(0.0, 1.15, 8.0)
	actor.rotation.y = PI
	actor.call("configure_from_record", {"name": "听觉测试敌人", "team": "enemy", "aiEnabled": true})
	RoundManager.set_live()
	var accepted := bool(actor.call("notify_ai_sound", Vector3(5.0, 1.0, 8.0), 12.0, "T"))
	for _frame in range(8):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(accepted, "enemy sound inside the audible radius should enter bot memory")
	_assert_equal(String(ai.get("state", "")), "INVESTIGATE", "heard opponent without vision should trigger investigate state")
	_assert_true(actor.global_position.x > 0.05, "investigating bot should move toward the remembered sound")
	await _cleanup_fixture(fixture)

func _test_visible_enemy_is_acquired_then_burst_fired() -> void:
	var fixture := await _make_fixture()
	var player := fixture.player as CharacterBody3D
	var actor := fixture.actor as CharacterBody3D
	actor.call("configure_from_record", {
		"name": "射击测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05, "aiDamage": 8,
	})
	RoundManager.set_live()
	for _frame in range(90):
		await get_tree().physics_frame
		if GameState.player_health < 100:
			break
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("shots", 0)) > 0, "visible enemy should be acquired before the bot pulls the trigger")
	_assert_true(GameState.player_health < 100, "bot hitscan should use the shared player damage path")
	_assert_true(String(ai.get("state", "")) in ["ENGAGE", "ACQUIRE"], "combat bot should remain in a combat state while target is visible")
	await _cleanup_fixture(fixture)

func _test_bot_uses_ladder_and_water_semantics() -> void:
	var fixture := await _make_fixture()
	var world := fixture.world as Node3D
	var actor := fixture.actor as CharacterBody3D
	var geometry := Node3D.new()
	world.add_child(geometry)
	ShapeBuilder.build_into(geometry, {
		"arenaSize": 30,
		"ladders": [{"id": "ai-ladder", "x": 0.0, "z": 0.0, "sx": 1.2, "sz": 1.4, "h": 3.2, "bottomY": 0.1, "normal": [0, 1], "exitDirection": [0, -1]}],
		"waterVolumes": [{"id": "ai-water", "x": 8.0, "z": 0.0, "sx": 4.0, "sz": 4.0, "surfaceY": 2.1, "bottomY": 0.1}],
	})
	actor.global_position = Vector3(0.0, 1.15, 0.0)
	actor.call("configure_from_record", {
		"name": "通行测试队友", "team": "friendly", "aiEnabled": true,
		"routePoints": [[0.0, 1.15, 0.0], [0.0, 4.15, -2.5]],
	})
	RoundManager.set_live()
	for _frame in range(28):
		await get_tree().physics_frame
	_assert_true(actor.global_position.y > 1.35, "route point above a ladder should make the bot climb")
	actor.global_position = Vector3(8.0, 1.15, 0.0)
	actor.velocity = Vector3.ZERO
	for _frame in range(4):
		await get_tree().physics_frame
	var environment := actor.call("get_ai_environment_snapshot") as Dictionary
	_assert_true(bool(environment.get("in_water", false)), "bot environment sensor should enter authored water volumes")
	_assert_equal(float(environment.get("speed_multiplier", 1.0)), 0.52, "deep water should apply the shared deep-water speed tier")
	await _cleanup_fixture(fixture)
