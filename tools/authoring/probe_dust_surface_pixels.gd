extends SceneTree

var output := "D:/AgentGamePipeline/evidence/dust-release-audit-20261029/dust"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	if FileAccess.file_exists(output.path_join("baseline.png")):
		push_error("Use a fresh output directory; existing screenshots are evidence")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for frame in range(12):
		await process_frame
	var index := int(main.call("find_level_option_index", "dustline-depths-original-local"))
	if index < 0:
		print("MAP_OPTIONS ", main.get("level_options"))
		quit(1)
		return
	main.call("_on_map_selected", index)
	main.call("_on_team_selected", "T")
	await main.call("_on_start_pressed")
	main.call("_on_player_ready")
	for actor in main.get_node("CombatSandbox").get_children():
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("Player").set_physics_process(false)
	await _capture("baseline")
	var environment: Environment = main.get_node("WorldEnvironment").environment
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	await _capture("no-screen-occlusion")
	_disable_shadows(main)
	await _capture("no-shadows")
	var records: Array = []
	_inventory(main.get_node("Level/VisualRoot/LevelVisual"), records)
	var file := FileAccess.open(output.path_join("materials.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	root.get_camera_3d().near = 0.5
	await _capture("near-half-meter")
	root.get_camera_3d().near = 0.05
	_chainlink(main.get_node("Level/VisualRoot/LevelVisual"), false)
	await _capture("chainlink-hidden")
	_chainlink(main.get_node("Level/VisualRoot/LevelVisual"), true)
	_alpha_coverage(main.get_node("Level/VisualRoot/LevelVisual"), 0.25)
	await _capture("chainlink-alpha-coverage-quarter")
	_alpha_coverage(main.get_node("Level/VisualRoot/LevelVisual"), 0.4)
	await _capture("chainlink-alpha-coverage-four-tenths")
	_opaque(main.get_node("Level/VisualRoot/LevelVisual"))
	await _capture("forced-opaque-diagnostic")
	print("DUST_PIXEL_PROBE_DONE")
	quit(0)


func _alpha_coverage(node: Node, edge: float) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == "dust_chainlink_fence_wire_001":
				var copy := material.duplicate() as StandardMaterial3D
				copy.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				copy.alpha_antialiasing_edge = edge
				node.set_surface_override_material(surface, copy)
	for child in node.get_children():
		_alpha_coverage(child, edge)


func _chainlink(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == "dust_chainlink_fence_wire_001":
				node.visible = enabled
	for child in node.get_children():
		_chainlink(child, enabled)


func _opaque(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as StandardMaterial3D
			if material != null:
				var copy := material.duplicate() as StandardMaterial3D
				copy.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				node.set_surface_override_material(surface, copy)
	for child in node.get_children():
		_opaque(child)


func _inventory(node: Node, records: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_active_material(surface) as StandardMaterial3D
			if material != null:
				records.append(
					{
						"node": str(node.get_path()),
						"surface": surface,
						"material": material.resource_name,
						"transparency": material.transparency,
						"alpha_scissor_threshold": material.alpha_scissor_threshold,
						"alpha_antialiasing_mode": material.alpha_antialiasing_mode,
						"alpha_antialiasing_edge": material.alpha_antialiasing_edge,
						"texture_filter": material.texture_filter,
						"albedo_texture":
						(
							material.albedo_texture.resource_path
							if material.albedo_texture != null
							else ""
						),
						"grow": material.grow_amount if material.grow else 0.0,
						"position": str(node.global_position)
					}
				)
	for child in node.get_children():
		_inventory(child, records)


func _disable_shadows(node: Node) -> void:
	if node is Light3D:
		node.shadow_enabled = false
	for child in node.get_children():
		_disable_shadows(child)


func _capture(label: String) -> void:
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
