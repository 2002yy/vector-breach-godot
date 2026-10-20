extends RefCounted

const Catalog = preload("res://scripts/combat/WeaponCatalog.gd")
const Fire = preload("res://scripts/combat/FireArea.gd")


static func weapons(host: Node, fixture: Dictionary) -> void:
	var system: Node = fixture.weapon_system
	var player: CharacterBody3D = fixture.player
	for id in ["sniper", "smg", "shotgun"]:
		var profile = Catalog.profile(id)
		host.call(
			"_assert_true", profile.get_configuration_errors().is_empty(), id + " profile validates"
		)
		host.call("_assert_true", system.call("purchase_weapon", id), id + " replaces primary")
		host.call(
			"_assert_equal",
			system.call("get_slot_record", 0).weapon_id,
			id,
			"actual primary identity"
		)
	system.call("purchase_weapon", "sniper")
	var camera: Camera3D = player.call("get_camera_node")
	var before := camera.fov
	system.call("toggle_scope", player)
	host.call("_assert_true", camera.fov < before, "scope changes the real camera")
	system.call("switch_to_slot", 1)
	host.call("_assert_equal", camera.fov, before, "switching cancels scope")
	system.call("purchase_weapon", "shotgun")
	var dummy: StaticBody3D = host.call("_spawn_target_dummy", fixture, 500)
	dummy.position.z = -3.0
	await host.call("_await_world_ready")
	host.call("_tick_weapon_system", system, player, 0.6)
	var results: Array = []
	system.shot_resolved.connect(func(result: Dictionary) -> void: results.append(result))
	host.call("_tick_weapon_system", system, player, 0.01, true, true)
	host.call("_assert_equal", results.size(), 1, "one shell produces one shot event")
	host.call(
		"_assert_equal",
		system.call("get_slot_record", 0).ammo_in_mag,
		7,
		"seven pellets spend one shell"
	)
	if not results.is_empty():
		host.call(
			"_assert_true",
			results[0].get("pellet_impacts", []).size() > 1,
			"physical pellet rays reach target"
		)
		host.call("_assert_equal", GameState.hit_count, 1, "pellets count one hit per trigger")
		host.call(
			"_assert_equal",
			results[0].get("damage_events", []).size(),
			1,
			"same victim aggregated once"
		)
	system.call(
		"pickup_weapon",
		{"slot_index": 0, "weapon_id": "smg", "ammo_in_mag": 13, "ammo_reserve": 41}
	)
	host.call(
		"_assert_equal",
		system.call("get_slot_record", 0).ammo_in_mag,
		13,
		"pickup preserves real magazine"
	)
	host.call(
		"_assert_equal",
		system.call("get_slot_record", 0).ammo_reserve,
		41,
		"pickup never creates reserve"
	)


static func fire_barrier(host: Node, fixture: Dictionary) -> void:
	fixture.player.add_to_group("local_player")
	var events: Array = []
	GameState.area_damage_resolved.connect(
		func(result: Dictionary, shooter: String, team: String) -> void:
			events.append({"damage": result, "shooter": shooter, "team": team}),
		CONNECT_ONE_SHOT
	)
	var dummy: StaticBody3D = host.call("_spawn_target_dummy", fixture, 100)
	dummy.position = Vector3(0, 1.0, -3.0)
	var wall: StaticBody3D = host.call("_spawn_test_wall", fixture)
	wall.position.z = -1.5
	var fire := Fire.new()
	host.add_child(fire)
	host.call("_register_cleanup_node", fixture, fire)
	fire.configure(fixture.player, GameState.player_team, Vector3.ZERO)
	fire.set_physics_process(false)
	await host.call("_await_world_ready")
	var before: int = dummy.get("_current_health")
	fire.apply_damage_tick()
	host.call(
		"_assert_equal", dummy.get("_current_health"), before, "fire cannot burn through wall"
	)
	wall.position.x = 100.0
	await host.call("_await_world_ready")
	fire.apply_damage_tick()
	host.call(
		"_assert_true",
		int(dummy.get("_current_health")) < before,
		"unobstructed fire damages training targets"
	)
	host.call("_assert_equal", GameState.hit_count, 1, "player fire credits actual damage")
	host.call(
		"_assert_equal", events.size(), 1, "area damage uses its own event, not gunfire audio"
	)
	if not events.is_empty():
		host.call("_assert_equal", events[0].shooter, "你", "fire preserves owner attribution")
	RoundManager.set_paused_menu()
	var remaining := fire.remaining
	fire.call("_physics_process", 2.0)
	host.call("_assert_equal", fire.remaining, remaining, "pause freezes fire lifetime")
	await _fire_after_thrower_cleanup(host, fixture)


static func _fire_after_thrower_cleanup(host: Node, fixture: Dictionary) -> void:
	var tree := host.get_tree()
	var previous_scene := tree.current_scene
	tree.current_scene = host
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	collision.shape = box
	floor_body.add_child(collision)
	host.add_child(floor_body)
	floor_body.position = Vector3(20, -1, 0)
	host.call("_register_cleanup_node", fixture, floor_body)
	var owner_actor := CharacterBody3D.new()
	host.add_child(owner_actor)
	owner_actor.add_to_group("local_player")
	var projectile := preload("res://scripts/combat/GrenadeProjectile.gd").new()
	host.add_child(projectile)
	projectile.configure("fire_grenade", owner_actor, Vector3(20, 1, 0), Vector3.ZERO)
	projectile.set_physics_process(false)
	owner_actor.free()
	await host.call("_await_world_ready")
	var previous_zones := tree.get_nodes_in_group("fire_areas")
	projectile.call("_detonate")
	var zones := tree.get_nodes_in_group("fire_areas")
	host.call(
		"_assert_equal",
		zones.size(),
		previous_zones.size() + 1,
		"fire survives thrower cleanup before landing"
	)
	for zone in zones:
		if zone not in previous_zones:
			host.call("_register_cleanup_node", fixture, zone)
			host.call("_assert_equal", zone.get("_source_name"), "你", "launch attribution survives")
			host.call(
				"_assert_equal", zone.get("_team"), GameState.player_team, "launch team survives"
			)
	tree.current_scene = previous_scene
