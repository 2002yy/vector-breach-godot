extends Node

const Delivery = preload("res://scripts/characters/SourceCharacterSSAO.gd")
var _viewport: SubViewport
var _out: String


func _ready() -> void:
	get_tree().create_timer(120).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(320, 240)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	world.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.6
	environment.ssao_radius = 0.5
	environment.ssao_intensity = 4.0
	var effect := Delivery.new()
	world.compositor = Compositor.new()
	world.compositor.compositor_effects = [effect]
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position.z = 3
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	_viewport.add_child(camera)
	camera.make_current()
	var receiver := MeshInstance3D.new()
	receiver.mesh = QuadMesh.new()
	receiver.scale = Vector3(2, 1.5, 1)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/tests/source_ssao_delivery.gdshader")
	effect.bind(material)
	receiver.material_override = material
	_viewport.add_child(receiver)
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.scale = Vector3(0.3, 0.3, 0.3)
	blocker.position = Vector3(0.15, 0, 0.18)
	var opaque := StandardMaterial3D.new()
	opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opaque.albedo_color = Color(0.15, 0.15, 0.15)
	blocker.material_override = opaque
	_viewport.add_child(blocker)
	var records := []
	for ao in [1.0, 0.4, 0.0]:
		material.set_shader_parameter("material_ao", ao)
		var images := []
		for mode in range(3):
			material.set_shader_parameter("mode", mode)
			for enabled in [false, true]:
				environment.ssao_enabled = enabled
				effect.set_requested(enabled)
				images.append(await _capture("ao-%s-mode-%s-on-%s" % [ao, mode, enabled]))
		var baseline := _difference(images[0], images[2])
		var builtin := _difference(images[0], images[1])
		var bypass := _difference(images[2], images[3])
		var delivered := _difference(images[4], images[5])
		assert(baseline < 0.00002, "material AO must not be multiplied twice")
		assert(bypass == 0.0, "legacy emission should bypass SSAO")
		assert(_difference(images[2], images[4]) == 0.0, "off must preserve exact energy")
		if ao > 0.0:
			assert(delivered > 0.0001, "contact occlusion missing")
		if ao == 1.0:
			assert(builtin > 0.0001, "builtin control missing")
			assert(_difference(images[1], images[5]) < 0.00002, "same SSAO as engine")
		if ao == 0.0:
			assert(delivered == 0.0, "fully occluded material must stay black")
		records.append({"ao": ao, "baseline": baseline, "builtin": builtin, "delivered": delivered})
	# With candidate indirect removed, direct light and original emission are exact invariants.
	material.set_shader_parameter("mode", 2)
	material.set_shader_parameter("material_ao", 1.0)
	blocker.position.x = -0.5
	var moved := await _capture("moving-first-frame", 1)
	var settled := await _capture("moving-settled")
	assert(_difference(moved, settled) == 0.0, "SSAO must use current-frame geometry")
	# A caller must unbind before reallocating a viewport, then bind after warmup.
	effect.set_requested(false)
	effect.unbind(material)
	await _capture("resize-suspended")
	_viewport.size = Vector2i(400, 300)
	effect.set_requested(true)
	await _capture("resized-unbound")
	effect.bind(material)
	var resized := await _capture("resized-bound")
	material.set_shader_parameter("mode", 0)
	var resized_control := await _capture("resized-control")
	assert(_difference(resized, resized_control) < 0.00002, "resized SSAO mismatch")
	material.set_shader_parameter("mode", 2)
	material.set_shader_parameter("material_ao", 1.0)
	material.set_shader_parameter("indirect_energy", 0.0)
	material.set_shader_parameter("original_emission", 0.15)
	var sun := DirectionalLight3D.new()
	_viewport.add_child(sun)
	effect.set_requested(false)
	var guard_off := await _capture("direct-emission-off")
	effect.set_requested(true)
	var guard_on := await _capture("direct-emission-on")
	assert(_difference(guard_off, guard_on) == 0.0, "direct/emission changed")
	# Disable while Godot retains its old SSAO allocation: never sample stale shadows.
	environment.ssao_enabled = false
	effect.set_requested(false)
	material.set_shader_parameter("indirect_energy", 0.3)
	var disabled := await _capture("disabled-retained-buffer")
	material.set_shader_parameter("source_ssao_enabled", false)
	var detached := await _capture("unbound")
	assert(_difference(disabled, detached) == 0.0, "stale buffer after disable")
	effect.unbind(material)
	await _capture("teardown-suspended")
	world.compositor = null
	_viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var file := FileAccess.open(_out.path_join("ssao.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("CHARACTER_SSAO_OK ", records.size())
	get_tree().quit()


func _capture(label: String, frames := 8) -> Image:
	for frame in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	assert(image.save_png(_out.path_join(label + ".png")) == OK)
	return image


func _difference(a: Image, b: Image) -> float:
	var error := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			for channel in range(3):
				error += absf(first[channel] - second[channel])
	return error / (a.get_width() * a.get_height() * 3.0)
