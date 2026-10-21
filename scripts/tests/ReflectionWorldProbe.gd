extends Node3D

const Adapter = preload("res://scripts/level/SourceReflectionDiagnostic.gd")
const Alignment = preload("res://scripts/level/SourceVisualAlignment.gd")
const LEVEL = preload("res://scenes/level/GrayboxLevel.tscn")
const NUMERIC = preload("res://scripts/tests/source_reflection_world.gdshader")
const SURFACE = preload("res://scripts/tests/source_reflection_surface.gdshader")


func _ready() -> void:
	get_tree().create_timer(240).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var path: String = args[args.find("--input") + 1]
	var out: String = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + data.level + ".json")
	)
	var level := LEVEL.instantiate()
	level.level_id = data.level
	add_child(level)
	var alignment := Alignment.resolve(
		level.get_node("VisualRoot/LevelVisual"),
		config,
		args[args.find("--alignment-receipt") + 1] if "--alignment-receipt" in args else ""
	)
	var adapter := Adapter.new()
	assert(not await adapter.configure(path, config, alignment))
	assert(await adapter.configure(path, config, alignment, true))
	var cases: Array = JSON.parse_string(
		FileAccess.get_file_as_string(args[args.find("--goldens") + 1])
	)
	level.visible = false
	var result := await _numeric(adapter, alignment, cases, out)
	assert(not result.is_empty())
	level.visible = true
	await _surfaces(adapter, alignment, cases, out)
	var binding := ShaderMaterial.new()
	binding.shader = NUMERIC
	assert(adapter.bind(binding))
	assert(not await adapter.configure(path, {}, alignment, true))
	assert(binding.get_shader_parameter("reflection_count") == 0)
	assert(binding.get_shader_parameter("native_reflection") == null)
	var file := FileAccess.open(out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("REFLECTION_WORLD_OK ", JSON.stringify(result))
	get_tree().quit()


func _numeric(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> Dictionary:
	var input := Image.create(cases.size(), 2, false, Image.FORMAT_RGBAF)
	for index in range(cases.size()):
		var test: Dictionary = cases[index]
		var p := alignment * Vector3(test.position[0], test.position[1], test.position[2])
		var ray := alignment.basis * Vector3(test.ray[0], test.ray[1], test.ray[2])
		input.set_pixel(index, 0, Color(p.x, p.y, p.z, 1))
		input.set_pixel(index, 1, Color(ray.x, ray.y, ray.z, 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cases.size(), 2)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = NUMERIC
	assert(adapter.bind(material))
	material.set_shader_parameter("cases", ImageTexture.create_from_image(input))
	rect.material = material
	viewport.add_child(rect)
	var image := await _read(viewport)
	var maximum := 0.0
	var overlaps := 0
	for index in range(cases.size()):
		var expected: Array = cases[index].signature
		var pixel := image.get_pixel(index, 0)
		var coverage := image.get_pixel(index, 1).r
		var actual := [pixel.r, pixel.g, pixel.b, coverage]
		for channel in range(4):
			var error := absf(actual[channel] - expected[channel])
			maximum = maxf(maximum, error)
			assert(
				is_finite(actual[channel]) and error < 0.002,
				"world weights/directions mismatch: " + str(cases[index])
			)
		if cases[index].contributors > 1:
			overlaps += 1
	material.set_shader_parameter("signature", false)
	var lod_images := []
	for lod in [3.0, 4.0, 3.5]:
		material.set_shader_parameter("native_lod", lod)
		lod_images.append(await _read(viewport))
	var mip_error := 0.0
	for index in range(cases.size()):
		var a: Color = lod_images[0].get_pixel(index, 0)
		var b: Color = lod_images[1].get_pixel(index, 0)
		var actual: Color = lod_images[2].get_pixel(index, 0)
		var expected := (a + b) * 0.5
		for channel in range(3):
			var error := (
				absf(actual[channel] - expected[channel]) / maxf(1.0, absf(expected[channel]))
			)
			assert(
				is_finite(error) and error < 0.01,
				(
					"fractional mip interpolation mismatch case=%d a=%s b=%s actual=%s expected=%s error=%s"
					% [index, a, b, actual, expected, error]
				)
			)
			mip_error = maxf(mip_error, error)
	assert(image.save_png(out.path_join("world-signatures.png")) == OK)
	viewport.queue_free()
	await get_tree().process_frame
	return {
		"cases": cases.size(),
		"overlap_cases": overlaps,
		"maximum_signature_error": maximum,
		"fractional_mip_error": mip_error
	}


func _read(viewport: SubViewport) -> Image:
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _surfaces(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("758393")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	add_child(sun)
	var p: Array = cases[0].position
	var origin := alignment * Vector3(p[0], p[1], p[2])
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = origin + Vector3(0, 1, -4)
	camera.look_at(origin)
	camera.make_current()
	var materials := []
	var meshes := []
	for index in range(3):
		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new()
		mesh.mesh.radius = 0.4
		mesh.mesh.height = 0.8
		var material := ShaderMaterial.new()
		material.shader = SURFACE
		material.set_shader_parameter("native_lod", float(index * 3))
		assert(adapter.bind(material))
		mesh.material_override = material
		add_child(mesh)
		mesh.position = origin + Vector3(index - 1, 0, 0)
		materials.append(material)
		meshes.append(mesh)
	for step in range(3):
		for mesh in meshes:
			mesh.position.z += 0.3
		for frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(
			(
				get_viewport().get_texture().get_image().save_png(
					out.path_join("real-map-moving-%d.png" % step)
				)
				== OK
			)
		)
