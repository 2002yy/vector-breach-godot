extends "res://scripts/tests/CharacterEnvironmentProbe.gd"

const Indirect = preload("res://scripts/characters/SourceIndirectInputs.gd")
const INDIRECT_MATH = preload("res://scripts/tests/source_indirect_numeric.gdshader")
var _indirect := Indirect.new()
var _indirect_records: Array = []


func _numeric(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> Dictionary:
	var result := await super._numeric(adapter, alignment, cases, out)
	var args := OS.get_cmdline_user_args()
	var path: String = args[args.find("--indirect") + 1]
	assert(_indirect.configure(path, args[args.find("--lighting") + 1]))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var tests: Array = data.cases
	var input := Image.create(tests.size(), 11, false, Image.FORMAT_RGBAF)
	for index in range(tests.size()):
		var test: Dictionary = tests[index]
		for row in range(4):
			var values: Array = [test.normal, test.geometric, test.albedo, test.reflection][row]
			input.set_pixel(
				index,
				row,
				Color(
					values[0],
					values[1],
					values[2],
					[test.coverage, test.skin, test.metallic, test.ao][row]
				)
			)
		input.set_pixel(index, 4, Color(test.roughness, test.ndotv, 0, 1))
		for face in range(6):
			var values: Array = test.cube[face]
			input.set_pixel(index, 5 + face, Color(values[0], values[1], values[2], 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(tests.size(), 4)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = INDIRECT_MATH
	assert(_inputs.bind(material) and _indirect.bind(material))
	material.set_shader_parameter("cases", ImageTexture.create_from_image(input))
	rect.material = material
	viewport.add_child(rect)
	var actual := await _read(viewport)
	var maximum := 0.0
	for index in range(tests.size()):
		for row in range(4):
			var expected: Array = tests[index].expected[row]
			var pixel := actual.get_pixel(index, row)
			for channel in range(3):
				var error := (
					absf(pixel[channel] - expected[channel]) / maxf(1.0, absf(expected[channel]))
				)
				maximum = maxf(maximum, error)
				assert(is_finite(pixel[channel]) and error < 0.002, "indirect GPU mismatch")
	assert(actual.save_png(out.path_join("indirect-numeric.png")) == OK)
	viewport.queue_free()
	await get_tree().process_frame
	result["indirect_cases"] = tests.size()
	result["indirect_max_error"] = maximum
	result["indirect_stage"] = await _stage(out)
	return result


func _stage(out: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.2
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position.z = 2
	viewport.add_child(camera)
	camera.make_current()
	var surface := MeshInstance3D.new()
	surface.mesh = QuadMesh.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/tests/source_indirect_stage.gdshader")
	surface.material_override = material
	viewport.add_child(surface)
	material.set_shader_parameter("source_indirect_enabled", true)
	var a := await _read(viewport)
	world.environment.ambient_light_color = Color(1, 0.05, 0.1)
	world.environment.ambient_light_energy = 2.0
	var b := await _read(viewport)
	assert(_difference(a, b) < 0.00001, "Godot ambient must not double indirect energy")
	var expected := Color(0.132, 0.285, 0.506)
	var actual := b.get_pixel(16, 16).srgb_to_linear()
	for c in range(3):
		assert(absf(actual[c] - expected[c]) < 0.015, "indirect stage energy mismatch")
	material.set_shader_parameter("source_indirect_enabled", false)
	var fallback_a := await _read(viewport)
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.2
	var fallback_b := await _read(viewport)
	assert(_difference(fallback_a, fallback_b) > 0.001)
	material.set_shader_parameter("source_indirect_enabled", true)
	material.set_shader_parameter("material_ao", 0.0)
	var zero := await _read(viewport)
	assert(zero.get_pixel(16, 16).r < 0.005 and zero.get_pixel(16, 16).b < 0.005)
	material.set_shader_parameter("material_ao", 1.0)
	var sun := DirectionalLight3D.new()
	viewport.add_child(sun)
	var direct := await _read(viewport)
	assert(_difference(a, direct) > 0.001, "direct lighting must remain active")
	assert(a.save_png(out.path_join("indirect-stage.png")) == OK)
	viewport.queue_free()
	await get_tree().process_frame
	return {
		"ambient_duplicate_difference": _difference(a, b),
		"direct_difference": _difference(a, direct),
		"linear_rgb": [actual.r, actual.g, actual.b]
	}


func _configure_candidate(composite: RefCounted) -> void:
	for material in composite.materials:
		assert(_indirect.bind(material))


func _exercise_indirect(composite: RefCounted, out: String, label: String, second: Image) -> void:
	for material in composite.materials:
		material.set_shader_parameter("source_indirect_enabled", false)
	var previous := await _capture(out, label + "-specular-only")
	var energy_difference := _difference(second, previous)
	assert(energy_difference > 0.000000001, "indirect energy must affect real hair pixels")
	for material in composite.materials:
		material.set_shader_parameter("source_indirect_enabled", true)
		material.set_shader_parameter("source_indirect_softening", false)
	var hard := await _capture(out, label + "-hard-normal")
	for material in composite.materials:
		material.set_shader_parameter("source_indirect_softening", true)
	_indirect_records.append(
		{
			"label": label,
			"energy_difference": energy_difference,
			"softening_difference": _difference(second, hard)
		}
	)
	var file := FileAccess.open(out.path_join("indirect-characters.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_indirect_records, "\t"))
