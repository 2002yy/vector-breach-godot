extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: level-id evidence-directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(12)
	var index := int(main.call("find_level_option_index", args[0]))
	if index < 0:
		push_error("Requested installed map is unavailable")
		quit(1)
		return
	main.call("_on_map_selected", index)
	await _frames(6)
	main.call("_on_team_selected", "CT")
	await main.call("_on_start_pressed")
	await _frames(20)
	main.call("_on_player_ready")
	for actor in main.get_node("CombatSandbox").get_children():
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var player := main.get_node("Player") as Node3D
	player.set_physics_process(false)
	var pivot := player.get_node("CameraPivot") as Node3D
	var data: Dictionary = main.get_node("Level").call("get_current_level_data")
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(String(data.match_manifest))
	)
	var graph: Dictionary = manifest.layout.navigationGraph
	var astar := AStar3D.new()
	for point in range(graph.points.size()):
		astar.add_point(point, _vector(graph.points[point]))
	for link in graph.links:
		if not astar.are_points_connected(int(link.from), int(link.to)):
			astar.connect_points(int(link.from), int(link.to))
	var t_spawn := _vector(manifest.layout.matchSpawns.T[0])
	var cases: Array = []
	for objective in manifest.layout.objectives:
		var target := Vector3(objective.x, objective.y, objective.z)
		var path := astar.get_point_path(
			astar.get_closest_point(t_spawn), astar.get_closest_point(target)
		)
		if path.size() < 2:
			push_error("No connected material sampling path")
			quit(1)
			return
		for fraction in [0.1, 0.35, 0.65, 0.9, 1.0]:
			var at := mini(int((path.size() - 1) * fraction), path.size() - 1)
			var look := mini(at + 12, path.size() - 1)
			if look == at:
				look = maxi(0, at - 12)
			cases.append(
				{
					"label": "%s-%s" % [objective.label, int(fraction * 100)],
					"position": path[at],
					"look": path[look]
				}
			)
	var records: Array = []
	for record in cases:
		player.global_position = record.position
		var direction: Vector3 = record.look - record.position
		player.rotation.y = atan2(-direction.x, -direction.z)
		pivot.rotation.x = 0
		await _frames(12)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := args[1].path_join(String(record.label) + ".png")
		if image.save_png(path) != OK:
			quit(1)
			return
		if "--compare-occlusion" in args:
			var previous := root.use_occlusion_culling
			root.use_occlusion_culling = false
			await _frames(12)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				args[1].path_join(String(record.label) + "-no-culling.png")
			)
			root.use_occlusion_culling = previous
		records.append(
			{"case": record.label, "render_fps": Engine.get_frames_per_second(), "image": path}
		)
	var file := FileAccess.open(args[1].path_join("material-tour.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"level": args[0],
				"movement_mode": "test_teleport_along_authored_routes",
				"navigation_acceptance": false,
				"texture_sample": _texture_sample(main.get_node("Level/VisualRoot/LevelVisual")),
				"views": records
			},
			"\t"
		)
	)
	file.close()
	print("CLASSIC_MATERIAL_TOUR_CAPTURED=" + str(records.size()))
	main.queue_free()
	await _frames(3)
	quit(0)


func _vector(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))


func _texture_sample(node: Node) -> Dictionary:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				return {
					"class": material.albedo_texture.get_class(),
					"path": material.albedo_texture.resource_path
				}
	for child in node.get_children():
		var found := _texture_sample(child)
		if not found.is_empty():
			return found
	return {}


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
