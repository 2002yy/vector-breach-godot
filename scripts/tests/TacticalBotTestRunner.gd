extends Node

const ACTOR_SCENE = preload("res://scenes/combat/TacticalActor.tscn")
const PLAYER_SCENE = preload("res://scenes/player/Player.tscn")
const ShapeBuilder = preload("res://scripts/level/ShapeBuilder.gd")
const BotNavigationModel = preload("res://scripts/ai/BotNavigationModel.gd")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("bot_configuration_uses_route_and_classic_timing", _test_bot_configuration_uses_route_and_classic_timing)
	await _run_test("freeze_holds_then_live_patrols", _test_freeze_holds_then_live_patrols)
	await _run_test("opponent_sound_triggers_investigation", _test_opponent_sound_triggers_investigation)
	await _run_test("investigation_uses_connected_navigation_graph", _test_investigation_uses_connected_navigation_graph)
	await _run_test("navigation_attributes_prefer_cover_and_apply_crouch", _test_navigation_attributes_prefer_cover_and_apply_crouch)
	await _run_test("navigation_model_preserves_weighted_path_choice", _test_navigation_model_preserves_weighted_path_choice)
	await _run_test("blocked_bot_detects_stall_and_recovers", _test_blocked_bot_detects_stall_and_recovers)
	await _run_test("visible_enemy_is_acquired_then_burst_fired", _test_visible_enemy_is_acquired_then_burst_fired)
	await _run_test("bot_uses_ladder_and_water_semantics", _test_bot_uses_ladder_and_water_semantics)
	await _run_test("bot_reacts_to_damage_source", _test_bot_reacts_to_damage_source)
	await _run_test("bot_records_dynamic_danger_and_reroutes", _test_bot_records_dynamic_danger_and_reroutes)
	await _run_test("bot_switches_to_knife_at_close_range", _test_bot_switches_to_knife_at_close_range)
	await _run_test("bot_dodges_and_crouches_during_combat", _test_bot_dodges_and_crouches_during_combat)
	await _run_test("bot_retreats_at_low_health", _test_bot_retreats_at_low_health)
	await _run_test("bot_spray_plan_scales_with_distance", _test_bot_spray_plan_scales_with_distance)
	await _run_test("bot_strafes_without_orbiting_target", _test_bot_strafes_without_orbiting_target)
	await _run_test("bot_applies_recoil_compensation_during_spray", _test_bot_applies_recoil_compensation_during_spray)
	await _run_test("visual_actor_keeps_collision_and_hit_model_independent", _test_visual_actor_keeps_collision_and_hit_model_independent)
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

func _test_investigation_uses_connected_navigation_graph() -> void:
	var fixture := await _make_fixture()
	var world := fixture.world as Node3D
	var player := fixture.player as CharacterBody3D
	var actor := fixture.actor as CharacterBody3D
	player.set("is_dead", true)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(3.0, 3.0, 1.0)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	wall.position = Vector3(0.0, 1.5, 0.0)
	world.add_child(wall)
	actor.global_position = Vector3(0.0, 1.15, 8.0)
	actor.call("configure_from_record", {
		"name": "导航测试敌人", "team": "enemy", "aiEnabled": true,
		"navigationGraph": {
			"points": [[0.0, 1.15, 8.0], [4.0, 1.15, 8.0], [4.0, 1.15, -8.0], [0.0, 1.15, -8.0]],
			"links": [[0, 1], [1, 2], [2, 3]],
		},
	})
	RoundManager.set_live()
	actor.call("notify_ai_sound", Vector3(0.0, 1.0, -8.0), 24.0, "T")
	for _frame in range(30):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_equal(int(ai.get("navigation_nodes", 0)), 4, "bot should retain the authored connected navigation graph")
	_assert_true(actor.global_position.x > 0.45, "investigation should follow the connected route around a blocking wall")
	await _cleanup_fixture(fixture)

