extends Node3D

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const Contrast = preload("res://scripts/characters/SourceCharacterContrast.gd")
var _out := "user://contrast-input-proof"
var _records: Array = []


func _ready() -> void:
	get_tree().create_timer(180).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("323b47")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 145, 0)
	light.light_energy = 1.5
	add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	camera.far = 100.0
	add_child(camera)
	camera.make_current()
	var context := {
		"purpose": "diagnostic",
		"accept_average_candidate": true,
		"source_unit_m": 0.0254,
		"strength": 0.5,
		"fog_modification": 1.0,
		"irradiance_sh1":
		[Vector4(0, 0, 0.1, 0.4), Vector4(0, 0, 0.1, 0.5), Vector4(0, 0, 0.1, 0.6)],
	}
	assert(not Contrast.context_valid({}))
	for key in ["source_unit_m", "strength", "fog_modification", "irradiance_sh1"]:
		var invalid := context.duplicate(true)
		invalid[key] = "invalid"
		assert(not Contrast.context_valid(invalid))
	var unapproved := context.duplicate(true)
	unapproved.accept_average_candidate = false
	assert(not Contrast.context_valid(unapproved))
	for id in ["ct-st6", "ct-sas-officer", "ct-fbi", "t-phoenix", "t-elite", "t-blackwolf"]:
		var model := Appearance.instantiate(id)
		assert(model != null, "missing original profile: " + id)
		add_child(model)
		var path: String = String(Appearance.record(id).asset_root) + id + ".glb"
		assert(Contrast.apply(model, path) == 0)
		var count := Contrast.apply(model, path, context)
		assert(count > 0, "no bound original materials: " + id)
		var materials: Array[ShaderMaterial] = []
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				var original := mesh.get_active_material(surface) as ShaderMaterial
				if original == null or original in materials or original.next_pass == null:
					continue
				materials.append(original)
				var diagnostic := original.next_pass as ShaderMaterial
				assert(
					(
						diagnostic.get_shader_parameter("surface_texture")
						== original.get_shader_parameter("base_texture")
					)
				)
				assert(
					(
						diagnostic.get_shader_parameter("surface_uv_scale")
						== original.get_shader_parameter("uv_scale")
					)
				)
				assert(
					(
						diagnostic.get_shader_parameter("surface_uv_offset")
						== original.get_shader_parameter("uv_offset")
					)
				)
				assert(
					diagnostic.get_shader_parameter("irradiance_sh_b") == context.irradiance_sh1[2]
				)
				var native: Dictionary = original.get_meta("source_material_parameters")
				var raw := float(
					native.get("FloatParams", {}).get("g_fDistanceContrastExposure", 0.6)
				)
				var translucent: bool = native.get("IntParams", {}).get("F_TRANSLUCENT", 0) == 1
				var expected := raw if translucent else 1.0 - raw
				assert(
					is_equal_approx(diagnostic.get_shader_parameter("source_exposure"), expected)
				)
		assert(materials.size() == count)
		var first_pass := materials[0].next_pass
		assert(Contrast.apply(model, path, context) == count)
		assert(materials[0].next_pass == first_pass, "rebind must reuse pass")
		for distance_m in [8.0, 22.0, 40.0]:
			camera.position = Vector3(0, 0.9, -distance_m)
			camera.look_at(Vector3(0, 0.9, 0))
			Contrast.detach(model)
			var baseline := await _capture("%s-%dm-baseline" % [id, distance_m])
			assert(Contrast.apply(model, path, context) == count)
			var adjusted := await _capture("%s-%dm-diagnostic" % [id, distance_m])
			var changed := 0
			for y in range(baseline.get_height()):
				for x in range(baseline.get_width()):
					if baseline.get_pixel(x, y) != adjusted.get_pixel(x, y):
						changed += 1
			if distance_m > 10.16:
				assert(changed > 100, "bound pass must affect visible original surfaces")
			else:
				assert(changed <= 100, "near surfaces must retain original shading")
			_records.append(
				{
					"profile": id,
					"distance_m": distance_m,
					"materials": count,
					"changed_pixels": changed
				}
			)
		var foreign := StandardMaterial3D.new()
		materials[0].next_pass = foreign
		assert(Contrast.apply(model, path, context) == count - 1)
		assert(materials[0].next_pass == foreign)
		assert(Contrast.apply(model, path, {}) == 0)
		assert(materials[0].next_pass == foreign)
		for original in materials.slice(1):
			assert(original.next_pass == null, "invalid input must detach stale passes")
		materials[0].next_pass = null
		model.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(_out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("CHARACTER_CONTRAST_INPUTS_PROBE_OK profiles=6 views=18 images=36")
	get_tree().quit()


func _capture(label: String) -> Image:
	for frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(_out.path_join(label + ".png")) == OK)
	return image
