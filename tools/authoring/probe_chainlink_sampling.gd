extends "res://tools/authoring/probe_dust_surface_pixels.gd"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.dir_exists_absolute(args[0]):
		push_error("Fresh output directory required")
		quit(2)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for frame in range(12):
		await process_frame
	main.call(
		"_on_map_selected", main.call("find_level_option_index", "dustline-depths-original-local")
	)
	main.call("_on_team_selected", "T")
	await main.call("_on_start_pressed")
	main.call("_on_player_ready")
	for actor in main.get_node("CombatSandbox").get_children():
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("Player").set_physics_process(false)
	var camera := root.get_camera_3d()
	var original := camera.global_transform
	var visual := main.get_node("Level/VisualRoot/LevelVisual")
	var records: Array = []
	for distance in [-2.0, 0.0, 2.0]:
		for yaw in [-0.5, 0.0, 0.5]:
			camera.global_transform = original
			camera.global_position += original.basis.z * distance
			camera.rotate_y(deg_to_rad(yaw))
			var label := "d%s-y%s" % [distance, yaw]
			_chainlink(visual, true)
			_set_mode(visual, BaseMaterial3D.ALPHA_ANTIALIASING_OFF)
			await _capture(label + "-off")
			_set_mode(visual, BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE)
			await _capture(label + "-coverage")
			_chainlink(visual, false)
			await _capture(label + "-hidden")
			records.append(
				{
					"label": label,
					"camera": str(camera.global_transform),
					"distance_offset": distance,
					"yaw_degrees": yaw
				}
			)
	var file := FileAccess.open(output.path_join("poses.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"poses": records,
				"msaa": root.msaa_3d,
				"edge": 0.25,
				"threshold": 0.5,
				"lighting": "product defaults unchanged"
			},
			"\t"
		)
	)
	print("CHAINLINK_SAMPLING_OK poses=9 images=27")
	quit(0)


func _set_mode(node: Node, mode: int) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == "dust_chainlink_fence_wire_001":
				var copy := material.duplicate() as StandardMaterial3D
				copy.alpha_antialiasing_mode = mode
				copy.alpha_antialiasing_edge = 0.25
				node.set_surface_override_material(surface, copy)
	for child in node.get_children():
		_set_mode(child, mode)
