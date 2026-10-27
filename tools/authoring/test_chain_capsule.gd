extends SceneTree

const Sweep = preload("res://tools/authoring/ChainCapsuleSweep.gd")
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	assert(condition, label)
	checks += 1


func _segment(a: Array, b: Array, depth: float = 0.0) -> Dictionary:
	return {"from": a, "to": b, "height": 1.8, "local_offset": [0, 0, 0], "recovery_depth": depth}


func _run() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.02, 5, 5)
	wall.add_child(shape)
	root.add_child(wall)
	wall.position = Vector3(0, 3, 0)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(20, 0.1, 20)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	floor_body.position.y = -0.05
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var thin := Sweep.sweep(space, _segment([-2, 3, 0], [2, 3, 0]), 0.4)
	_check(thin.initial_overlaps == 0 and thin.endpoint_overlaps == 0, "thin wall endpoints clear")
	_check(thin.free_fraction < 1 and not thin.query_clear, "continuous cast detects thin wall")
	_check(thin.impact_contact.classification == "wall_or_ceiling", "wall contact classified")
	var support := Sweep.sweep(space, _segment([-3, 2, 0], [-3, 0.8, 0]), 0.4)
	_check(support.free_fraction < 1, "full capsule detects floor")
	_check(
		support.impact_contact.classification == "support", "support classified without exclusion"
	)
	var overlap := Sweep.sweep(space, _segment([-3, 0.8, 0], [-2, 0.8, 0]), 0.4)
	_check(
		overlap.initial_overlaps > 0 and not overlap.clearance_proven,
		"initial overlap cannot pass cast"
	)
	var tail := Sweep.sweep(space, _segment([-2, 3, 0], [-2, 3, 1]), 0.4)
	_check(tail.query_clear and tail.clearance_proven, "clear terminal tail queried")
	var recovery := Sweep.sweep(space, _segment([-2, 3, 0], [-2, 3, 1], 0.001), 0.4)
	_check(
		recovery.query_clear and not recovery.clearance_proven,
		"unresolved recovery cannot acquire authority"
	)
	print("CHAIN_CAPSULE_OK checks=", checks)
	quit(0)
