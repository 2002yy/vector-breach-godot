extends SceneTree
## Read-only factorial queries; no player or map rules are changed.

const Survey = preload("res://tools/authoring/ClassicJumpSurvey.gd")
var space: PhysicsDirectSpaceState3D
var probe: CharacterBody3D
var shape_cache := {}


func _initialize() -> void:
	_run.call_deferred()


func _relative(node: Node) -> String:
	var path := str(node.get_path())
	var offset := path.find("/player_collision/")
	assert(offset >= 0)
	return path.substr(offset + 1)


func _triangles(point: Vector3, body: CollisionObject3D, shape_index: int) -> Dictionary:
	var owner := body.shape_find_owner(shape_index)
	var node := body.shape_owner_get_owner(owner) as CollisionShape3D
	if node == null or not node.shape is ConcavePolygonShape3D:
		return {"bound": false, "reason": "not_concave_triangle_shape"}
	var key := _relative(body) + ":" + str(shape_index)
	if not shape_cache.has(key):
		var faces := (node.shape as ConcavePolygonShape3D).get_faces()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(var_to_bytes(faces))
		shape_cache[key] = {"faces": faces, "sha256": hash.finish().hex_encode()}
	var stored: Dictionary = shape_cache[key]
	var candidates: Array[Dictionary] = []
	for index in range(0, stored.faces.size(), 3):
		var a: Vector3 = node.global_transform * stored.faces[index]
		var b: Vector3 = node.global_transform * stored.faces[index + 1]
		var c: Vector3 = node.global_transform * stored.faces[index + 2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 0.000000000001:
			continue
		var normal := cross.normalized()
		var plane := Plane(normal, normal.dot(a))
		var projected := plane.project(point)
		var inside := (
			((b - a).cross(projected - a)).dot(normal) >= -0.000001
			and ((c - b).cross(projected - b)).dot(normal) >= -0.000001
			and ((a - c).cross(projected - c)).dot(normal) >= -0.000001
		)
		var edge_distance := minf(
			point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)),
			minf(
				point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)),
				point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))
			)
		)
		var distance := (
			minf(absf(plane.distance_to(point)), edge_distance) if inside else edge_distance
		)
		if distance <= 0.002:
			candidates.append(
				{
					"triangle_index": index / 3,
					"normal": Survey.array(normal),
					"distance_m": distance,
					"edge_distance_m": edge_distance
				}
			)
	return {
		"bound": true,
		"shape_faces_sha256": stored.sha256,
		"triangle_count": stored.faces.size() / 3,
		"candidates": candidates,
		"unique": candidates.size() == 1,
		"scope": "shape_array_candidates_not_Jolt_face_ids"
	}


func _face(point: Vector3, normal: Vector3, body: Node, shape_index: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + normal * 0.02, point - normal * 0.02, 1)
	query.exclude = [probe.get_rid()]
	query.hit_back_faces = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"matched": false, "reason": "no_ray_hit"}
	var dot: float = hit.normal.dot(normal)
	var error: float = hit.position.distance_to(point)
	var result := {
		"matched":
		(
			hit.collider == body
			and (shape_index < 0 or int(hit.shape) == shape_index)
			and int(hit.face_index) >= 0
			and dot > 0.99
			and error < 0.002
		),
		"body": _relative(hit.collider),
		"shape_index": int(hit.shape),
		"face_index": int(hit.face_index),
		"normal_dot": dot,
		"position_error_m": error,
		"scope": "corroborating_ray_not_motion_result_face_api"
	}
	var bound_index := int(hit.shape) if shape_index < 0 else shape_index
	result["shape_triangles"] = _triangles(point, body as CollisionObject3D, bound_index)
	return result


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
		velocity.y -= gravity * float(delta)
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
				"contacts": contacts
			}
		)
		if hit:
			break
		position += motion
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
		FileAccess.get_sha256("res://tools/authoring/probe_crouch_motion.gd") == matrix.probe_sha256
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
	print("CROUCH_MOTION_WRITTEN ", args[1])
	quit(0)
