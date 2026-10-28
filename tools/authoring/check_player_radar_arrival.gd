extends Node
## Frozen input replay with the real Player; no human or whole-map acceptance.

const Atlas = preload("res://scripts/ui/RadarAtlas.gd")
const ACTIONS := {
	"W": "move_forward",
	"S": "move_backward",
	"A": "move_left",
	"D": "move_right",
	"Space": "jump",
	"Ctrl": "crouch",
	"Shift": "walk"
}
var player: CharacterBody3D
var point: Dictionary
var atlas: Dictionary
var tick := 0
var running := false
var trace: Array = []
var floor_height := 0.0
var layer := -1
var first_landing: Dictionary = {}
var airborne := false
var jumped := false
var collision_root: Node3D


func _ready() -> void:
	process_physics_priority = -100
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if not running:
		return
	tick += 1


func _record(sample: Dictionary) -> void:
	if not running:
		return
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	var feet: float = shape.global_position.y - shape.shape.height * 0.5
	floor_height = Atlas.floor_sample(floor_height, feet, sample.grounded_after, trace.is_empty())
	layer = Atlas.nearest_layer(atlas.layers, floor_height, layer)
	jumped = jumped or bool(sample.jumped)
	airborne = airborne or (jumped and not sample.grounded_after)
	if airborne and sample.grounded_after and first_landing.is_empty():
		var goal := Vector3(point.target_feet[0], point.target_feet[1], point.target_feet[2])
		var at := player.global_position - Vector3.UP * 0.9
		var supports := 0
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
			var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			if (
				not hit.is_empty()
				and hit.collider is Node
				and collision_root.is_ancestor_of(hit.collider)
				and hit.normal.y >= 0.7
			):
				supports += 1
		var distance := Vector2(at.x - goal.x, at.z - goal.z).length()
		var height_error := absf(at.y - goal.y)
		first_landing = {
			"tick": tick,
			"position": [at.x, at.y, at.z],
			"distance": distance,
			"height_error": height_error,
			"supports": supports,
			"target_radius": point.target_radius,
			"height_tolerance": point.target_height_tolerance,
			"reached":
			(
				distance <= point.target_radius
				and height_error <= point.target_height_tolerance
				and supports > 0
			)
		}
	trace.append(
		{
			"tick": tick,
			"delta": sample.delta,
			"position": [player.position.x, player.position.y, player.position.z],
			"feet": feet,
			"grounded": sample.grounded_after,
			"jumped": sample.jumped,
			"layer": layer
		}
	)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2 and not FileAccess.file_exists(args[1]))
	Engine.physics_ticks_per_second = 60
	for unused in range(3):
		await get_tree().physics_frame
	var rows: Array = []
	for name in ["dust2", "mirage", "inferno"]:
		var manifest_path: String = args[0] + "/" + name + "-current.json"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		assert(
			(
				FileAccess.get_sha256(manifest.identity.collision_path)
				== manifest.identity.collision_sha256
			)
		)
		for path in manifest.runtime_sha256:
			assert(FileAccess.get_sha256(path) == manifest.runtime_sha256[path])
		point = manifest.cases[0]
		atlas = JSON.parse_string(
			FileAccess.get_file_as_string(
				"res://assets/local_reference/radar/" + manifest.level + "/v4/atlas.json"
			)
		)
		var world := Node3D.new()
		add_child(world)
		var level = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
		level.load_on_ready = false
		world.add_child(level)
		var geometry = load(manifest.identity.collision_path).instantiate()
		world.add_child(geometry)
		collision_root = geometry
		level.call(
			"_build_runtime_collision", geometry, true, true, manifest.identity.collision_path
		)
		GameState.reset_runtime_state()
		RoundManager.set_warmup()
		GameState.player_spawn = Vector3(point.start[0], point.start[1], point.start[2])
		GameState.player_spawn_yaw_radians = float(point.yaw)
		player = load("res://scenes/player/Player.tscn").instantiate()
		player.set_script(load("res://tools/authoring/NativeRoutePlayer.gd"))
		world.add_child(player)
		player.set_movement_scheme("current")
		for frame in range(30):
			await get_tree().physics_frame
		var start_ok := (
			player.is_on_floor()
			and (
				player.global_position.distance_to(
					Vector3(point.start[0], point.start[1], point.start[2])
				)
				< 0.2
			)
		)
		var timeline: Array[Dictionary] = []
		for event in point.native_timeline:
			timeline.append(event.duplicate(true))
		player.timeline = timeline
		player.active = true
		player.set_controls_enabled(true)
		player.movement_step.connect(_record)
		tick = 0
		trace = []
		first_landing = {}
		airborne = false
		jumped = false
		layer = -1
		running = true
		while tick < 180:
			await get_tree().physics_frame
		running = false
		assert(not trace.is_empty())
		for action in ACTIONS.values():
			Input.action_release(action)
		var goal := Vector3(point.target_feet[0], point.target_feet[1], point.target_feet[2])
		rows.append(
			{
				"map": manifest.level,
				"case": point.parent_case,
				"manifest_sha256": FileAccess.get_sha256(manifest_path),
				"identity": manifest.identity,
				"runtime_sha256": manifest.runtime_sha256,
				"timeline": point.native_timeline,
				"target_feet": point.target_feet,
				"start_ok": start_ok,
				"first_landing": first_landing,
				"qualification": start_ok and bool(first_landing.get("reached", false)),
				"final_horizontal_distance":
				Vector2(player.position.x - goal.x, player.position.z - goal.z).length(),
				"trace": trace
			}
		)
		world.queue_free()
		await get_tree().process_frame
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(
		JSON.stringify(
			{"kind": "full_player_frozen_input", "human_acceptance": false, "maps": rows}, "\t"
		)
	)
	output.close()
	print("PLAYER_RADAR_ARRIVAL_WRITTEN maps=3")
	get_tree().quit(0)
