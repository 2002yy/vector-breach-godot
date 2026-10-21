extends "res://scripts/tests/CharacterDistanceContrastProbe.gd"

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const EYE_NUMERIC = preload("res://scripts/tests/eye_distance_numeric.gdshader")


func _ready() -> void:
	get_tree().create_timer(180).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	await _distance_numeric()
	await _characters()
	var file := FileAccess.open(_out.path_join("eyes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("CHARACTER_EYE_DISTANCE_OK checks=", _records.size())
	get_tree().quit()


func _distance_numeric() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var material := ShaderMaterial.new()
	material.shader = EYE_NUMERIC
	rect.material = material
	viewport.add_child(rect)
	var color := Vector3(0.2, 0.3, 0.4)
	# Independent analytic goldens: native distance weight is .1 at 120 Source
	# units, .5 at 200, 1 at 300; the viewer's .05 slope would fail these.
	var cases := [
		["below-distance", {"distance_m": 2.0}, color],
		["distance-boundary", {"distance_m": 2.54}, color],
		["original-slope", {"distance_m": 3.048}, color * 0.98],
		["half-distance", {"distance_m": 5.08}, color * 0.9],
		["full-distance", {}, color * 0.8],
		["distance-clamped", {"distance_m": 30.0}, color * 0.8],
		["zero-derivative", {"derivative_x": 0.0}, color],
		["below-derivative", {"derivative_x": 0.149}, color],
		["derivative-boundary", {"derivative_x": 0.15}, color],
		["negative-derivative", {"derivative_x": -0.2}, color * 0.8],
		["highlight-center", {"iris_uv": Vector2(0.15, -0.15)}, color * 0.8 + Vector3.ONE],
		["highlight-inner", {"iris_uv": Vector2(0.22, -0.15)}, color * 0.8 + Vector3.ONE],
		["highlight-mid", {"iris_uv": Vector2(0.24, -0.15)}, color * 0.8 + Vector3.ONE * 0.5],
		["highlight-outer", {"iris_uv": Vector2(0.26, -0.15)}, color * 0.8],
		["hdr", {"input_color": Vector3(2, 3, 4)}, Vector3(1.6, 2.4, 3.2)]
	]
	var defaults := {
		"input_color": color,
		"iris_uv": Vector2.ZERO,
		"pupil": 0.15,
		"derivative_x": 0.2,
		"distance_m": 7.62
	}
	for test in cases:
		for key in defaults:
			material.set_shader_parameter(key, test[1].get(key, defaults[key]))
		await _frames()
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var pixel := image.get_pixel(4, 4)
		var actual := Vector3(pixel.r, pixel.g, pixel.b)
		var error := actual.distance_to(test[2])
		assert(error < 0.004, test[0] + " numeric mismatch " + str(actual))
		_records.append({"numeric": test[0], "actual": str(actual), "error": error})
	viewport.queue_free()
	await get_tree().process_frame


func _characters() -> void:
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("323b47")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 145, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 32
	world.add_child(camera)
	camera.make_current()
	for id in ["t-elite", "t-blackwolf", "t-phoenix"]:
		var model := Appearance.instantiate(id)
		assert(model != null and model.has_meta("source_eye_controller"))
		world.add_child(model)
		var skeleton := Appearance.find_skeleton(model)
		var controller: Node = model.get_child(model.get_child_count() - 1)
		controller.refresh()
		var materials: Array = controller.get("_materials")
		var material: ShaderMaterial = materials[0]
		var changed := 0
		for pose in ["rest", "head-turn"]:
			if pose == "head-turn":
				var head := skeleton.find_bone("head_0")
				skeleton.set_bone_pose_rotation(
					head, skeleton.get_bone_pose_rotation(head) * Quaternion(Vector3.UP, 0.3)
				)
				controller.refresh()
			var left: Vector3 = material.get_shader_parameter("eye_left_center")
			var right: Vector3 = material.get_shader_parameter("eye_right_center")
			var target := (left + right) * 0.5
			for distance_m in [0.45, 2.0, 5.08, 7.62, 15.0]:
				camera.position = target + Vector3(0, 0, -distance_m)
				camera.look_at(target)
				var label: String = "%s-%s-%s" % [id, pose, distance_m]
				for eye_material in materials:
					eye_material.set_shader_parameter("enable_eye_distance_filter", false)
				var baseline := await _capture(label + "-baseline")
				for eye_material in materials:
					eye_material.set_shader_parameter("enable_eye_distance_filter", true)
				var active := await _capture(label + "-filtered")
				var bounds := _eye_region(camera, left, right, active.get_size())
				var base_eye := baseline.get_region(bounds)
				var active_eye := active.get_region(bounds)
				assert(base_eye.save_png(_out.path_join(label + "-baseline-eyes.png")) == OK)
				assert(active_eye.save_png(_out.path_join(label + "-filtered-eyes.png")) == OK)
				var difference := _eye_difference(base_eye, active_eye)
				if distance_m <= 2.0:
					assert(difference < 0.000001, "near eyes must remain unchanged")
				elif difference > 0.0:
					changed += 1
				_records.append(
					{
						"profile": id,
						"pose": pose,
						"distance_m": distance_m,
						"mean_difference": difference
					}
				)
			if pose == "head-turn":
				await _quad_phases(camera, id, target, left, right)
		assert(changed > 0, "real far eye branch never changed: " + id)
		print("EYE_DISTANCE_PROFILE_OK ", id, " changed_far_samples=", changed)
		model.queue_free()
		await get_tree().process_frame


func _quad_phases(
	camera: Camera3D, id: String, target: Vector3, left: Vector3, right: Vector3
) -> void:
	var metre_per_pixel := (
		2.0 * 5.08 * tan(deg_to_rad(camera.fov) * 0.5) / get_viewport().get_visible_rect().size.y
	)
	var signatures := {}
	for phase in [0.0, 0.25, 0.5, 0.75]:
		camera.position = target + Vector3(0, 0, -5.08)
		camera.look_at(target)
		camera.position.x += metre_per_pixel * phase
		var label := "%s-quad-%s" % [id, phase]
		var first := await _capture(label)
		var repeat := await _capture(label + "-repeat")
		var bounds := _eye_region(camera, left, right, first.get_size())
		var eyes := first.get_region(bounds)
		var error := _eye_difference(eyes, repeat.get_region(bounds))
		assert(error < 0.000001, "stationary eye sample must be reproducible")
		assert(eyes.save_png(_out.path_join(label + "-eyes.png")) == OK)
		signatures[hash(first.get_data())] = true
		_records.append({"quad_profile": id, "phase_pixels": phase, "repeat_mad": error})
	assert(signatures.size() > 1, "subpixel camera sweep did not change raster coverage")


func _eye_region(camera: Camera3D, left: Vector3, right: Vector3, size: Vector2i) -> Rect2i:
	var minimum := Vector2(size)
	var maximum := Vector2.ZERO
	var scale := Vector2(size) / get_viewport().get_visible_rect().size
	for point in [left, right]:
		for offset in [Vector3(-0.025, -0.025, 0), Vector3(0.025, 0.025, 0)]:
			var projected := camera.unproject_position(point + offset) * scale
			minimum = minimum.min(projected)
			maximum = maximum.max(projected)
	return (
		Rect2i(Vector2i(minimum) - Vector2i(2, 2), Vector2i(maximum - minimum) + Vector2i(5, 5))
		. intersection(Rect2i(Vector2i.ZERO, size))
	)


func _eye_difference(a: Image, b: Image) -> float:
	var difference := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			assert(is_finite(cb.r) and is_finite(cb.g) and is_finite(cb.b))
			difference += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return difference / (a.get_width() * a.get_height() * 3)
