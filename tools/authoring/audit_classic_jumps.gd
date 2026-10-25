extends SceneTree

const Survey = preload("res://tools/authoring/ClassicJumpSurvey.gd")
var stage: Node3D
var space: PhysicsDirectSpaceState3D
var samples: Array[Dictionary] = []
var rate := 60
var trial_player: CharacterBody3D
var collision_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args[0] not in ["discover", "verify", "qualify"]:
		push_error("Usage: discover level output.json OR verify manifest.json output.json [rate]")
		quit(1)
		return
	var manifest: Dictionary
	if args[0] != "discover":
		manifest = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		rate = int(args[3]) if args.size() > 3 else 60
	Engine.physics_ticks_per_second = rate
	assert(rate in [60, 120])
	var level: String = manifest.level if args[0] != "discover" else args[1]
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(level)
	assert(not data.is_empty())
	var source := String(data.runtime_collision_scene)
	var identity := {
		"level": level,
		"level_sha256": FileAccess.get_sha256("res://data/levels/%s.json" % level),
		"collision_path": source,
		"collision_sha256": FileAccess.get_sha256(source)
	}
	identity["collision_import_sha256"] = FileAccess.get_sha256(source + ".import")
	identity["engine_hash"] = Engine.get_version_info().hash
	var layout_path := String(
		data.get("match_manifest", "res://data/levels/match-local/dustline.json")
	)
	identity["layout_sha256"] = FileAccess.get_sha256(layout_path)
	var layout: Dictionary = preload("res://scripts/level/ClassicMatchLayout.gd").load_authored(
		data
	)
	if layout.is_empty():
		push_error("Installed authored layout does not match level/collision identity")
		quit(1)
		return
	if args[0] != "discover" and manifest.identity != identity:
		push_error("Frozen collision/level/layout identity changed; refusing stale jump points")
		quit(1)
		return
	stage = Node3D.new()
	root.add_child(stage)
	var geometry := (load(source) as PackedScene).instantiate()
	collision_root = geometry
	stage.add_child(geometry)
	var builder := (load("res://scenes/level/GrayboxLevel.tscn") as PackedScene).instantiate()
	builder.load_on_ready = false
	stage.add_child(builder)
	builder.call("_build_runtime_collision", geometry, true, true, source)
	for frame in range(5):
		await physics_frame
	space = stage.get_world_3d().direct_space_state
	var output: Dictionary
	if args[0] == "discover":
		var survey := Survey.discover(space, layout)
		output = {"schema": 1, "level": level, "identity": identity, "survey": survey, "cases": []}
		if not survey.flat.is_empty():
			output.cases.append(Survey.make_case("ordinary", survey.flat[0]))
		if not survey.critical.is_empty():
			output.cases.append(Survey.make_case("critical_landing", survey.critical[0]))
		if not survey.drops.is_empty():
			output.cases.append(Survey.make_case("edge", survey.drops[0]))
		if not survey.rises.is_empty():
			output.cases.append(Survey.make_case("run_up", survey.rises[0]))
			output.cases.append(Survey.make_case("crouch_jump", survey.rises[-1]))
		print(
			"JUMP_SURVEY ",
			level,
			" flat=",
			survey.flat.size(),
			" rises=",
			survey.rises.size(),
			" drops=",
			survey.drops.size()
		)
	elif args[0] == "qualify":
		output = {
			"schema": 1,
			"kind": "map_jump_qualification_evidence_v1",
			"level": level,
			"identity": identity,
			"physics_hz": rate,
			"manifest_sha256": FileAccess.get_sha256(args[1]),
			"points": []
		}
		for point in manifest.cases:
			var feet := Survey.vector(point.start) - Vector3.UP * 0.9
			var corridor := Survey.body_corridor(
				space, feet, Survey.vector(point.target_feet), point.kind == "crouch_jump"
			)
			var controls: Array[Dictionary] = []
			for mode in ["no_jump", "walk"]:
				controls.append(await _trial(point, "current", mode))
			if point.id == "run_up" and level == "mirage-classic-local":
				for scheme in ["current", "legacy_16", "modern_cs"]:
					for mode in ["jump_early", "jump_late"]:
						controls.append(await _trial(point, scheme, mode))
					if scheme != "current":
						for mode in ["no_jump", "walk"]:
							controls.append(await _trial(point, scheme, mode))
			output.points.append({"case": point.id, "corridor": corridor, "controls": controls})
	else:
		output = {
			"schema": 1,
			"level": level,
			"identity": identity,
			"physics_hz": rate,
			"manifest_sha256": FileAccess.get_sha256(args[1]),
			"results": []
		}
		for point in manifest.cases:
			for scheme in ["current", "legacy_16", "modern_cs"]:
				output.results.append(await _trial(point, scheme))
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	stage.queue_free()
	await process_frame
	await process_frame
	print("CLASSIC_MAP_JUMPS_WRITTEN ", args[2])
	quit(0)


func _record(sample: Dictionary) -> void:
	var contacts: Array[Dictionary] = []
	for index in range(trial_player.get_slide_collision_count()):
		var contact := trial_player.get_slide_collision(index)
		var collider = contact.get_collider()
		contacts.append(
			{
				"normal": Survey.array(contact.get_normal()),
				"position": Survey.array(contact.get_position()),
				"body": str(collider.get_path()) if collider is Node else "unknown"
			}
		)
	samples.append(
		{
			"contacts": contacts,
			"time": sample.input.sample_time,
			"jumped": sample.jumped,
			"grounded_before": sample.grounded_before,
			"grounded_after": sample.grounded_after,
			"position": Survey.array(sample.position),
			"velocity": Survey.array(sample.velocity)
		}
	)


