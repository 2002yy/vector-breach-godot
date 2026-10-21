extends Node

const Reflection = preload("res://scripts/level/SourceReflectionTexture.gd")
const LOOKUP = preload("res://scripts/tests/source_reflection_lookup.gdshader")
const PROJECTION = preload("res://scripts/tests/source_reflection_projection.gdshader")
const PANORAMA = preload("res://scripts/tests/source_reflection_panorama.gdshader")


func _ready() -> void:
	get_tree().create_timer(120).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var path := args[args.find("--input") + 1]
	var out := args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data.file == "blocks/reflection.bc6h")
	var payload := FileAccess.get_file_as_bytes(path.get_base_dir().path_join(data.file))
	assert(Reflection._sha(payload) == data.sha256)
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + data.level + ".json")
	)
	assert(config.sourceTrace.vpkSha256 == data.source_trace.vpkSha256)
	var source := Reflection.new()
	assert(await source.create(data, payload))
	await _lifetime(data, payload)
	var inputs := Image.create(data.samples.size(), 2, false, Image.FORMAT_RGBAF)
	for index in range(data.samples.size()):
		var test: Dictionary = data.samples[index]
		var s: float = 2.0 * (test.x + 0.5) / test.size - 1.0
		var t: float = 2.0 * (test.y + 0.5) / test.size - 1.0
		var direction: Vector3 = [
			Vector3(1, -t, -s),
			Vector3(-1, -t, s),
			Vector3(s, 1, t),
			Vector3(s, -1, -t),
			Vector3(s, -t, 1),
			Vector3(-s, -t, -1)
		][int(test.face)]
		inputs.set_pixel(index, 0, Color(direction.x, direction.y, direction.z, test.index))
		inputs.set_pixel(index, 1, Color(test.mip, 0, 0, 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(data.samples.size(), 1)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = LOOKUP
	material.set_shader_parameter("native_reflection", source.texture)
	material.set_shader_parameter("cases", ImageTexture.create_from_image(inputs))
	rect.material = material
	viewport.add_child(rect)
	for frame in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var rows := []
	var max_error := 0.0
	for index in range(data.samples.size()):
		var pixel := image.get_pixel(index, 0)
		var expected: Array = data.samples[index].rgb
		var actual := [pixel.r, pixel.g, pixel.b]
		for channel in range(3):
			var error := absf(actual[channel] - expected[channel]) / maxf(1.0, expected[channel])
			max_error = maxf(max_error, error)
			assert(
				is_finite(actual[channel]) and error < 0.01,
				"reflection sample mismatch " + str(data.samples[index]) + " actual=" + str(actual)
			)
		rows.append({"case": data.samples[index], "actual": actual})
	var file := FileAccess.open(out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples": rows, "max_relative_error": max_error}, "\t"))
	await _projections(data, out)
	await _panoramas(data, source.texture, out)
	viewport.queue_free()
	await get_tree().process_frame
	source.release()
	await get_tree().process_frame
	print("SOURCE_REFLECTION_GPU_OK samples=", rows.size(), " max_error=", max_error)
	get_tree().quit()


func _lifetime(data: Dictionary, payload: PackedByteArray) -> void:
	var cancelled := Reflection.new()
	cancelled.release.call_deferred()
	assert(not await cancelled.create(data, payload), "cancelled upload must not publish a texture")
	assert(cancelled.texture == null)
	var abandoned := Reflection.new()
	assert(await abandoned.create(data, payload))
	abandoned = null
	for frame in range(3):
		await get_tree().process_frame
	print("SOURCE_REFLECTION_LIFETIME_OK cancellation+destruction")


func _projections(data: Dictionary, out: String) -> void:
	var cases: Array = data.projection_cases
	assert(not cases.is_empty())
	var inputs := Image.create(cases.size(), 5, false, Image.FORMAT_RGBAF)
	for index in range(cases.size()):
		var test: Dictionary = cases[index]
		for row in range(5):
			var values: Array = [test.position, test.ray, test.origin_yaw, test.minimum, test.size][row]
			inputs.set_pixel(
				index,
				row,
				Color(values[0], values[1], values[2], values[3] if values.size() > 3 else 0.0)
			)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cases.size(), 2)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = PROJECTION
	material.set_shader_parameter("cases", ImageTexture.create_from_image(inputs))
	rect.material = material
	viewport.add_child(rect)
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var maximum := 0.0
	for index in range(cases.size()):
		var pixel := image.get_pixel(index, 0)
		var expected: Array = cases[index].expected
		var actual := [pixel.r * 2.0 - 1.0, pixel.g * 2.0 - 1.0, pixel.b * 2.0 - 1.0]
		for axis in range(3):
			var error := absf(actual[axis] - expected[axis])
			maximum = maxf(maximum, error)
			assert(is_finite(actual[axis]) and error < 0.002, "box projection mismatch")
		assert(image.get_pixel(index, 1).r > 0.99)
	var file := FileAccess.open(out.path_join("projection.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": cases.size(), "maximum_axis_error": maximum}))
	viewport.queue_free()
	await get_tree().process_frame
	print("SOURCE_REFLECTION_BOX_OK cases=", cases.size(), " error=", maximum)


func _panoramas(data: Dictionary, cube_texture: TextureCubemapArrayRD, out: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 256)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = PANORAMA
	material.set_shader_parameter("native_reflection", cube_texture)
	rect.material = material
	viewport.add_child(rect)
	for index in [0, int(data.cubes) / 2, int(data.cubes) - 1]:
		for mip in [0, 3, int(data.mip_count) - 1]:
			material.set_shader_parameter("cube_index", float(index))
			material.set_shader_parameter("native_lod", float(mip))
			for frame in range(4):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			assert(image.save_png(out.path_join("cube-%d-mip-%d.png" % [index, mip])) == OK)
	viewport.queue_free()
	await get_tree().process_frame
