extends SceneTree

const Receipt = preload("res://tools/authoring/SlidePathReceipt.gd")
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	assert(value, label)
	checks += 1


func _run() -> void:
	Engine.physics_ticks_per_second = 60
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	wall_shape.shape.size = Vector3(0.1, 10, 10)
	wall.add_child(wall_shape)
	root.add_child(wall)
	wall.position = Vector3(1.5, 0, 0)
	var actor := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.4
	shape.shape.height = 1.8
	actor.add_child(shape)
	actor.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	root.add_child(actor)
	await physics_frame
	await physics_frame
	actor.velocity = Vector3(120, 0, -120)
	actor.move_and_slide()
	var sample := Receipt.capture(actor, "fixture")
	_check(sample.slide_count >= 1, "actual diagonal wall produces slide collision")
	_check(actor.position.x < 1.11 and actor.position.z < -1.9, "actor really slides along wall")
	var sum := Vector3.ZERO
	for move in sample.movements:
		sum += Vector3(move.travel[0], move.travel[1], move.travel[2])
	_check(sum.x > 1.0 and sum.z > -1.2, "collision travel stops at first impact")
	var residual := actor.get_position_delta() - sum
	_check(
		residual.distance_to(actor.get_last_motion()) < 0.00001,
		"last clear submove matches terminal residual"
	)
	_check(
		residual.z < -0.8 and absf(residual.x) < 0.002,
		"terminal motion is wall slide including measured small normal recovery"
	)
	_check(
		Vector3(sample.start[0], sample.start[1], sample.start[2]).length() < 0.00001,
		"central movement start is recovered"
	)
	actor.position = Vector3(0, 0, 3)
	actor.velocity = Vector3(120, 0, 0)
	await physics_frame
	actor.move_and_slide()
	var stopped := Receipt.capture(actor, "fixture")
	var stopped_travel := Vector3.ZERO
	for move in stopped.movements:
		stopped_travel += Vector3(move.travel[0], move.travel[1], move.travel[2])
	_check(stopped.slide_count >= 1, "head-on motion has a real contact")
	_check(
		(actor.get_position_delta() - stopped_travel).length() < 0.00001,
		"terminal collision travel must not be appended again as last motion"
	)
	print("SLIDE_PATH_RECEIPT_OK checks=", checks)
	quit(0)
