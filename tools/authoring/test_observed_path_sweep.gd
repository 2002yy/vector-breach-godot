extends SceneTree

const Sweep = preload("res://tools/authoring/ObservedPathSweep.gd")


func _initialize() -> void:
	_run.call_deferred()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	body.position = at
	return body


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var space := stage.get_world_3d().direct_space_state
	var poses := [{"position": [-1, 2, 0], "height": 1.8}, {"position": [1, 2, 0], "height": 1.8}]
	await physics_frame
	assert(Sweep.sweep(space, poses, 0.4).clear)
	var wall := _box(Vector3(0, 2, 0), Vector3(0.01, 4, 4))
	for frame in 3:
		await physics_frame
	var blocked: Dictionary = Sweep.sweep(space, poses, 0.4)
	assert(
		(
			not blocked.clear
			and blocked.segments[0].initial_overlaps == 0
			and blocked.segments[0].endpoint_overlaps == 0
		)
	)
	assert(blocked.segments[0].free_fraction < 1.0)
	wall.free()
	var floor_body := _box(Vector3(0, 0, 0), Vector3(8, 0.2, 8))
	for frame in 3:
		await physics_frame
	var support := [
		{"position": [-1, 0.9995, 0], "height": 1.8}, {"position": [1, 0.9995, 0], "height": 1.8}
	]
	var contact: Dictionary = Sweep.sweep(space, support, 0.4)
	assert(not contact.clear and contact.segments[0].initial_overlaps > 0)
	floor_body.free()
	poses[1].height = 1.2
	var transition: Dictionary = Sweep.sweep(space, poses, 0.4)
	assert(not transition.clear and transition.segments[0].height_transition)
	print("OBSERVED_PATH_SWEEP_OK checks=5")
	quit(0)
