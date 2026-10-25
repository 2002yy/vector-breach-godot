extends SceneTree
## Synthetic counterexamples only; never treated as real-map acceptance.

const Survey = preload("res://tools/authoring/ClassicJumpSurvey.gd")


func _initialize() -> void:
	_run.call_deferred()


func _box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at
	return body


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_box(stage, Vector3(-2.0, -0.1, 0), Vector3(3.9, 0.2, 4))
	_box(stage, Vector3(2.125, 0.3, 0), Vector3(3.75, 1.0, 4))
	var wall := _box(stage, Vector3(0, 2.5, 0), Vector3(0.12, 5.0, 4))
	for frame in range(3):
		await physics_frame
	var space := stage.get_world_3d().direct_space_state
	var start := Vector3(-0.5, 0, 0)
	var target := Vector3(1.1, 0.8, 0)
	assert(Survey.capsule_clear(space, target))
	var rejected := Survey._edge(space, start, Vector3.RIGHT, 0, 1.6)
	assert(not rejected.is_empty())
	assert(rejected.corridor.clear_arcs == 0)
	assert(rejected.corridor.status == "blocked_direct_route")
	var survey := Survey.discover(
		space, {"navigationGraph": {"points": [[-0.5, 0.96, 0]]}, "objectives": []}
	)
	assert(survey.rises.is_empty() and not survey.rejected.is_empty())
	wall.queue_free()
	for frame in range(3):
		await physics_frame
	var clear := Survey.body_corridor(space, start, target)
	assert(clear.clear_arcs > 0)
	# A thin lateral post misses the center ray but blocks a full player capsule.
	_box(stage, Vector3(0, 2.5, 0.34), Vector3(0.12, 5.0, 0.12))
	for frame in range(3):
		await physics_frame
	var side := Survey.body_corridor(space, start, target)
	assert(side.clear_arcs == 0)
	stage.queue_free()
	await process_frame
	print("JUMP_CORRIDOR_REGRESSIONS_OK 3 counterexamples")
	quit(0)
