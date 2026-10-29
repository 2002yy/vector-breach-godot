extends SceneTree

var output := ""
var visual: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.dir_exists_absolute(args[0]):
		push_error("One fresh output directory required")
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
	visual = main.get_node("Level/VisualRoot/LevelVisual")
	await _capture("baseline")
	var camera := root.get_camera_3d()
	var records: Array = []
	var names: Dictionary = {}
	for material_name in [
		"dust_awning_02",
		"dust_awning_fabric_01",
		"dust_awning_fabric_frame_01",
		"dust_awning_fabric_ripped_01"
	]:
		names[material_name] = true
	for pixel in [Vector2(800, 220), Vector2(950, 235), Vector2(1100, 250)]:
		var hits: Array = []
		var origin := camera.project_ray_origin(pixel)
		var direction := camera.project_ray_normal(pixel)
		for candidate in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := candidate as MeshInstance3D
			if not mesh_node.is_visible_in_tree() or mesh_node.mesh == null:
				continue
			var inverse := mesh_node.global_transform.affine_inverse()
			var local_origin := inverse * origin
			var local_direction := inverse.basis * direction
			if mesh_node.get_aabb().intersects_ray(local_origin, local_direction) == null:
				continue
			for surface in range(mesh_node.mesh.get_surface_count()):
				var arrays := mesh_node.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var count := indices.size() if not indices.is_empty() else vertices.size()
				for index in range(0, count, 3):
					var a := indices[index] if not indices.is_empty() else index
					var b := indices[index + 1] if not indices.is_empty() else index + 1
					var c := indices[index + 2] if not indices.is_empty() else index + 2
					var hit: Variant = Geometry3D.ray_intersects_triangle(
						local_origin, local_direction, vertices[a], vertices[b], vertices[c]
					)
					if hit == null:
						continue
					var material := mesh_node.get_active_material(surface)
					hits.append(
						{
							"node": str(mesh_node.get_path()),
							"surface": surface,
							"material": material.resource_name if material != null else "",
							"distance": origin.distance_to(mesh_node.global_transform * hit)
						}
					)
		hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
		records.append({"pixel": str(pixel), "hits": hits.slice(0, 8)})
		if not hits.is_empty():
			names[hits[0].material] = true
	var file := FileAccess.open(output.path_join("ray-hits.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	for material_name in names:
		var hidden: Array[Node3D] = []
		for candidate in visual.find_children("*", "MeshInstance3D", true, false):
			var node := candidate as MeshInstance3D
			if node.mesh == null or not node.is_visible_in_tree():
				continue
			for surface in range(node.mesh.get_surface_count()):
				var material := node.get_active_material(surface)
				if material != null and material.resource_name == material_name:
					node.hide()
					hidden.append(node)
					break
		await _capture("hidden-" + String(material_name))
		for node in hidden:
			node.show()
	print("DUST_AWNING_DONE ", names)
	quit(0)


func _capture(label: String) -> void:
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
