extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Usage: level-id candidate-collision-resource output.json")
		quit(1)
		return
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(args[0])
	var stage := Node3D.new()
	root.add_child(stage)
	var baseline: Node3D = load(String(data.runtime_collision_scene)).instantiate()
	var candidate: Node3D = load(args[1]).instantiate()
	stage.add_child(baseline)
	stage.add_child(candidate)
	var shapes := [_bodies(baseline, 1), _bodies(candidate, 2)]
	for _frame in range(4):
		await physics_frame
	var points: Array = []
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(String(data.match_manifest))
	)
	var spawns: Dictionary = manifest.layout.matchSpawns
	for team in spawns:
		for index in range(spawns[team].size()):
			points.append({"id": "%s-%s" % [team, index], "position": spawns[team][index]})
	for site in data.landmarks:
		points.append({"id": site.name, "position": [site.x, site.y, site.z]})
	var space := stage.get_world_3d().direct_space_state
	for point in points:
		var position := Vector3(point.position[0], point.position[1], point.position[2])
		point["baseline"] = _ground(space, position, 1)
		point["candidate"] = _ground(space, position, 2)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.8
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = position
		query.collision_mask = 2
		point["candidate_capsule_overlaps"] = space.intersect_shape(query).size()
	var receipt := {
		"level": args[0],
		"baseline_sha256": FileAccess.get_sha256(String(data.runtime_collision_scene)),
		"candidate_sha256": FileAccess.get_sha256(args[1]),
		"body_counts": shapes,
		"points": points,
	}
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	output.store_string(JSON.stringify(receipt, "\t"))
	output.close()
	print("CLASSIC_COLLISION_AUDIT_WRITTEN=" + args[2])
	stage.free()
	quit(0)


func _bodies(node: Node, mask: int) -> int:
	var count := 0
	if node is MeshInstance3D and String(node.name).begins_with("COLLISION_"):
		var mesh := node as MeshInstance3D
		var body := StaticBody3D.new()
		body.collision_layer = mask
		var shape := CollisionShape3D.new()
		shape.shape = mesh.mesh.create_trimesh_shape()
		body.add_child(shape)
		mesh.add_child(body)
		count += 1
	for child in node.get_children():
		count += _bodies(child, mask)
	return count


func _ground(space: PhysicsDirectSpaceState3D, position: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 0.5, position - Vector3.UP * 4, mask
	)
	var hit := space.intersect_ray(query)
	return (
		{"height": (hit.position as Vector3).y, "normal_y": (hit.normal as Vector3).y}
		if not hit.is_empty()
		else {}
	)
