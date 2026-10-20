extends Node3D

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
var _out := "user://eye-proof"
var _records: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("323b47")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 145, 0)
	light.light_energy = 1.5
	add_child(light)
	var camera := Camera3D.new()
	camera.fov = 32
	add_child(camera)
	camera.make_current()
	for id in ["t-elite", "t-blackwolf", "t-phoenix"]:
		var model := Appearance.instantiate(id)
		assert(
			model != null and model.has_meta("source_eye_controller"),
			"missing calibrated eyes: " + id
		)
		add_child(model)
		var skeleton := Appearance.find_skeleton(model)
		var controller: Node = model.get_child(model.get_child_count() - 1)
		assert(controller.has_method("refresh"))
		await get_tree().process_frame
		controller.refresh()
		var material: ShaderMaterial = controller.get("_materials")[0]
		var radius: float = material.get_shader_parameter("eye_radius")
		assert(radius > 0.013 and radius < 0.015)
		var previous: Vector3 = material.get_shader_parameter("eye_left_center")
		for pose in ["rest", "head-turn", "world-transform"]:
			if pose == "head-turn":
				var head := skeleton.find_bone("head_0")
				assert(head >= 0)
				skeleton.set_bone_pose_rotation(
					head, skeleton.get_bone_pose_rotation(head) * Quaternion(Vector3.UP, 0.3)
				)
				controller.refresh()
			if pose == "world-transform":
				model.position = Vector3(1.2, 0.3, -0.7)
				model.rotation.y = 0.15
				model.scale = Vector3.ONE * 1.1
				controller.refresh()
				assert(is_equal_approx(material.get_shader_parameter("eye_radius"), radius * 1.1))
			var left: Vector3 = material.get_shader_parameter("eye_left_center")
			var right: Vector3 = material.get_shader_parameter("eye_right_center")
			var target := (left + right) * 0.5
			camera.position = target + Vector3(0, 0.015, -0.45)
			camera.look_at(target)
			assert(
				(
					left.distance_to(
						(
							skeleton.global_transform
							* skeleton.get_bone_global_pose(skeleton.find_bone("eyeball_l")).origin
						)
					)
					< 0.00001
				)
			)
			if pose == "head-turn":
				assert(left.distance_to(previous) > 0.0001, "eye centers must follow animated head")
			for weight in [0.0, 1.0]:
				material.set_shader_parameter("eye_weight", weight)
				for frame in range(5):
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var label: String = "%s-%s-%d" % [id, pose, int(weight)]
				assert(
					(
						get_viewport().get_texture().get_image().save_png(
							_out.path_join(label + ".png")
						)
						== OK
					)
				)
			_records.append({"profile": id, "pose": pose, "left": str(left), "radius_m": radius})
		model.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(_out.path_join("bindings.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("CHARACTER_EYE_VISUAL_OK profiles=3 poses=9 images=18")
	get_tree().quit()