func _test_navigation_attributes_prefer_cover_and_apply_crouch() -> void:
	var fixture := await _make_fixture()
	var player := fixture.player as CharacterBody3D
	var actor := fixture.actor as CharacterBody3D
	player.set("is_dead", true)
	actor.global_position = Vector3(0.0, 1.15, 8.0)
	actor.call("configure_from_record", {
		"name": "掩体路线测试敌人", "team": "enemy", "aiEnabled": true,
		"navigationGraph": {
			"points": [
				[0.0, 1.15, 8.0], [-4.0, 1.15, 4.0], [-4.0, 1.15, -4.0], [0.0, 1.15, -8.0],
				[4.0, 1.15, 4.0], [4.0, 1.15, -4.0],
			],
			"links": [
				{"from": 0, "to": 1, "route": "covered", "cover": 0.9, "precise": true, "crouch": true},
				{"from": 1, "to": 2, "route": "covered", "cover": 0.9, "precise": true},
				{"from": 2, "to": 3, "route": "covered", "cover": 0.7},
				{"from": 0, "to": 4, "route": "exposed", "danger": 1.0},
				{"from": 4, "to": 5, "route": "exposed", "danger": 1.0},
				{"from": 5, "to": 3, "route": "exposed", "danger": 1.0},
			],
		},
	})
	RoundManager.set_live()
	actor.call("notify_ai_sound", Vector3(0.0, 1.0, -8.0), 24.0, "T")
	for _frame in range(18):
		await get_tree().physics_frame
	var actor_snapshot := actor.call("get_combat_snapshot") as Dictionary
	var ai := actor_snapshot.get("ai", {}) as Dictionary
	var active_link := ai.get("active_navigation_link", {}) as Dictionary
	_assert_true(actor.global_position.x < -0.05, "danger-weighted A* should choose the safer covered branch")
	_assert_equal(String(active_link.get("route", "")), "covered", "active edge metadata should preserve its authored route")
	_assert_true(bool(actor_snapshot.get("crouching", false)), "crouch navigation edges should lower the tactical actor hull")
	_assert_equal(int(ai.get("navigation_links", 0)), 6, "bot should retain all attributed navigation links")
	var crouched_head_hit := actor.call("apply_hitscan_damage", 1, actor.global_position + Vector3.UP * 0.34, 1.0, false) as Dictionary
	_assert_equal(String(crouched_head_hit.get("hit_group", "")), "head", "crouched visual head position should retain head-hit semantics")
	await _cleanup_fixture(fixture)

func _test_navigation_model_preserves_weighted_path_choice() -> void:
	var navigation: BotNavigationModel = BotNavigationModel.new()
	navigation.configure({
		"points": [[0.0, 0.0], [-4.0, 4.0], [-4.0, 8.0], [0.0, 12.0], [4.0, 4.0], [4.0, 8.0]],
		"links": [
			{"from": 0, "to": 1, "route": "covered", "cover": 0.9},
			{"from": 1, "to": 2, "route": "covered", "cover": 0.9},
			{"from": 2, "to": 3, "route": "covered", "cover": 0.7},
			{"from": 0, "to": 4, "route": "exposed", "danger": 1.0},
			{"from": 4, "to": 5, "route": "exposed", "danger": 1.0},
			{"from": 5, "to": 3, "route": "exposed", "danger": 1.0},
		],
	})
	var danger_events: Array[Dictionary] = []
	var path := navigation.find_path(0, 3, danger_events)
	_assert_equal(path, [0, 1, 2, 3], "extracted model should preserve covered-route A* ordering and weights")
	_assert_equal(navigation.link_count, 6, "extracted model should count authored bidirectional edges once")
	var first_link := navigation.find_link(0, 1, danger_events)
	_assert_equal(String(first_link.get("route", "")), "covered", "extracted model should preserve active-edge metadata")

