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
	_material.set_shader_parameter("enable_aniso", false)
	_material.set_shader_parameter("feature_weight", 1.0)
	_material.set_shader_parameter("enable_retro", true)
	_material.set_shader_parameter("retro_texture", _texture(Color(1, 0, 0, 1)))
	var retro := await _capture("retro-red")
	_check_difference(baseline, retro, "native red mask changes retroreflection", true)
	_material.set_shader_parameter("retro_texture", _texture(Color(0, 1, 1, 1)))
	var no_retro := await _capture("retro-green-blue")
	_check_difference(baseline, no_retro, "green and blue cannot enable retroreflection", false)
	_material.set_shader_parameter("retro_texture", _texture(Color(1, 0, 0, 1)))
	_material.set_shader_parameter("feature_weight", 0.0)
	_check_difference(
		baseline, await _capture("retro-disabled"), "zero weight disables retroreflection", false
	)
	_material.set_shader_parameter("feature_weight", 1.0)
	light.light_energy = 0.0
	var dark_retro := await _capture("retro-without-light")
	_material.set_shader_parameter("enable_retro", false)
	_check_difference(
		dark_retro,
		await _capture("baseline-without-light"),
		"retroreflection does not emit light",
		false
	)
	light.light_energy = 1.0
	_material.set_shader_parameter("enable_hair", true)
	_material.set_shader_parameter("skin_texture", _texture(Color(1, 0, 0, 1)))
	_material.set_shader_parameter("hair_transmission", 1.0)
	_material.set_shader_parameter("hair_roughness_scale", 1.6)
	_material.set_shader_parameter("hair_shift", 0.35)
	var hair := await _capture("hair-red")
	_check_difference(baseline, hair, "red SSS mask enables the native hair lobe", true)
	_material.set_shader_parameter("skin_texture", _texture(Color(0, 1, 1, 1)))
	_check_difference(
		baseline, await _capture("hair-green-blue"), "skin green and blue cannot enable hair", false
	)
	_material.set_shader_parameter("skin_texture", _texture(Color(1, 0, 0, 1)))
	_material.set_shader_parameter("hair_shift", 0.0)
	var unshifted := await _capture("hair-unshifted")
	_check_difference(hair, unshifted, "hair shift moves the secondary highlight", true)
	_material.set_shader_parameter("hair_roughness_scale", 1.0)
	_check_difference(
		unshifted,
		await _capture("hair-scale-one"),
		"hair roughness scale changes the secondary lobe",
		true
	)
	var hair_full := await _capture("hair-transmission-one")
	_material.set_shader_parameter("hair_transmission", 0.0)
	_check_difference(
		hair_full,
		await _capture("hair-transmission-zero"),
		"hair transmission weights the secondary lobe",
		true
	)
	_material.set_shader_parameter("feature_weight", 0.0)
	_check_difference(
		baseline, await _capture("hair-disabled"), "zero weight disables hair shading", false
	)
	_material.set_shader_parameter("enable_hair", false)
	_material.set_shader_parameter("feature_weight", 1.0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 44
	var eye_baseline := await _capture("eye-baseline")
	_material.set_shader_parameter("eye_left_center", Vector3.ZERO)
	_material.set_shader_parameter("eye_right_center", Vector3(100, 0, 0))
	_material.set_shader_parameter("eye_left_forward", Vector3.BACK)
	_material.set_shader_parameter("eye_radius", 0.8)
	_material.set_shader_parameter("eye_mask_texture", _texture(Color(1, 0, 0, 1)))
	_material.set_shader_parameter("eye_albedo", _eye_texture())
	_material.set_shader_parameter("enable_eyes", true)
	var eyes := await _capture("eye-red")
	_check_difference(eye_baseline, eyes, "native eye sphere projects iris through red mask", true)
	_material.set_shader_parameter("eye_mask_texture", _texture(Color(0, 1, 1, 1)))
	_check_difference(
		eye_baseline,
		await _capture("eye-green-blue"),
		"eye mask green/blue do not replace skin",
		false
	)
	_material.set_shader_parameter("eye_mask_texture", _texture(Color(1, 0, 0, 1)))
	_material.set_shader_parameter("eye_radius", 0.0)
	_check_difference(
		eye_baseline, await _capture("eye-zero-radius"), "zero eye radius fails safely", false
	)
	_material.set_shader_parameter("eye_radius", 0.8)
	_material.set_shader_parameter("eye_pupil", 0.5)
	_check_difference(
		eyes, await _capture("eye-large-pupil"), "native pupil size changes pupil extent", true
	)
	_material.set_shader_parameter("eye_pupil", 0.15)
	_material.set_shader_parameter("eye_iris", 1.7)
	_check_difference(
		eyes, await _capture("eye-large-iris"), "native iris size changes radial sampling", true
	)
	_material.set_shader_parameter("eye_iris", 1.0)
	_material.set_shader_parameter("eye_hue", 1.8)
	_check_difference(eyes, await _capture("eye-hue"), "iris alpha gates native hue rotation", true)
	_material.set_shader_parameter("eye_hue", 0.0)
	_material.set_shader_parameter("eye_saturation", 0.0)
	_check_difference(
		eyes, await _capture("eye-desaturated"), "native saturation affects iris", true
	)
	_material.set_shader_parameter("eye_saturation", 1.0)
	_material.set_shader_parameter("feature_weight", 0.0)
	_check_difference(
		eye_baseline,
		await _capture("eye-disabled"),
		"zero weight restores original eye surface",
		false
	)
	_material.set_shader_parameter("feature_weight", 1.0)
	_material.set_shader_parameter("eye_albedo", _texture(Color(0.8, 0.2, 0.05, 0)))
	var no_iris_alpha := await _capture("eye-no-iris-alpha")
	_material.set_shader_parameter("eye_hue", 1.8)
	_material.set_shader_parameter("eye_saturation", 0.0)
	_check_difference(
		no_iris_alpha,
		await _capture("eye-sclera-unchanged"),
		"zero iris alpha protects sclera from hue and saturation",
		false
	)
	_material.set_shader_parameter("eye_left_center", Vector3(100, 0, 0))
	_check_difference(
		eye_baseline,
		await _capture("eye-ray-miss"),
		"ray missing both eye spheres preserves base surface",
		false
	)
	var file := FileAccess.open(_out.path_join("pixel-checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("CHARACTER_SHADING_GPU_OK checks=", _records.size())
	get_tree().quit()


func _texture(color: Color) -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _eye_texture() -> Texture2D:
	var image := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var radial := Vector2(x - 63.5, y - 63.5).length() / 64.0
			image.set_pixel(x, y, Color(0.8 * radial, 0.2, 0.05, 1.0))
	image.generate_mipmaps()
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
