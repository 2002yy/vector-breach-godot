extends "res://scripts/tests/ReflectionWorldProbe.gd"

const Inputs = preload("res://scripts/characters/SourceEnvironmentInputs.gd")
const Composite = preload("res://scripts/characters/SourceCharacterEnvironment.gd")
const Probes = preload("res://scripts/level/SourceProbeDiagnostic.gd")
const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const MATH = preload("res://scripts/tests/source_environment_numeric.gdshader")
var _inputs := Inputs.new()
var _normalization: Dictionary
var _role_records: Array = []


func _numeric(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> Dictionary:
	var result := await super._numeric(adapter, alignment, cases, out)
	assert(not result.is_empty())
	var args := OS.get_cmdline_user_args()
	var input: String = args[args.find("--normalization") + 1]
	_normalization = JSON.parse_string(FileAccess.get_file_as_string(input))
	var reflection: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(args[args.find("--input") + 1])
	)
	assert(_inputs.configure(input, reflection))
	var tests: Array = _normalization.cases
	var image := Image.create(tests.size(), 5, false, Image.FORMAT_RGBAF)
	for index in range(tests.size()):
		var test: Dictionary = tests[index]
		image.set_pixel(index, 0, Color(test.roughness, test.ndotv, test.cube, 1))
		for row in range(1, 4):
			var values: Array = [test.normal, test.irradiance, test.f0][row - 1]
			image.set_pixel(index, row, Color(values[0], values[1], values[2], 1))
		image.set_pixel(index, 4, Color(test.rough_xy[0], test.rough_xy[1], 0, 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(tests.size(), 4)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = MATH
	assert(_inputs.bind(material))
	material.set_shader_parameter("cases", ImageTexture.create_from_image(image))
	rect.material = material
	viewport.add_child(rect)
	var actual := await _read(viewport)
	var maximum := 0.0
	for index in range(tests.size()):
		var test: Dictionary = tests[index]
		for row in range(4):
			var expected: Array = [
				[test.normalization, test.normalization, test.normalization],
				test.single,
				test.multi,
				test.secondary_ray
			][row]
			var pixel := actual.get_pixel(index, row)
			for channel in range(3):
				var error := (
					absf(pixel[channel] - expected[channel]) / maxf(1.0, absf(expected[channel]))
				)
				maximum = maxf(maximum, error)
				assert(is_finite(pixel[channel]) and error < 0.002, "original SH/BRDF GPU mismatch")
	assert(actual.save_png(out.path_join("normalization-brdf.png")) == OK)
	viewport.queue_free()
	await get_tree().process_frame
	result["normalization_cases"] = tests.size()
	result["normalization_max_error"] = maximum
	return result


func _surfaces(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> void:
	var args := OS.get_cmdline_user_args()
	var level: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + _normalization.level + ".json")
	)
	var probes := Probes.new()
	assert(probes.configure(args[args.find("--lighting") + 1], level, alignment, true))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("758393")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.45
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35
	add_child(camera)
	camera.make_current()
	var p: Array = cases[0].position
	var point := alignment * Vector3(p[0], p[1], p[2] - 64)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point + Vector3.DOWN * 5)
	)
	assert(not hit.is_empty())
	for id in ["t-elite", "t-blackwolf"]:
		var model := Appearance.instantiate(id)
		assert(model != null)
		add_child(model)
		model.position = hit.position + Vector3.UP * 0.02
		model.rotation.y = PI
		var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var composite := Composite.new()
		assert(composite.attach(model, adapter, probes, _inputs) == 0)
		for pose in [0.0, 0.6]:
			player.play("run")
			player.pause()
			player.seek(player.get_animation("run").length * pose, true)
			for distance in [1.8, 7.0]:
				camera.position = model.position + Vector3(0, 1.65, -distance)
				camera.look_at(model.position + Vector3.UP * 1.65)
				model.look_at(Vector3(camera.position.x, model.position.y, camera.position.z))
				var label := "%s-pose-%s-distance-%s" % [id, pose, distance]
				var baseline := await _capture(out, label + "-baseline")
				assert(composite.attach(model, adapter, probes, _inputs, true) > 0)
				assert(composite.attach(model, adapter, probes, _inputs, true) == 0)
				for material in composite.materials:
					material.set_shader_parameter("source_env_enabled", false)
				var disabled := await _capture(out, label + "-disabled")
				assert(
					_difference(baseline, disabled) < 0.00001,
					"disabled environment must preserve original material"
				)
				for material in composite.materials:
					material.set_shader_parameter("source_env_enabled", true)
					material.set_shader_parameter("source_env_second_weight", 0.0)
				var primary := await _capture(out, label + "-primary")
				for material in composite.materials:
					material.set_shader_parameter("source_env_second_weight", 1.0)
				var second := await _capture(out, label + "-second")
				var difference := _difference(primary, second)
				assert(
					difference > 0.000000001, "second environment lobe must affect real hair pixels"
				)
				var followed := await _follow_check(composite, model, player, pose)
				_role_records.append(
					{
						"label": label,
						"second_lobe_difference": difference,
						"moving_eye_bindings": followed,
						"disabled_difference": _difference(baseline, disabled)
					}
				)
				composite.detach()
		model.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(out.path_join("characters.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_role_records, "\t"))
	print("CHARACTER_HAIR_ENVIRONMENT_OK ", JSON.stringify(_role_records))


func _follow_check(
	composite: RefCounted, model: Node3D, player: AnimationPlayer, pose: float
) -> int:
	var previous := []
	for material in composite.materials:
		previous.append(material.get_shader_parameter("eye_left_center"))
		material.set_shader_parameter("enable_eyes", false)
	var previous_scale := model.scale
	model.scale *= 1.1
	player.seek(player.get_animation("run").length * (pose + 0.1), true)
	model.position.x += 0.1
	for frame in range(3):
		await get_tree().process_frame
	var count := 0
	for i in range(composite._bindings.size()):
		var entry: Dictionary = composite._bindings[i]
		if entry.original.get_shader_parameter("enable_eyes") != true:
			continue
		var actual: Vector3 = entry.copy.get_shader_parameter("eye_left_center")
		var expected: Vector3 = entry.original.get_shader_parameter("eye_left_center")
		assert(actual.is_equal_approx(expected) and actual.distance_to(previous[i]) > 0.01)
		assert(entry.copy.get_shader_parameter("enable_eyes") == true)
		assert(
			is_equal_approx(
				entry.copy.get_shader_parameter("eye_radius"),
				entry.original.get_shader_parameter("eye_radius")
			)
		)
		count += 1
	assert(count > 0, "moving eye uniforms must follow original controller")
	model.position.x -= 0.1
	model.scale = previous_scale
	player.seek(player.get_animation("run").length * pose, true)
	return count


func _capture(out: String, label: String) -> Image:
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(out.path_join(label + ".png")) == OK)
	return image


func _difference(a: Image, b: Image) -> float:
	var difference := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			difference += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return difference / (a.get_width() * a.get_height() * 3)
