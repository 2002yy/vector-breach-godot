extends "res://tools/authoring/probe_crouch_motion.gd"
## Midpoint-gravity free-flight capsule queries, stopped at first contact.


func _snap_receipt(position: Vector3, velocity_y: float) -> Dictionary:
	var from := position + Vector3.UP * 0.1
	var to := from + Vector3.DOWN * 1.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [probe.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"ray_hit": false, "eligible": false}
	var gap: float = position.y - (float(hit.position.y) + 0.9)
	return {
		"ray_hit": true,
		"eligible":
		(
			velocity_y <= 0.0
			and hit.normal.dot(Vector3.UP) >= cos(PI / 4)
			and gap >= 0.0
			and gap <= 0.45
		),
		"gap_m": gap,
		"normal": Survey.array(hit.normal),
		"body": _relative(hit.collider)
	}


func _query(point: Dictionary, gravity: float) -> Dictionary:
	var position := Survey.vector(point.position)
	var velocity := Survey.vector(point.velocity)
	var initial := PhysicsShapeQueryParameters3D.new()
	initial.shape = probe.get_node("CollisionShape3D").shape
	initial.transform.origin = position + Vector3(0, -0.3, 0)
	initial.collision_mask = 1
	initial.exclude = [probe.get_rid()]
	var overlaps: Array[String] = []
	for item in space.intersect_shape(initial, 32):
		overlaps.append(_relative(item.collider))
	var origin_before := probe.global_position
	var rows: Array[Dictionary] = []
	for delta in point.steps:
		velocity.y -= gravity * float(delta) * 0.5
		var motion := velocity * float(delta)
		var parameters := PhysicsTestMotionParameters3D.new()
		parameters.from = Transform3D(Basis.IDENTITY, position)
		parameters.motion = motion
		parameters.margin = probe.safe_margin
		parameters.max_collisions = 4
		parameters.recovery_as_collision = false
		var result := PhysicsTestMotionResult3D.new()
		var hit := PhysicsServer3D.body_test_motion(probe.get_rid(), parameters, result)
		var contacts: Array[Dictionary] = []
		for index in result.get_collision_count():
			var body := result.get_collider(index) as Node
			var normal := result.get_collision_normal(index)
			var contact := result.get_collision_point(index)
			var shape_index := result.get_collider_shape(index)
			contacts.append(
				{
					"body": _relative(body),
					"shape_index": shape_index,
					"normal": Survey.array(normal),
					"position": Survey.array(contact),
					"face_ray": _face(contact, normal, body, shape_index)
				}
			)
		rows.append(
			{
				"delta": float(delta),
				"from": Survey.array(position),
				"motion": Survey.array(motion),
				"hit": hit,
				"safe_fraction": result.get_collision_safe_fraction(),
				"unsafe_fraction": result.get_collision_unsafe_fraction(),
				"contacts": contacts,
				"snap_query": _snap_receipt(position + motion, velocity.y)
			}
		)
		if hit:
			break
		position += motion
		velocity.y -= gravity * float(delta) * 0.5
	return {
		"id": point.id,
		"initial_overlaps": overlaps,
		"steps": rows,
		"body_origin_unchanged": probe.global_position == origin_before
	}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2 and not FileAccess.file_exists(args[1]))
	var matrix: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	assert(matrix.schema == 1 and matrix.cases.size() == 8)
	assert(
		(
			FileAccess.get_sha256("res://tools/authoring/probe_mirage_landing_motion.gd")
			== matrix.probe_sha256
		)
	)
	assert(
		(
			FileAccess.get_sha256("res://tools/authoring/probe_crouch_motion.gd")
			== matrix.parent_probe_sha256
		)
	)
	assert(Engine.get_version_info().hash == matrix.identity.engine_hash)
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(
		matrix.level
	)
	var source := String(data.runtime_collision_scene)
	assert(FileAccess.get_sha256(source) == matrix.identity.collision_sha256)
	assert(FileAccess.get_sha256(source + ".import") == matrix.identity.collision_import_sha256)
	assert(
		(
			FileAccess.get_sha256("res://data/levels/%s.json" % matrix.level)
			== matrix.identity.level_sha256
		)
	)
	assert(FileAccess.get_sha256(String(data.match_manifest)) == matrix.identity.layout_sha256)
	var stage := Node3D.new()
	root.add_child(stage)
	var geometry := (load(source) as PackedScene).instantiate()
	stage.add_child(geometry)
	var builder := (load("res://scenes/level/GrayboxLevel.tscn") as PackedScene).instantiate()
	builder.load_on_ready = false
	stage.add_child(builder)
	builder.call("_build_runtime_collision", geometry, true, true, source)
	probe = CharacterBody3D.new()
	probe.collision_layer = 0
	probe.collision_mask = 1
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(matrix.capsule.radius)
	capsule.height = float(matrix.capsule.height)
	shape.shape = capsule
	shape.position.y = float(matrix.capsule.local_y)
	probe.add_child(shape)
	stage.add_child(probe)
	for frame in range(5):
		await physics_frame
	space = stage.get_world_3d().direct_space_state
	var results: Array[Dictionary] = []
	for point in matrix.cases:
		results.append(_query(point, float(matrix.gravity)))
	var contact: Dictionary = matrix.original_contact
	var relative: String = String(contact.body).substr(
		String(contact.body).find("/player_collision/") + 1
	)
	var original_body: Node = geometry.get_node(NodePath(relative.trim_prefix("player_collision/")))
	var output := {
		"schema": 1,
		"identity": matrix.identity,
		"matrix_sha256": FileAccess.get_sha256(args[0]),
		"probe_sha256": matrix.probe_sha256,
		"safe_margin": probe.safe_margin,
		"results": results,
		"original_contact_face":
		_face(Survey.vector(contact.position), Survey.vector(contact.normal), original_body, -1)
	}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	stage.free()
	print("MIRAGE_LANDING_MOTION_WRITTEN ", args[1])
	quit(0)