func _test_blocked_bot_detects_stall_and_recovers() -> void:
	var fixture := await _make_fixture()
	var world := fixture.world as Node3D
	var player := fixture.player as CharacterBody3D
	var actor := fixture.actor as CharacterBody3D
	player.set("is_dead", true)
	_add_test_wall(world, Vector3(0.0, 1.5, 7.2), Vector3(4.0, 3.0, 0.5))
	_add_test_wall(world, Vector3(-0.85, 1.5, 8.0), Vector3(0.3, 3.0, 2.0))
	_add_test_wall(world, Vector3(0.85, 1.5, 8.0), Vector3(0.3, 3.0, 2.0))
	actor.global_position = Vector3(0.0, 1.15, 8.0)
	actor.call("configure_from_record", {
		"name": "脱困测试敌人", "team": "enemy", "aiEnabled": true,
		"routePoints": [[0.0, 8.0], [0.0, 0.0]],
	})
	RoundManager.set_live()
	for _frame in range(100):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("stuck_recoveries", 0)) >= 1, "bot should count a recovery after sustained navigation stall")
	_assert_true(actor.global_position.z > 8.15, "recovery steering should back the bot out of a three-sided obstruction")
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

func _test_bot_reacts_to_damage_source() -> void:
	var fixture := await _make_fixture()
	var player := fixture.player as CharacterBody3D
	var actor := fixture.actor as CharacterBody3D
	player.set("is_dead", true)
	actor.global_position = Vector3(0.0, 1.15, 8.0)
	actor.rotation.y = PI
	actor.call("configure_from_record", {
		"name": "受击感知测试敌人", "team": "enemy", "aiEnabled": true,
		"routePoints": [[0.0, 8.0], [0.0, -8.0]],
	})
	RoundManager.set_live()
	actor.call("apply_hitscan_damage", 8, actor.global_position + Vector3.UP * 0.6, 1.0, false, "T", Vector3(5.0, 1.0, 8.0))
	for _frame in range(10):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("damage_count", 0)) >= 1, "receiving a hit should record damage-source memory")
	_assert_true(String(ai.get("state", "")) in ["HOLD_ANGLE", "INVESTIGATE"], "damage without vision should turn the bot toward the source")
	_assert_true((ai.get("last_known_position", Vector3.ZERO) as Vector3).x > 3.0, "damage source position should become the last known enemy position")
	await _cleanup_fixture(fixture)