func _trial(point: Dictionary, scheme: String, mode := "jump") -> Dictionary:
	var state: Node = root.get_node("GameState")
	state.call("reset_runtime_state")
	state.set("player_spawn", Survey.vector(point.start))
	state.set("player_spawn_yaw_radians", float(point.yaw))
	root.get_node("RoundManager").call("set_warmup")
	var player = load("res://scenes/player/Player.tscn").instantiate()
	player.set_script(load("res://scripts/tests/MovementTimelinePlayer.gd"))
	trial_player = player
	stage.add_child(player)
	for frame in range(rate / 2):
		await physics_frame
	var settled := Survey.array(player.global_position)
	var start_ok: bool = (
		player.is_on_floor()
		and player.global_position.distance_to(Survey.vector(point.start)) < 0.2
	)
	var timeline: Array[Dictionary] = []
	for event in point.timeline:
		var row: Dictionary = event.duplicate()
		if mode in ["no_jump", "walk"]:
			row["jump"] = false
			row["walk"] = mode == "walk"
		elif mode in ["jump_early", "jump_late"] and row.has("jump"):
			row.at = (0.15 if mode == "jump_early" else 0.55) + (0.0 if row.jump else 0.1)
		if row.has("direction"):
			row.direction = Vector2(row.direction[0], row.direction[1])
		timeline.append(row)
	player.timeline = timeline
	player.set_movement_scheme(scheme)
	samples = []
	player.movement_step.connect(_record)
	player.active = true
	player.set_controls_enabled(true)
	for frame in range(int(point.duration * rate)):
		await physics_frame
	player.set_controls_enabled(false)
	var landing := {}
	var jumped := false
	var airborne := false
	var apex := -INF
	var collisions := 0
	var support: Array[Dictionary] = []
	var target_entry := {}
	for row in samples:
		apex = maxf(apex, float(row.position[1]))
		jumped = jumped or bool(row.jumped)
		airborne = airborne or (jumped and not row.grounded_after)
		if airborne and row.grounded_after and landing.is_empty():
			landing = row
		if row.grounded_after and target_entry.is_empty():
			var feet_at := Survey.vector(row.position) - Vector3.UP * 0.9
			var target := Survey.vector(point.target_feet)
			if (
				Vector2(feet_at.x - target.x, feet_at.z - target.z).length() <= point.target_radius
				and absf(feet_at.y - target.y) <= point.target_height_tolerance
			):
				target_entry = row
	var control_mode := mode in ["no_jump", "walk"]
	if control_mode:
		landing = target_entry
	var distance := INF
	var height_error := INF
	if not landing.is_empty():
		var at := Survey.vector(landing.position) - Vector3.UP * 0.9
		var goal := Survey.vector(point.target_feet)
		distance = Vector2(at.x - goal.x, at.z - goal.z).length()
		height_error = absf(at.y - goal.y)
		for offset in [
			Vector3.ZERO,
			Vector3.LEFT * 0.3,
			Vector3.RIGHT * 0.3,
			Vector3.FORWARD * 0.3,
			Vector3.BACK * 0.3
		]:
			var ray := PhysicsRayQueryParameters3D.create(
				at + offset + Vector3.UP * 0.2, at + offset - Vector3.UP * 0.3, 1
			)
			ray.exclude = [player.get_rid()]
			var hit := space.intersect_ray(ray)
			if (
				not hit.is_empty()
				and hit.collider is Node
				and collision_root.is_ancestor_of(hit.collider)
			):
				if hit.normal.y >= 0.7:
					support.append(
						{
							"position": Survey.array(hit.position),
							"normal": Survey.array(hit.normal),
							"body": str(hit.collider.get_path())
						}
					)
		collisions = support.size()
	var reached: bool = (
		start_ok
		and (not jumped if control_mode else jumped and airborne)
		and collisions > 0
		and distance <= point.target_radius
		and height_error <= point.target_height_tolerance
	)
	var reason := "reached"
	if not start_ok:
		reason = "invalid_start"
	elif not control_mode and (not jumped or not airborne):
		reason = "no_takeoff"
	elif landing.is_empty() or collisions == 0:
		reason = "no_supported_landing"
	elif height_error > point.target_height_tolerance:
		reason = "wrong_elevation"
	elif distance > point.target_radius:
		reason = "outside_target"
	var result := {
		"mode": mode,
		"applied_timeline": timeline,
		"target_entry": target_entry,
		"reason": reason,
		"airborne": airborne,
		"id": point.id,
		"scheme": scheme,
		"start_valid": start_ok,
		"settled_start": settled,
		"jumped": jumped,
		"landed": not landing.is_empty(),
		"supported_by_frozen_collision": collisions > 0,
		"support": support,
		"target_reached": reached,
		"landing_distance": distance if is_finite(distance) else -1,
		"landing_height_error": height_error if is_finite(height_error) else -1,
		"apex_y": apex,
		"landing": landing,
		"trace": samples.duplicate(true)
	}
	var exported_timeline: Array[Dictionary] = []
	for event in timeline:
		var exported := event.duplicate(true)
		if exported.get("direction") is Vector2:
			exported.direction = [exported.direction.x, exported.direction.y]
		exported_timeline.append(exported)
	result.applied_timeline = exported_timeline
	player.queue_free()
	await process_frame
	return result
