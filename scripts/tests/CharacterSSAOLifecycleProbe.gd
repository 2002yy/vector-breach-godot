extends "res://scripts/tests/CharacterSSAOProbe.gd"

const Owner = preload("res://scripts/characters/SourceCharacterSSAOOwner.gd")


func _ready() -> void:
	get_tree().create_timer(120).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	var root_world := WorldEnvironment.new()
	add_child(root_world)
	var unsupported := Owner.new()
	root_world.add_child(unsupported)
	assert(not unsupported.attach(root_world), "root viewport must reject unsafe ownership")
	assert(root_world.compositor == null)
	root_world.queue_free()
	var fixture := _fixture()
	_viewport = fixture.viewport
	var owner: Node = fixture.owner
	var material: ShaderMaterial = fixture.material
	var world: WorldEnvironment = fixture.world
	var environment := world.environment
	var cold := await _capture("cold-first-frame", 1)
	material.set_shader_parameter("mode", 1)
	var neutral := await _capture("cold-neutral")
	assert(_difference(cold, neutral) == 0.0, "cold start must fail open to neutral")
	material.set_shader_parameter("mode", 2)
	await _control(material, "warm")
	environment.ssao_enabled = false
	var disabled := await _capture("environment-off", 1)
	assert(material.get_shader_parameter("source_ssao_enabled") == false)
	assert(_difference(disabled, neutral) == 0.0, "environment switch must disable sampling")
	environment.ssao_enabled = true
	await _control(material, "environment-on")
	var resizes := []
	for size in [Vector2i(400, 300), Vector2i(256, 192), Vector2i(320, 240), Vector2i(480, 270)]:
		var old_target: RID = owner.effect.texture.texture_rd_rid
		var old_generation: int = owner.effect._generation
		# Simulate a queued publication from the allocation that is about to die.
		owner.effect._publish.call_deferred(old_target, old_generation)
		owner.request_size(size)
		await owner.reconfigured
		var first := await _capture("resize-%s-first" % size.x, 1)
		assert(first.get_size() == size)
		material.set_shader_parameter("mode", 1)
		var clear := await _capture("resize-%s-neutral" % size.x)
		assert(_difference(first, clear) == 0.0, "resize first frame must not sample old SSAO")
		material.set_shader_parameter("mode", 2)
		resizes.append(await _control(material, "resize-%s" % size.x))
	# Resource replacement and render-buffer reconfiguration need the same barrier.
	world.environment = environment.duplicate()
	world.environment.ssao_enabled = false
	await _capture("replacement-disabled", 1)
	assert(material.get_shader_parameter("source_ssao_enabled") == false)
	world.environment = environment
	await _control(material, "replacement-restored")
	owner.request_render_settings(0.75, Viewport.MSAA_4X)
	await owner.reconfigured
	await _control(material, "scaled-msaa")
	owner.request_render_settings(1.0, Viewport.MSAA_DISABLED)
	await owner.reconfigured
	await _control(material, "full-resolution")
	# Preserve the exact pre-existing compositor and external replacement ownership.
	owner.detach()
	assert(world.compositor == fixture.original)
	assert(material.get_shader_parameter("source_ssao_enabled") == false)
	assert(owner.attach(world))
	assert(owner.bind(material))
	await _control(material, "reattached")
	var foreign := Compositor.new()
	world.compositor = foreign
	await _capture("external-owner", 1)
	assert(owner.effect == null and world.compositor == foreign)
	assert(material.get_shader_parameter("source_ssao_enabled") == false)
	assert(owner.attach(world))
	assert(owner.bind(material))
	await _control(material, "foreign-preserved")
	owner.request_size(Vector2i(600, 400))
	owner.request_size(Vector2i(420, 280))
	owner.request_size(Vector2i(512, 384))
	await owner.reconfigured
	assert(_viewport.size == Vector2i(512, 384), "resize requests must coalesce to latest")
	await _control(material, "coalesced")
	# Real OS window events resize only the owned SubViewport through the barrier.
	owner.detach()
	assert(owner.attach(world, true))
	assert(owner.bind(material))
	var window := get_window()
	var original_window_size := window.size
	window.size = Vector2i(640, 480)
	await owner.reconfigured
	assert(_viewport.size == window.size)
	await _control(material, "window-resized")
	owner.detach()
	window.size = original_window_size
	assert(owner.attach(world))
	assert(owner.bind(material))
	var takeover_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	takeover_image.fill(Color.WHITE)
	var takeover := ImageTexture.create_from_image(takeover_image)
	material.set_shader_parameter("source_ssao_texture", takeover)
	material.set_shader_parameter("source_ssao_enabled", true)
	owner.detach()
	assert(material.get_shader_parameter("source_ssao_texture") == takeover)
	assert(material.get_shader_parameter("source_ssao_enabled") == true)
	assert(owner.attach(world))
	assert(owner.bind(material))
	# A second simultaneous viewport must have its own publication and teardown.
	var cancellations := []
	var observe := func(applied: bool) -> void: cancellations.append(applied)
	owner.reconfigured.connect(observe)
	var size_before_cancel := _viewport.size
	owner.request_size(Vector2i(900, 500))
	owner.detach()
	assert(cancellations == [false], "canceled transaction must notify its caller")
	assert(owner.attach(world))
	assert(owner.bind(material))
	await _control(material, "canceled-reattached")
	assert(_viewport.size == size_before_cancel and cancellations == [false])
	owner.reconfigured.disconnect(observe)
	var first_viewport := _viewport
	for index in range(3):
		var second := _fixture()
		_viewport = second.viewport
		assert(second.owner.effect.texture != owner.effect.texture)
		await _control(second.material, "independent-%s" % index)
		second.viewport.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		assert(second.material.get_shader_parameter("source_ssao_enabled") == false)
		_viewport = first_viewport
		await _control(material, "surviving-%s" % index)
	# Cancel an in-flight transaction and retain its effect to test late callbacks.
	var retired: CompositorEffect = owner.effect
	var retired_target: RID = retired.texture.texture_rd_rid
	var retired_generation: int = retired._generation
	owner.request_size(Vector2i(800, 450))
	owner.queue_free()
	await get_tree().process_frame
	assert(world.compositor == foreign)
	assert(material.get_shader_parameter("source_ssao_enabled") == false)
	_viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	retired._publish(retired_target, retired_generation)
	var file := FileAccess.open(_out.path_join("lifecycle.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"resizes": resizes, "independent_teardowns": 3}, "\t"))
	print("CHARACTER_SSAO_LIFECYCLE_OK")
	get_tree().quit()


func _fixture() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	world.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.6
	environment.ssao_radius = 0.5
	environment.ssao_intensity = 4.0
	environment.ssao_enabled = true
	var original := Compositor.new()
	var existing := CompositorEffect.new()
	existing.enabled = false
	original.compositor_effects = [existing]
	world.compositor = original
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position.z = 3
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	viewport.add_child(camera)
	camera.make_current()
	var receiver := MeshInstance3D.new()
	receiver.mesh = QuadMesh.new()
	receiver.scale = Vector3(2, 1.5, 1)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/tests/source_ssao_delivery.gdshader")
	material.set_shader_parameter("mode", 2)
	receiver.material_override = material
	viewport.add_child(receiver)
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.scale = Vector3(0.3, 0.3, 0.3)
	blocker.position = Vector3(0.15, 0, 0.18)
	var opaque := StandardMaterial3D.new()
	opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opaque.albedo_color = Color(0.15, 0.15, 0.15)
	blocker.material_override = opaque
	viewport.add_child(blocker)
	var owner := Owner.new()
	world.add_child(owner)
	assert(owner.attach(world))
	assert(owner.bind(material))
	return {
		"viewport": viewport,
		"world": world,
		"owner": owner,
		"material": material,
		"original": original,
	}


func _control(material: ShaderMaterial, label: String) -> float:
	material.set_shader_parameter("mode", 2)
	var delivered := await _capture(label + "-delivered")
	material.set_shader_parameter("mode", 0)
	var engine := await _capture(label + "-engine")
	material.set_shader_parameter("mode", 1)
	var neutral := await _capture(label + "-neutral")
	material.set_shader_parameter("mode", 2)
	var error := _difference(delivered, engine)
	assert(error < 0.00002, "owned SSAO must match engine")
	assert(_difference(delivered, neutral) > 0.0001, "owned SSAO positive control missing")
	return error
