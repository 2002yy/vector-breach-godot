extends Node

const SAMPLER = preload("res://scripts/tests/source_probe_sample.gdshader")


func _ready() -> void:
	get_tree().create_timer(90).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	assert("--input" in args and "--evidence-dir" in args)
	var input: String = args[args.find("--input") + 1]
	var output: String = args[args.find("--evidence-dir") + 1]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	assert(data.get("cases", []).size() > 0, "GPU validation requires nonempty reference cases")
	var dimensions := Vector3i(
		int(data.dimensions[0]), int(data.dimensions[1]), int(data.dimensions[2])
	)
	var bytes := FileAccess.get_file_as_bytes(input.get_base_dir().path_join(data.volume_file))
	assert(bytes.size() == dimensions.x * dimensions.y * dimensions.z * 16)
	var layers: Array[Image] = []
	var layer_size := dimensions.x * dimensions.y * 16
	for z in range(dimensions.z):
		layers.append(
			Image.create_from_data(
				dimensions.x,
				dimensions.y,
				false,
				Image.FORMAT_RGBAF,
				bytes.slice(z * layer_size, (z + 1) * layer_size)
			)
		)
	bytes.clear()
	var texture := ImageTexture3D.new()
	assert(
		(
			texture.create(
				Image.FORMAT_RGBAF, dimensions.x, dimensions.y, dimensions.z, false, layers
			)
			== OK
		)
	)
	layers.clear()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var material := ShaderMaterial.new()
	material.shader = SAMPLER
	material.set_shader_parameter("probe_texture", texture)
	material.set_shader_parameter("texture_dimensions", Vector3(dimensions))
	rect.material = material
	viewport.add_child(rect)
	var records: Array = []
	for test in data.cases:
		for name in [
			"probe_origin",
			"bounds_min",
			"bounds_size",
			"atlas_size",
			"atlas_offset",
			"source_position",
			"source_direction"
		]:
			var value: Array = test[name]
			material.set_shader_parameter(name, Vector3(value[0], value[1], value[2]))
		material.set_shader_parameter("yaw_degrees", float(test.yaw_degrees))
		for frame in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(4, 4)
		var actual := Vector3(pixel.r, pixel.g, pixel.b)
		var expected := Vector3(test.rgb[0], test.rgb[1], test.rgb[2])
		var error := actual.distance_to(expected)
		assert(
			actual.is_finite() and error < 0.01 + expected.length() * 0.005,
			"HDR probe sampling disagrees with CPU reference: %s / %s" % [actual, expected]
		)
		records.append(
			{"name": test.name, "expected": str(expected), "actual": str(actual), "error": error}
		)
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("SOURCE_PROBE_GPU_OK checks=", records.size())
	get_tree().quit()
