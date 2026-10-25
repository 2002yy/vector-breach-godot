extends SceneTree
## Original visual scene with non-colliding diagnostic markers only.

const Survey = preload("res://tools/authoring/ClassicJumpSurvey.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var source: String = manifest.identity.collision_path
	assert(FileAccess.get_sha256(source) == manifest.identity.collision_sha256)
	assert(FileAccess.get_sha256(source + ".import") == manifest.identity.collision_import_sha256)
	assert(
		(
			FileAccess.get_sha256("res://data/levels/%s.json" % manifest.level)
			== manifest.identity.level_sha256
		)
	)
	var stage := Node3D.new()
	root.add_child(stage)
	var data: Dictionary = preload("res://scripts/level/LevelDataLoader.gd").load_level(
		manifest.level
	)
	# Reuse actual Main/map lighting without starting menus, actors or a match.
	var template = load("res://scenes/Main.tscn").instantiate()
	var environment: WorldEnvironment = template.get_node("WorldEnvironment")
	var sun: DirectionalLight3D = template.get_node("Sun")
	environment.environment = environment.environment.duplicate(true)
	template.set("world_environment", environment)
	template.set("sun", sun)
	template.call("_capture_default_environment")
	template.call("_apply_level_environment", data)
	template.remove_child(environment)
	template.remove_child(sun)
	environment.owner = null
	sun.owner = null
	stage.add_child(environment)
	stage.add_child(sun)
	template.free()
	var level = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.load_on_ready = false
	stage.add_child(level)
	assert(level.load_level(manifest.level))
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 300.0
	stage.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute(args[1])
	var images: Array[Dictionary] = []
	for point in manifest.cases:
		var start := Survey.vector(point.start)
		var goal := Survey.vector(point.target_feet)
		var direction := Vector3(-sin(point.yaw), 0, -cos(point.yaw))
		var markers := Node3D.new()
		stage.add_child(markers)
		_marker(markers, start - Vector3.UP * 0.8, Color(0.1, 0.9, 1.0), "START")
		_marker(markers, goal + Vector3.UP * 0.15, Color(1.0, 0.7, 0.1), "GOAL")
		for view in ["first_person", "overview"]:
			if view == "first_person":
				camera.global_position = start + Vector3.UP * 0.72
				camera.look_at(camera.global_position + direction, Vector3.UP)
			else:
				camera.global_position = _overview(
					stage.get_world_3d().direct_space_state, start, goal, direction
				)
				var focus := goal + Vector3.UP * 0.65
				var look_direction := (focus - camera.global_position).normalized()
				camera.look_at(
					focus,
					Vector3.FORWARD if absf(look_direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
				)
			for frame in range(6):
				await process_frame
			await RenderingServer.frame_post_draw
			var path := args[1].path_join("%s-%s.png" % [point.id, view])
			assert(root.get_texture().get_image().save_png(path) == OK)
			images.append({"case": point.id, "view": view, "image": path})
		markers.queue_free()
		await process_frame
	var output := FileAccess.open(args[1].path_join("capture.json"), FileAccess.WRITE)
	output.store_string(
		JSON.stringify(
			{
				"lighting": "Main environment plus runtime map environment helper",
				"manifest_sha256": FileAccess.get_sha256(args[0]),
				"level": manifest.level,
				"images": images
			},
			"\t"
		)
	)
	stage.queue_free()
	await process_frame
	await process_frame
	print("CLASSIC_JUMP_IMAGES_OK ", images.size())
	quit(0)


func _overview(
	space: PhysicsDirectSpaceState3D, start: Vector3, goal: Vector3, direction: Vector3
) -> Vector3:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	for at in [
		start + Vector3.UP * 3.2,
		start - direction * 3.0 + direction.cross(Vector3.UP) * 2.0 + Vector3.UP * 2.2,
		start - direction * 1.0 - direction.cross(Vector3.UP) * 2.0 + Vector3.UP * 1.2,
		start + Vector3.UP * 0.72
	]:
		query.transform.origin = at
		var ray := PhysicsRayQueryParameters3D.create(at, goal + Vector3.UP * 0.65, 1)
		if space.intersect_shape(query, 1).is_empty() and space.intersect_ray(ray).is_empty():
			return at
	return start + Vector3.UP * 0.72


func _marker(parent: Node3D, at: Vector3, color: Color, text: String) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	parent.add_child(marker)
	marker.global_position = at
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	parent.add_child(label)
	label.global_position = at + Vector3.UP * 0.4
