extends Node

const MATERIAL = preload("res://scripts/characters/SourceCharacterMaterials.gd")
var _out := "user://character-shading-proof"
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _records: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0
	add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 3)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation = Vector3(-0.35, -0.55, 0)
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh.mesh = sphere
	add_child(_mesh)
	var original := StandardMaterial3D.new()
	original.resource_name = "synthetic_native_character"
	original.albedo_color = Color(0.32, 0.2, 0.14).linear_to_srgb()
	original.roughness = 0.55
	var entry := {
		"native_material": {"IntParams": {}, "FloatParams": {}},
		"loaded_textures": {},
		"pending_features": []
	}
	_material = MATERIAL._material(original, entry)
	_mesh.material_override = _material
	_material.set_shader_parameter("spherical_aniso", true)
	_material.set_shader_parameter("aniso_pole", Vector3.UP)
	_material.set_shader_parameter("skin_texture", _texture(Color(0, 1, 0, 1)))
	_material.set_shader_parameter("skin_falloff", _texture(Color(1, 0.5, 0.5, 1)))
	_material.set_shader_parameter("cloth_texture", _texture(Color(0, 0, 1, 1)))
	_material.set_shader_parameter("aniso_texture", _texture(Color(0.18, 0.7, 0, 1)))
	var baseline := await _capture("baseline")
	_material.set_shader_parameter("enable_cloth", true)
	var cloth := await _capture("cloth")
	_check_difference(baseline, cloth, "cloth blue mask changes the direct lobe", true)
	_material.set_shader_parameter("cloth_texture", _texture(Color(1, 0, 0, 1)))
	var no_cloth := await _capture("cloth-red-only")
	_check_difference(baseline, no_cloth, "red channel must not act as cloth mask", false)
	_material.set_shader_parameter("enable_cloth", false)
	_material.set_shader_parameter("enable_skin", true)
	var skin := await _capture("skin")
	_check_difference(baseline, skin, "native green SSS mask changes the terminator", true)
	_material.set_shader_parameter("skin_texture", _texture(Color(1, 0, 0, 1)))
	var no_skin := await _capture("skin-red-only")
	_check_difference(baseline, no_skin, "red channel must not enable skin diffusion", false)
	_material.set_shader_parameter("enable_skin", false)
	_material.set_shader_parameter("enable_aniso", true)
	var aniso := await _capture("aniso-0")
	_material.set_shader_parameter("aniso_angle", 90.0)
	var rotated := await _capture("aniso-90")
	_check_difference(aniso, rotated, "rotating the anisotropic axis changes the highlight", true)
	_material.set_shader_parameter("aniso_texture", _texture(Color(0.55, 0.55, 0, 1)))
	var iso90 := await _capture("isotropic-90")
	_material.set_shader_parameter("aniso_angle", 0.0)
	var iso0 := await _capture("isotropic-0")
	_check_difference(iso90, iso0, "equal roughness axes remain rotation invariant", false)
	_material.set_shader_parameter("feature_weight", 0.0)
	var disabled := await _capture("features-disabled")
	_check_difference(baseline, disabled, "zero feature weight restores baseline", false)
	var file := FileAccess.open(_out.path_join("pixel-checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("CHARACTER_SHADING_GPU_OK checks=7")
	get_tree().quit()


func _texture(color: Color) -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _capture(label: String) -> Image:
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(_out.path_join(label + ".png")) == OK)
	return image


func _check_difference(a: Image, b: Image, label: String, should_change: bool) -> void:
	var difference := 0.0
	var samples := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			assert(is_finite(cb.r) and is_finite(cb.g) and is_finite(cb.b))
			difference += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			samples += 3
	difference /= samples
	_records.append({"check": label, "mean_difference": difference, "should_change": should_change})
	print("SHADING_GPU_CHECK ", label, " difference=", difference)
	assert(difference > 0.0005 if should_change else difference < 0.0001, label)
