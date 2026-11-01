extends RefCounted


static func check(host: Node, value: bool, label: String) -> void:
	host.call("_assert_true", value, label)


static func run(host: Node) -> void:
	var main: Node3D = host.call("_instantiate_main")
	await host.call("_await_main_ready")
	main.call("_on_map_selected", main.call("find_level_option_index", "test-collision-room"))
	await main.call("_on_start_pressed")
	await host.call("_await_main_ready")
	main.set_process(false)
	var player: CharacterBody3D = main.get_node("Player")
	player.set_physics_process(false)
	var enemy: CharacterBody3D
	var teammate: CharacterBody3D
	for actor in host.get_tree().get_nodes_in_group("combat_actors"):
		actor.set_physics_process(false)
		if actor.get("team") == GameState.player_team:
			teammate = actor
		else:
			enemy = actor
	check(
		host,
		is_instance_valid(enemy) and is_instance_valid(teammate),
		"radar fixture has both teams"
	)
	if not is_instance_valid(enemy) or not is_instance_valid(teammate):
		await host.call("_cleanup_main", main)
		return
	player.global_position = Vector3(0, 30, 0)
	enemy.global_position = Vector3(0, 30, -5)
	var camera: Camera3D = player.call("get_camera_node")
	camera.look_at(enemy.global_position + Vector3.UP * 0.25)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	check(
		host, main.call("_is_target_legally_spotted", enemy), "actual visible enemy enters memory"
	)
	var initial_records: Array = main.call("_build_radar_players")
	var first: Dictionary = {}
	for record in initial_records:
		if record.team != GameState.player_team:
			first = {"position": Vector3(record.x, record.y, record.z), "yaw": record.yaw}
	check(host, not first.is_empty(), "legal observation stores pose")
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 6, 0.4)
	shape.shape = box
	blocker.add_child(shape)
	main.add_child(blocker)
	blocker.global_position = Vector3(0, 31, -2.5)
	enemy.global_position = Vector3(2, 30, -6)
	enemy.rotation.y += 1.0
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	check(
		host, not main.call("_is_target_legally_spotted", enemy), "actual wall blocks observation"
	)
	var records: Array = main.call("_build_radar_players")
	for record in records:
		if record.team != GameState.player_team:
			var position := Vector3(record.x, record.y, record.z)
			check(
				host,
				position.is_equal_approx(first.get("position", Vector3.INF)),
				"lost-LOS position freezes"
			)
			check(
				host,
				is_equal_approx(float(record.yaw), float(first.get("yaw", -9))),
				"lost-LOS heading freezes"
			)
			check(host, record.spotted, "last-known marker remains during TTL")
	var memory = load("res://scripts/ui/RadarObservationMemory.gd").new()
	memory.observe(1, Vector3.ONE, 0.5, 100)
	var expired: Dictionary = memory.recall(1, 2601)
	check(host, expired.is_empty(), "expired memory removed without a live update")
	var display_script = load("res://scripts/ui/RadarDisplay.gd")
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var drawn := Vector2.UP.rotated(display_script.heading_angle(yaw, 0.0))
		check(
			host,
			drawn.is_equal_approx(Vector2(forward.x, forward.z)),
			"north-up heading matches 3D forward"
		)
		check(
			host,
			is_zero_approx(display_script.heading_angle(yaw, yaw)),
			"rotating heading remains up"
		)
	var settings: Node = host.get_node("/root/UserSettings")
	var old_rotate: bool = settings.radar_rotates
	settings.radar_rotates = false
	player.set("is_dead", true)
	teammate.global_position = Vector3(11, 35, -2)
	teammate.rotation.y = 0.9
	var spectator: Node = main.get("spectator")
	spectator.call("begin", player, GameState.player_team)
	var snapshot: Dictionary = main.call("_build_radar_snapshot")
	check(
		host,
		snapshot.get("view_actor_id", 0) == teammate.get_instance_id(),
		"spectator radar follows selected actor"
	)
	check(
		host,
		snapshot.player_position.is_equal_approx(Vector2(11, -2)),
		"spectator radar center follows teammate"
	)
	check(
		host,
		is_equal_approx(snapshot.get("view_yaw", -9.0), 0.9),
		"fixed north retains watched heading"
	)
	check(host, is_zero_approx(snapshot.player_yaw), "fixed north does not rotate map")
	var body: CollisionShape3D = teammate.get_node("CollisionShape3D")
	var feet: float = (
		body.global_position.y - body.shape.height * body.global_basis.y.length() * 0.5
	)
	check(host, is_equal_approx(snapshot.feet_height, feet), "feet and center use same actor")
	var radar: Control = main.get_node("CombatHud/HudRoot/Radar")
	radar.call("set_snapshot", snapshot)
	var changed := snapshot.duplicate(true)
	changed.view_actor_id = 0
	changed.feet_height = feet + 4.0
	changed.grounded = false
	radar.call("set_snapshot", changed)
	var debug: Dictionary = radar.call("get_debug_snapshot")
	check(
		host,
		is_equal_approx(debug.atlas_floor_height, feet + 4.0),
		"view switch resets previous floor even in air"
	)
	settings.radar_rotates = old_rotate
	spectator.call("stop")
	memory = null
	first.clear()
	await host.call("_cleanup_main", main)