func _test_visual_actor_keeps_collision_and_hit_model_independent() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	var animation_player := actor.get_node("AnimationPlayer") as AnimationPlayer
	var visual := actor.get_node("ActorVisual") as Node3D
	_assert_true(visual.find_child("Vest_Mk1", true, false) != null, "shared visual GLB should expose the replaceable vest node")
	_assert_true(visual.find_child("Helmet_LowProfile", true, false) != null, "shared visual GLB should expose the optional helmet node")
	_assert_true(visual.find_child("WeaponSocket", true, false) != null, "shared visual GLB should expose the weapon mount socket")
	for animation_name in [&"tactical/idle", &"tactical/run", &"tactical/crouch", &"tactical/hit", &"tactical/death"]:
		_assert_true(animation_player.has_animation(animation_name), "AnimationPlayer should register %s" % animation_name)
	var skeleton: Skeleton3D
	for candidate in visual.find_children("*", "Skeleton3D", true, false):
		skeleton = candidate as Skeleton3D
		break
	_assert_true(skeleton != null, "shared visual GLB should import its Armature as a Skeleton3D")
	if skeleton != null:
		for bone_name in [&"root", &"hips", &"spine", &"chest", &"head", &"upper_arm_l", &"forearm_l", &"upper_arm_r", &"forearm_r", &"thigh_l", &"calf_l", &"thigh_r", &"calf_r"]:
			_assert_true(skeleton.find_bone(bone_name) >= 0, "imported skeleton should contain %s" % bone_name)
	var visual_snapshot := actor.call("get_visual_animation_snapshot") as Dictionary
	var imported_names := visual_snapshot.get("imported_names", []) as Array
	for clip_name in [&"idle", &"run", &"crouch", &"hit", &"death"]:
		_assert_true(imported_names.has(clip_name), "GLB should expose imported %s action" % clip_name)
	var capsule := actor.get_node("CollisionShape3D").shape as CapsuleShape3D
	_assert_true(is_equal_approx(capsule.height, 1.8), "visual asset should not replace the standing capsule hull")
	var zone_samples := {
		"head": Vector3(0.0, 0.66, 0.0), "chest": Vector3(0.0, 0.20, 0.0),
		"stomach": Vector3(0.0, -0.15, 0.0), "arms": Vector3(0.35, 0.10, 0.0),
		"legs": Vector3(0.0, -0.50, 0.0),
	}
	for expected_zone in zone_samples:
		var zone_hit := actor.call("apply_hitscan_damage", 1, actor.global_position + zone_samples[expected_zone], 1.0, false) as Dictionary
		_assert_equal(String(zone_hit.get("hit_group", "")), expected_zone, "visual asset should not replace %s hit resolution" % expected_zone)
	actor.call("set_ai_crouching", true)
	_assert_true(is_equal_approx(capsule.height, 1.2), "existing crouch collision behavior must remain authoritative over the visual")
	actor.call("apply_hitscan_damage", 500, actor.global_position + Vector3.UP * 0.66, 1.0, false)
	visual_snapshot = actor.call("get_visual_animation_snapshot") as Dictionary
	_assert_equal(visual_snapshot.get("active", &""), StringName("death"), "lethal damage should select the presentation-only death animation")
	_assert_true(bool(visual_snapshot.get("uses_imported", false)), "lethal damage should prefer the GLB-imported death action")
	_assert_true(not actor.is_queued_for_deletion(), "death animation should keep the non-colliding visual alive briefly")
	await _cleanup_fixture(fixture)

func _test_bot_records_dynamic_danger_and_reroutes() -> void:
	var fixture := await _make_fixture()
	var player := fixture.player as CharacterBody3D
	var actor := fixture.actor as CharacterBody3D
	player.set("is_dead", true)
	actor.global_position = Vector3(0.0, 1.15, 8.0)
	actor.call("configure_from_record", {
		"name": "动态危险测试敌人", "team": "enemy", "aiEnabled": true,
		"navigationGraph": {
			"points": [[0.0, 1.15, 8.0], [-4.0, 1.15, 4.0], [-4.0, 1.15, -4.0], [0.0, 1.15, -8.0], [4.0, 1.15, 4.0], [4.0, 1.15, -4.0]],
			"links": [[0, 1], [1, 2], [2, 3], [0, 4], [4, 5], [5, 3]],
		},
	})
	RoundManager.set_live()
	actor.call("record_ai_dynamic_danger", Vector3(4.0, 1.0, 0.0), 1.0)
	actor.call("notify_ai_sound", Vector3(0.0, 1.0, -8.0), 24.0, "T")
	for _frame in range(20):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("danger_events", 0)) >= 1, "recorded danger events should remain in bot memory")
	_assert_true(actor.global_position.x < -0.05, "dynamic danger near the exposed branch should reroute the bot to cover")
	await _cleanup_fixture(fixture)

func _test_bot_switches_to_knife_at_close_range() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.global_position = Vector3(0.0, 1.15, 2.0)
	actor.call("configure_from_record", {
		"name": "近战切枪测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05, "aiDamage": 8,
	})
	RoundManager.set_live()
	for _frame in range(150):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_equal(String(ai.get("weapon_id", "")), "knife", "close-range healthy bot should switch to the knife")
	_assert_true(int(ai.get("shots", 0)) > 0 or GameState.player_health < 100, "knife switch should lead to a melee attack")
	await _cleanup_fixture(fixture)

