extends "res://scripts/tests/CharacterIndirectProbe.gd"

const CUBE_MATH = preload("res://scripts/tests/source_probe_cube_numeric.gdshader")


func _numeric(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> Dictionary:
	var result := await super._numeric(adapter, alignment, cases, out)
	result["body_math"] = await _body_math(out)
	var args := OS.get_cmdline_user_args()
	var level: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + _normalization.level + ".json")
	)
	var probes := Probes.new()
	assert(probes.configure(args[args.find("--lighting") + 1], level, alignment, true))
	var tests := []
	for test in cases:
		for n in [
			Vector3.RIGHT,
			Vector3.LEFT,
			Vector3.UP,
			Vector3.DOWN,
			Vector3.BACK,
			Vector3.FORWARD,
			Vector3(0.6, 0, 0.8)
		]:
			tests.append({"position": test.position, "normal": n})
	for n in [Vector3.RIGHT, Vector3(0.6, 0, 0.8)]:
		tests.append({"position": [1000000, 1000000, 1000000], "normal": n})
	var input := Image.create(tests.size(), 2, false, Image.FORMAT_RGBAF)
	for index in range(tests.size()):
		var p: Array = tests[index].position
		var n: Vector3 = tests[index].normal
		input.set_pixel(index, 0, Color(p[0], p[1], p[2], 1))
		input.set_pixel(index, 1, Color(n.x, n.y, n.z, 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(tests.size(), 4)
	viewport.use_hdr_2d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = CUBE_MATH
	assert(probes.bind(material) and _indirect.bind(material))
	material.set_shader_parameter("cases", ImageTexture.create_from_image(input))
	rect.material = material
	viewport.add_child(rect)
	var actual := await _read(viewport)
	var maximum := 0.0
	var covered := 0
	for index in range(tests.size()):
		if actual.get_pixel(index, 1).a > 0.0:
			covered += 1
		for pair in range(2):
			var a := actual.get_pixel(index, pair * 2)
			var b := actual.get_pixel(index, pair * 2 + 1)
			for c in range(4):
				var error := absf(a[c] - b[c]) / maxf(1.0, absf(b[c]))
				maximum = maxf(maximum, error)
				assert(error < 0.002 and is_finite(a[c]), "shared probe cube regression")
	assert(covered > 0, "cube regression must exercise actual LPV coverage")
	assert(actual.save_png(out.path_join("probe-cube.png")) == OK)
	viewport.queue_free()
	await get_tree().process_frame
	result["probe_cube_cases"] = tests.size()
	result["probe_cube_max_error"] = maximum
	result["probe_cube_covered"] = covered
	return result


func _body_math(out: String) -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var tests: Array = JSON.parse_string(
		FileAccess.get_file_as_string(args[args.find("--body-cases") + 1])
	)
	var input := Image.create(tests.size(), 6, false, Image.FORMAT_RGBAF)
	for index in range(tests.size()):
		var test: Dictionary = tests[index]
		for row in range(5):
			var values: Array = [
				test.albedo, test.irradiance, test.reflection, test.view, test.tint
			][row]
			input.set_pixel(
				index,
				row,
				Color(
					values[0],
					values[1],
					values[2],
					[test.metal, test.ao, test.cloth, test.roughness, test.scale][row]
				)
			)
		input.set_pixel(index, 5, Color(test.hair, 0, 0, 1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(tests.size(), 7)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/tests/source_body_numeric.gdshader")
	assert(_inputs.bind(material))
	material.set_shader_parameter("cases", ImageTexture.create_from_image(input))
	rect.material = material
	viewport.add_child(rect)
	var actual := await _read(viewport)
	var maximum := 0.0
	for index in range(tests.size()):
		for row in range(7):
			var expected: Array = tests[index].expected[row]
			var pixel := actual.get_pixel(index, row)
			for c in range(3):
				var error := absf(pixel[c] - expected[c]) / maxf(1.0, absf(expected[c]))
				maximum = maxf(maximum, error)
				assert(is_finite(pixel[c]) and error < 0.002, "body BRDF/energy mismatch")
	assert(actual.save_png(out.path_join("body-numeric.png")) == OK)
	viewport.queue_free()
	await get_tree().process_frame
	return {"cases": tests.size(), "max_error": maximum}


func _surfaces(adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> void:
	await super._surfaces(adapter, alignment, cases, out)
	var args := OS.get_cmdline_user_args()
	var level: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + _normalization.level + ".json")
	)
	var probes := Probes.new()
	assert(probes.configure(args[args.find("--lighting") + 1], level, alignment, true))
	var p: Array = cases[0].position
	var point := alignment * Vector3(p[0], p[1], p[2] - 64)
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point + Vector3.DOWN * 5)
	)
	assert(not hit.is_empty())
	var camera := Camera3D.new()
	camera.fov = 35
	add_child(camera)
	camera.make_current()
	var occluder := MeshInstance3D.new()
	occluder.mesh = QuadMesh.new()
	var opaque := StandardMaterial3D.new()
	opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opaque.albedo_color = Color(0.15, 0.15, 0.15)
	occluder.material_override = opaque
	occluder.scale = Vector3(2, 2, 2)
	occluder.position.z = -0.5
	occluder.visible = false
	camera.add_child(occluder)
	var records := []
	for id in Appearance.NAMES:
		var model := Appearance.instantiate(id)
		assert(model != null)
		add_child(model)
		model.position = hit.position + Vector3.UP * 0.02
		var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var composite := Composite.new()
		assert(composite.attach(model, adapter, probes, _inputs, false, true) == 0)
		for pose in [0.0, 0.6]:
			player.play("run")
			player.pause()
			player.seek(player.get_animation("run").length * pose, true)
			for distance in [1.8, 7.0]:
				camera.position = model.position + Vector3(0, 1.65, -distance)
				camera.look_at(model.position + Vector3.UP * 1.65)
				model.look_at(Vector3(camera.position.x, model.position.y, camera.position.z))
				var label := "body-%s-pose-%s-distance-%s" % [id, pose, distance]
				var baseline := await _capture(out, label + "-baseline")
				assert(composite.attach(model, adapter, probes, _inputs, true, true) > 0)
				assert(composite.attach(model, adapter, probes, _inputs, true, true) == 0)
				_configure_candidate(composite)
				assert(composite.set_enabled(false) == composite.materials.size())
				assert(composite.set_enabled(false) == 0)
				var disabled := await _capture(out, label + "-disabled")
				assert(
					_difference(baseline, disabled) == 0.0,
					"disabled body candidate must restore original material identity"
				)
				assert(composite.set_enabled(true) == composite.materials.size())
				assert(composite.set_enabled(true) == 0)
				var enabled := await _capture(out, label + "-enabled")
				var difference := _difference(baseline, enabled)
				assert(difference > 0.000001, "body composition must affect real pixels")
				var blocked := -1.0
				if pose == 0.0 and distance == 1.8:
					occluder.visible = true
					var hidden := await _capture(out, label + "-occluded")
					assert(composite.set_enabled(false) == composite.materials.size())
					var hidden_base := await _capture(out, label + "-occluded-disabled")
					blocked = _difference(hidden, hidden_base)
					assert(blocked == 0.0, "opaque depth must occlude custom indirect emission")
					occluder.visible = false
				var material_count := composite.materials.size()
				composite.detach()
				var restored := await _capture(out, label + "-restored")
				assert(
					_difference(baseline, restored) == 0.0,
					"detach must restore original material exactly"
				)
				records.append(
					{
						"label": label,
						"materials": material_count,
						"restored_difference": _difference(baseline, restored),
						"difference": difference,
						"disabled_difference": _difference(baseline, disabled),
						"occluded_difference": blocked
					}
				)
		model.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(out.path_join("body-characters.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("CHARACTER_BODY_ENVIRONMENT_OK ", records.size())
