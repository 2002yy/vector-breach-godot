extends Node3D

const Adapter = preload("res://scripts/level/SourceProbeDiagnostic.gd")
const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const NUMERIC = preload("res://scripts/tests/source_probe_world_numeric.gdshader")
const LEVEL_SCENE = preload("res://scenes/level/GrayboxLevel.tscn")
const Alignment = preload("res://scripts/level/SourceVisualAlignment.gd")
var _out: String
var _records: Array = []


func _ready() -> void:
	get_tree().create_timer(240).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var bundle: String = args[args.find("--bundle") + 1]
	var metadata_path: String = args[args.find("--metadata") + 1]
	_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bundle))
	var level_data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + data.level + ".json")
	)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("7d8c9c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.75, 0.8)
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-40, -30, 0)
	add_child(sun)
	var level := LEVEL_SCENE.instantiate()
	level.level_id = data.level
	add_child(level)
	var visual: Node = level.get_node("VisualRoot/LevelVisual")
	print(
		"ALIGNMENT_ROOT ",
		visual.name,
		" candidates=",
		visual.find_children("*SourceAlignment*", "Node3D", true, false).size()
	)
	var alignment := Alignment.resolve(
		visual,
		level_data,
		args[args.find("--alignment-receipt") + 1] if "--alignment-receipt" in args else ""
	)
	assert(Adapter.valid_alignment(alignment))
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	var units: Dictionary = metadata.units
	assert(units.sourceToWebAxes in [["x", "z", "-y"], ["y", "z", "x"]])
	var offset: Array = units.sourceToWebOffset
	var translation := (
		Vector3(offset[0], offset[1], offset[2]) * (0.0254 / float(units.sourceToWebScale))
	)
	for sample in data.spawn_samples:
		var p: Array = sample.position_source
		var source := Vector3(p[0], p[1], p[2])
		var axes := (
			Vector3(source.x, source.z, -source.y)
			if units.sourceToWebAxes == ["x", "z", "-y"]
			else Vector3(source.y, source.z, source.x)
		)
		var expected := axes * 0.0254 + translation
		assert((alignment * source).distance_to(expected) < 0.0001)
		assert((alignment.affine_inverse() * expected).distance_to(source) < 0.01)
	var adapter := Adapter.new()
	assert(not adapter.configure(bundle, level_data, alignment))
	assert(adapter.configure(bundle, level_data, alignment, true))
	level.visible = false
	assert(await _numeric(adapter, data, alignment))
	assert("--moving-goldens" in args)
	var moving: Array = JSON.parse_string(
		FileAccess.get_file_as_string(args[args.find("--moving-goldens") + 1])
	)
	assert(await _moving(adapter, alignment, moving))
	level.visible = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera := Camera3D.new()
	camera.environment = environment.environment
	camera.fov = 40
	add_child(camera)
	camera.make_current()
	var source_spawn: Array = data.spawn_samples[0].position_source
	var origin := alignment * Vector3(source_spawn[0], source_spawn[1], source_spawn[2] - 64)
	for id in ["ct-st6", "ct-sas-officer", "ct-fbi", "t-phoenix", "t-elite", "t-blackwolf"]:
		var model := Appearance.instantiate(id)
		assert(model != null)
		add_child(model)
		for side in [-0.5, 0.5]:
			var target := origin + Vector3(side, 0, 0)
			var query := PhysicsRayQueryParameters3D.create(
				target + Vector3.UP * 2, target + Vector3.DOWN * 5
			)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			assert(not hit.is_empty(), "original spawn must align to installed collision")
			model.position = hit.position + Vector3.UP * 0.02
			camera.position = model.position + Vector3(0, 2, -4)
			camera.look_at(model.position + Vector3.UP)
			adapter.detach()
			await _capture("%s-%s-baseline" % [id, side])
			for direction in [0, 1]:
				var count := adapter.attach(model, direction)
				assert(count > 0)
				assert(
					adapter.attach(model, direction) == 0, "repeated attach must not stack passes"
				)
				await _capture("%s-%s-direction-%d" % [id, side, direction])
				# Move without reattaching; fragment positions must follow the model.
				model.position.x += 0.1
				await _capture("%s-%s-direction-%d-moved" % [id, side, direction])
				model.position.x -= 0.1
				adapter.detach()
		model.queue_free()
		await get_tree().process_frame
	var binding := ShaderMaterial.new()
	binding.shader = NUMERIC
	assert(adapter.bind(binding))
	assert(not adapter.configure(bundle, {}, alignment, true))
	assert(binding.get_shader_parameter("source_probe_count") == 0)
	var file := FileAccess.open(_out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("MAP_PROBE_RUNTIME_OK checks=", _records.size(), " profiles=6 images=60")
	get_tree().quit()


func _numeric(adapter: RefCounted, data: Dictionary, alignment: Transform3D) -> bool:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(8, 8)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var material := ShaderMaterial.new()
	material.shader = NUMERIC
	assert(adapter.bind(material))
	rect.material = material
	viewport.add_child(rect)
	var axes := {
		"+x": Vector3.RIGHT,
		"-x": Vector3.LEFT,
		"+y": Vector3.UP,
		"-y": Vector3.DOWN,
		"+z": Vector3.BACK,
		"-z": Vector3.FORWARD
	}
	for sample in data.spawn_samples:
		var p: Array = sample.position_source
		material.set_shader_parameter("sample_world", alignment * Vector3(p[0], p[1], p[2]))
		for direction in axes:
			material.set_shader_parameter("direction_world", alignment.basis * axes[direction])
			for frame in range(2):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var pixel := viewport.get_texture().get_image().get_pixel(4, 4)
			var actual := Vector3(pixel.r, pixel.g, pixel.b)
			var rgb: Array = sample.directions[direction].rgb
			var expected := Vector3(rgb[0], rgb[1], rgb[2])
			assert(
				(
					actual.is_finite()
					and actual.distance_to(expected) < 0.01 + expected.length() * 0.005
				),
				"%s / %s" % [actual, expected]
			)
			_records.append(
				{
					"direction": direction,
					"actual": str(actual),
					"expected": str(expected),
					"error": actual.distance_to(expected)
				}
			)
	viewport.queue_free()
	await get_tree().process_frame
	return true


func _capture(label: String) -> void:
	for frame in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png")) == OK)


func _moving(adapter: RefCounted, alignment: Transform3D, cases: Array) -> bool:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.02
	camera.environment = Environment.new()
	camera.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment.tonemap_exposure = 0.25
	viewport.add_child(camera)
	camera.make_current()
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	var material := ShaderMaterial.new()
	material.shader = Adapter.DISPLAY
	assert(adapter.bind(material))
	mesh.material_override = material
	viewport.add_child(mesh)
	for test in cases:
		var p: Array = test.position_source
		mesh.position = alignment * Vector3(p[0], p[1], p[2])
		camera.position = mesh.position + Vector3(0, 0, 1)
		camera.look_at(mesh.position)
		material.set_shader_parameter("diagnostic_direction", int(test.direction))
		for frame in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(16, 16).srgb_to_linear()
		var actual := Vector3(pixel.r, pixel.g, pixel.b) / 0.25
		var expected := Vector3(test.rgb[0], test.rgb[1], test.rgb[2])
		assert(
			actual.distance_to(expected) < 0.025,
			"moving fragment did not follow transform/camera: %s / %s" % [actual, expected]
		)
		_records.append(
			{
				"moving": true,
				"direction": test.direction,
				"actual": str(actual),
				"expected": str(expected),
				"error": actual.distance_to(expected)
			}
		)
	viewport.queue_free()
	await get_tree().process_frame
	return true
