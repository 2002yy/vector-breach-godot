extends "res://scripts/tests/CharacterBodyProbe.gd"


func _surfaces(_adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> void:
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
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point + Vector3.DOWN * 5)
	)
	assert(not hit.is_empty())
	var model := Appearance.instantiate("ct-st6")
	add_child(model)
	model.position = hit.position + Vector3.UP * 0.02
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play("run")
	player.pause()
	player.seek(0, true)
	camera.position = model.position + Vector3(0, 1.65, -7)
	camera.look_at(model.position + Vector3.UP * 1.65)
	model.look_at(Vector3(camera.position.x, model.position.y, camera.position.z))
	var bindings := []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as ShaderMaterial
			if original != null and original.shader.code.count(Composite.ANCHOR) == 1:
				bindings.append({"mesh": node, "surface": surface, "original": original})
	var baseline := await _capture(out, "ablation-baseline")
	var variants := {
		"original": "",
		"shared-shader": "",
		"shared-shader-reverse": "",
		"clone": "",
		"emission": "\n EMISSION += vec3(0.0);",
		"radiance": "\n RADIANCE = vec4(0.0);",
		"irradiance": "\n IRRADIANCE = vec4(0.0);",
		"both": "\n RADIANCE = vec4(0.0); IRRADIANCE = vec4(0.0); EMISSION += vec3(0.0);",
		"read-normal-depth": "\n float diagnostic_depth = NORMAL_MAP_DEPTH;",
		"prefix": "",
		"full-disabled": Composite.INJECT
	}
	var records := {}
	for label in variants:
		var ordered := bindings.duplicate()
		if label == "shared-shader-reverse":
			ordered.reverse()
		for entry in ordered:
			if label == "original":
				entry.mesh.set_surface_override_material(entry.surface, entry.original)
				continue
			var copy: ShaderMaterial = entry.original.duplicate()
			if label.begins_with("shared-shader"):
				for uniform in entry.original.shader.get_shader_uniform_list():
					var parameter: StringName = uniform.name
					assert(
						(
							entry.original.get_shader_parameter(parameter)
							== copy.get_shader_parameter(parameter)
						),
						"shared-shader copy must preserve all parameter values"
					)
				entry.mesh.set_surface_override_material(entry.surface, copy)
				continue
			var shader := Shader.new()
			shader.code = entry.original.shader.code
			if label in ["prefix", "full-disabled"]:
				shader.code = shader.code.replace(
					"// Source character channel contracts",
					Composite.PREFIX + "// Source character channel contracts"
				)
			shader.code = shader.code.replace(Composite.ANCHOR, Composite.ANCHOR + variants[label])
			copy.shader = shader
			if label == "full-disabled":
				copy.set_shader_parameter("source_env_enabled", false)
				copy.set_shader_parameter("source_body_enabled", true)
				assert(_indirect.bind(copy))
			entry.mesh.set_surface_override_material(entry.surface, copy)
		var captured := await _capture(out, "ablation-" + label)
		records[label] = _difference(baseline, captured)
	var file := FileAccess.open(out.path_join("ablation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("ENVIRONMENT_ABLATION_OK ", JSON.stringify(records))
