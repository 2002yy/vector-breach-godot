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


func _ready() -> void:
	process_physics_priority = -100
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if not running:
		return
	var keys: Array = []
	for event in point.native_timeline:
		if float(event.at) <= float(tick) / 60.0:
			keys = event["keys"]
	for key in ACTIONS:
		if key in keys:
			if not Input.is_action_pressed(ACTIONS[key]):
				Input.action_press(ACTIONS[key])
		else:
			Input.action_release(ACTIONS[key])
	tick += 1


func _record(sample: Dictionary) -> void:
	if not running:
		return
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	var feet: float = shape.global_position.y - shape.shape.height * 0.5
	floor_height = Atlas.floor_sample(floor_height, feet, sample.grounded_after, trace.is_empty())
	layer = Atlas.nearest_layer(atlas.layers, floor_height, layer)
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
		level.call(
			"_build_runtime_collision", geometry, true, true, manifest.identity.collision_path
		)
		GameState.reset_runtime_state()
		RoundManager.set_warmup()
		GameState.player_spawn = Vector3(point.start[0], point.start[1], point.start[2])
		GameState.player_spawn_yaw_radians = float(point.yaw)
		player = load("res://scenes/player/Player.tscn").instantiate()
		world.add_child(player)
		player.set_movement_scheme("current")
		player.set_controls_enabled(true)
		player.movement_step.connect(_record)
		tick = 0
		trace = []
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
	print("PLAYER_RADAR_ROUTES_OK maps=3")
	get_tree().quit(0)