func _test_bot_dodges_and_crouches_during_combat() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.call("configure_from_record", {
		"name": "交火身法测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05, "aiDamage": 8, "aiCrouchChance": 1.0,
	})
	RoundManager.set_live()
	for _frame in range(240):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("dodges", 0)) > 0, "engaged bot should perform side-step dodges between bursts")
	_assert_true(int(ai.get("crouches", 0)) > 0, "engaged bot should occasionally crouch during combat")
	await _cleanup_fixture(fixture)

func _test_bot_retreats_at_low_health() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.call("configure_from_record", {
		"name": "撤退测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05, "aiDamage": 8,
	})
	actor.set("current_health", 12)
	RoundManager.set_live()
	for _frame in range(60):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_equal(String(ai.get("state", "")), "RETREAT", "low-health bot should enter retreat instead of holding position")
	_assert_true(actor.global_position.z > 8.15, "retreat should move the bot away from the visible enemy")
	await _cleanup_fixture(fixture)

func _test_bot_spray_plan_scales_with_distance() -> void:
	var close_fixture := await _make_fixture()
	var close_actor := close_fixture.actor as CharacterBody3D
	close_actor.global_position = Vector3(0.0, 1.15, 4.0)
	close_actor.call("configure_from_record", {
		"name": "近距离火力测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05,
	})
	RoundManager.set_live()
	for _frame in range(20):
		await get_tree().physics_frame
	var close_ai := (close_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_equal(String(close_ai.get("spray_decision", "")), "spray", "close range should choose a sustained spray plan")
	await _cleanup_fixture(close_fixture)

	var far_fixture := await _make_fixture()
	var far_actor := far_fixture.actor as CharacterBody3D
	far_actor.global_position = Vector3(0.0, 1.15, 28.0)
	far_actor.call("configure_from_record", {
		"name": "远距离火力测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05,
	})
	RoundManager.set_live()
	for _frame in range(20):
		await get_tree().physics_frame
	var far_ai := (far_actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_equal(String(far_ai.get("spray_decision", "")), "tap", "long range should choose single-shot taps")
	await _cleanup_fixture(far_fixture)

func _test_bot_strafes_without_orbiting_target() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.global_position = Vector3(0.0, 1.15, 6.0)
	actor.call("configure_from_record", {
		"name": "绕圈回归测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05, "aiDamage": 8,
	})
	RoundManager.set_live()
	var previous_angle := INF
	var total_turn := 0.0
	var min_angle := INF
	var max_angle := -INF
	for _frame in range(300):
		await get_tree().physics_frame
		var angle := atan2(actor.global_position.x, actor.global_position.z)
		if previous_angle != INF:
			var step := absf(angle - previous_angle)
			if step > PI:
				step = TAU - step
			total_turn += step
		previous_angle = angle
		min_angle = minf(min_angle, angle)
		max_angle = maxf(max_angle, angle)
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(int(ai.get("dodges", 0)) > 0, "engaged bot should still perform bounded side-step dodges")
	_assert_true(total_turn < TAU * 0.75, "bounded strafes should not accumulate a full orbit around the target")
	await _cleanup_fixture(fixture)

func _test_bot_applies_recoil_compensation_during_spray() -> void:
	var fixture := await _make_fixture()
	var actor := fixture.actor as CharacterBody3D
	actor.global_position = Vector3(0.0, 1.15, 4.0)
	actor.call("configure_from_record", {
		"name": "压枪补偿测试敌人", "team": "enemy", "aiEnabled": true,
		"aiReactionTime": 0.05, "aiAimAcquisitionTime": 0.05, "aiDamage": 8,
	})
	RoundManager.set_live()
	for _frame in range(180):
		await get_tree().physics_frame
	var ai := (actor.call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
	_assert_true(float(ai.get("recoil_compensation", 0.0)) > 0.0, "bot recoil compensation should be configured for spray control")
	_assert_true(int(ai.get("recoil_compensated_shots", 0)) > 0, "close-range spray should apply downward recoil compensation on later shots")
	await _cleanup_fixture(fixture)

func _add_test_wall(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	wall.position = position
	parent.add_child(wall)
