extends Node

const NUMERIC = preload("res://scripts/tests/distance_contrast_numeric.gdshader")
const POSTLIT = preload("res://scripts/characters/distance_contrast_postlit.gdshader")
var _out := "user://distance-contrast-proof"
var _records: Array = []


func _ready() -> void:
	get_tree().create_timer(60).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	await _numeric_checks()
	await _stage_checks()
	var file := FileAccess.open(_out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("DISTANCE_CONTRAST_GPU_OK checks=", _records.size())
	get_tree().quit()


func _numeric_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var material := ShaderMaterial.new()
	material.shader = NUMERIC
	rect.material = material
	viewport.add_child(rect)
	var original := Vector3(0.2, 0.3, 0.4)
	var full := Vector3(0.36, 0.54, 0.72)
	var half_distance := Vector3(0.28, 0.42, 0.56)
	# Analytic goldens: gray average/surface=.5 yields curve=.5 and gain=4.
	# Thus the far weight=.8 gives 1.8*C; midpoint gives 1.4*C. HDR cases
	# independently exercise the min(1,...) and preserved excess components.
	var cases := [
		["far", {}, full],
		["near", {"distance_m": 399.0 * 0.0254}, original],
		["threshold", {"distance_m": 400.0 * 0.0254}, original],
		["midpoint", {"distance_m": 900.0 * 0.0254}, half_distance],
		["zero-strength", {"contrast_strength": 0.0}, original],
		["strength-cap", {"contrast_strength": 2.0}, full],
		["fog-zero", {"fog_modification": 0.0}, original],
		["fog-half", {"fog_modification": 0.5}, half_distance],
		["invalid-unit", {"source_unit_m": 0.0}, original],
		["exposure", {"source_exposure": 1.0}, Vector3(0.12, 0.18, 0.24)],
		["exposure-disabled", {"source_exposure": 1.0, "material_adjustment": false}, full],
		[
			"hdr-exposure",
			{"lit_color": Vector3(2, 1.5, 0.5), "surface_albedo": Vector3.ONE},
			Vector3(1.6, 1.3, 0.9)
		],
		[
			"hdr-no-adjustment",
			{
				"lit_color": Vector3(2, 1.5, 0.5),
				"surface_albedo": Vector3.ONE,
				"material_adjustment": false
			},
			Vector3(2, 1.5, 0.9)
		],
		[
			"both-directions-bright",
			{"irradiance_away": Vector3.ONE, "irradiance_toward": Vector3.ONE},
			original
		],
		["away-quarter", {"irradiance_away": Vector3.ONE * 0.25}, half_distance],
		["toward-half", {"irradiance_toward": Vector3.ONE * 0.5}, half_distance],
		["saturated-average", {"average_albedo": Vector3(1, 0, 0)}, full],
		[
			"black-average-safe",
			{"average_albedo": Vector3.ZERO, "source_exposure": 0.0},
			Vector3(0.04, 0.06, 0.08)
		],
		["white-average", {"average_albedo": Vector3.ONE}, original],
		["negative-strength", {"contrast_strength": -1.0}, original],
		["negative-fog", {"fog_modification": -1.0}, original],
		["black-lit", {"lit_color": Vector3.ZERO}, Vector3.ZERO],
		["near-hdr", {"distance_m": 1.0, "lit_color": Vector3(2, 1.5, 0.5)}, Vector3(2, 1.5, 0.5)],
		["scene-unit-scale", {"source_unit_m": 0.0508}, Vector3(0.23456, 0.35184, 0.46912)],
		[
			"gray-average-normalization",
			{"average_albedo": Vector3.ONE * 0.6, "surface_albedo": Vector3.ONE * 0.6},
			full
		],
		["black-surface", {"surface_albedo": Vector3.ZERO}, Vector3(0.04, 0.06, 0.08)]
	]
	var defaults := {
		"lit_color": original,
		"surface_albedo": Vector3.ONE * 0.5,
		"average_albedo": Vector3.ONE * 0.5,
		"irradiance_away": Vector3.ZERO,
		"irradiance_toward": Vector3.ZERO,
		"distance_m": 1400.0 * 0.0254,
		"source_unit_m": 0.0254,
		"source_exposure": 0.5,
		"contrast_strength": 0.8,
		"fog_modification": 1.0,
		"material_adjustment": true
	}
	for item in cases:
		for key in defaults:
			material.set_shader_parameter(key, item[1].get(key, defaults[key]))
		await _frames()
		var color := viewport.get_texture().get_image().get_pixel(4, 4)
		var actual := Vector3(color.r, color.g, color.b)
		var expected: Vector3 = item[2]
		assert(
			actual.is_finite() and actual.distance_to(expected) < 0.004,
			"%s expected=%s actual=%s" % [item[0], expected, actual]
		)
		_records.append({"numeric": item[0], "expected": str(expected), "actual": str(actual)})
	viewport.queue_free()
	await get_tree().process_frame


func _stage_checks() -> void:
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("17212b")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.0
	world.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0, 0, 40)
	world.add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.light_energy = 1.0
	world.add_child(light)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)
	mesh.mesh = quad
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.2, 0.3, 0.4).linear_to_srgb()
	base.roughness = 1.0
	mesh.material_override = base
	world.add_child(mesh)
	var pass_material := ShaderMaterial.new()
	pass_material.shader = POSTLIT
	pass_material.render_priority = -127
	pass_material.set_shader_parameter("contrast_strength", 0.8)
	pass_material.set_shader_parameter("fog_modification", 1.0)
	var baseline := await _capture("stage-far-baseline")
	base.next_pass = pass_material
	_check(
		baseline,
		await _capture("stage-invalid-inputs"),
		"missing inputs leave opaque lighting unchanged",
		false
	)
	pass_material.set_shader_parameter("inputs_ready", true)
	var far := await _capture("stage-far-enabled")
	_check(baseline, far, "far correction reads already lit color", true)
	pass_material.set_shader_parameter("irradiance_away", Vector3.ONE * 0.25)
	var flat_irradiance := await _capture("stage-direction-flat")
	pass_material.set_shader_parameter("use_directional_sh1", true)
	for channel in ["irradiance_sh_r", "irradiance_sh_g", "irradiance_sh_b"]:
		# Camera looks along -Z: away=.25, toward=0 across this distant quad.
		pass_material.set_shader_parameter(channel, Vector4(0, 0, -0.125, 0.125))
	_check(
		flat_irradiance,
		await _capture("stage-direction-sh1"),
		"SH1 matches independently supplied two-direction irradiance",
		false
	)
	pass_material.set_shader_parameter("use_directional_sh1", false)
	pass_material.set_shader_parameter("irradiance_away", Vector3.ZERO)
	var texture_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	texture_image.fill(Color.BLACK)
	pass_material.set_shader_parameter(
		"surface_texture", ImageTexture.create_from_image(texture_image)
	)
	pass_material.set_shader_parameter("use_surface_texture", true)
	var textured_black := await _capture("stage-textured-black")
	pass_material.set_shader_parameter("use_surface_texture", false)
	pass_material.set_shader_parameter("surface_albedo", Vector3.ZERO)
	_check(
		textured_black,
		await _capture("stage-flat-black"),
		"source-color texture participates in surface albedo",
		false
	)
	_check(
		far, textured_black, "texture changes response rather than using a constant albedo", true
	)
	pass_material.set_shader_parameter("surface_albedo", Vector3.ONE * 0.5)
	light.light_energy = 0.0
	base.next_pass = null
	var unlit := await _capture("stage-no-light-baseline")
	base.next_pass = pass_material
	_check(
		unlit,
		await _capture("stage-no-light-enabled"),
		"postlit correction does not invent light",
		false
	)
	light.light_energy = 1.0
	camera.position.z = 8.0
	base.next_pass = null
	var near := await _capture("stage-near-baseline")
	base.next_pass = pass_material
	_check(
		near, await _capture("stage-near-enabled"), "near geometry retains original shading", false
	)
	camera.position.z = 40.0
	pass_material.set_shader_parameter("fog_modification", 0.0)
	_check(
		baseline,
		await _capture("stage-fog-gated"),
		"zero native fog modification gates correction",
		false
	)
	pass_material.set_shader_parameter("fog_modification", 1.0)
	var wall := MeshInstance3D.new()
	wall.mesh = quad
	wall.position.z = 1.0
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("6c5140")
	wall.material_override = wall_material
	world.add_child(wall)
	base.next_pass = null
	var blocked := await _capture("stage-blocked-baseline")
	base.next_pass = pass_material
	_check(
		blocked,
		await _capture("stage-blocked-enabled"),
		"opaque wall occludes the correction pass",
		false
	)
	wall.visible = false
	env.environment.fog_enabled = true
	env.environment.fog_density = 0.025
	pass_material.set_shader_parameter("contrast_strength", 0.0)
	base.next_pass = null
	var fogged := await _capture("stage-fog-baseline")
	base.next_pass = pass_material
	_check(
		fogged,
		await _capture("stage-fog-zero-strength"),
		"identity pass does not apply scene fog twice",
		false
	)
	env.environment.fog_enabled = false
	pass_material.set_shader_parameter("contrast_strength", 0.8)
	var foreground := MeshInstance3D.new()
	foreground.mesh = quad
	foreground.position.z = 2.0
	var transparent := StandardMaterial3D.new()
	transparent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent.albedo_color = Color(0.8, 0.1, 0.05, 0.5)
	foreground.material_override = transparent
	world.add_child(foreground)
	_check(
		far,
		await _capture("stage-foreground"),
		"foreground transparency survives the early correction pass",
		true
	)
	base.next_pass = null
	var alpha_baseline := await _capture("stage-foreground-baseline")
	base.next_pass = pass_material
	pass_material.set_shader_parameter("contrast_strength", 0.0)
	_check(
		alpha_baseline,
		await _capture("stage-foreground-identity"),
		"identity does not erase foreground transparent color",
		false
	)
	world.queue_free()
	await get_tree().process_frame


func _frames() -> void:
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(label: String) -> Image:
	await _frames()
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(_out.path_join(label + ".png")) == OK)
	return image


func _check(a: Image, b: Image, label: String, changes: bool) -> void:
	var difference := 0.0
	var count := 0
	for y in range(8, a.get_height() - 8, 4):
		for x in range(8, a.get_width() - 8, 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			difference += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	difference /= count
	print("DISTANCE_STAGE_CHECK ", label, " difference=", difference)
	assert(difference > 0.0005 if changes else difference < 0.0001, label)
	_records.append({"stage": label, "difference": difference, "changes": changes})
