extends "res://scripts/tests/CharacterDistanceContrastProbe.gd"

const Composite = preload("res://scripts/characters/SourceCharacterPostlit.gd")
const Adapter = preload("res://scripts/level/SourceProbeDiagnostic.gd")
const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")


func _ready() -> void:
	get_tree().create_timer(240).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	await _numeric_checks()
	assert(_records.size() == 26)
	assert(await _composite_stage())
	assert(await _roles(args))
	var file := FileAccess.open(_out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "\t"))
	print("CHARACTER_PROBE_COMPOSITE_OK checks=", _records.size())
	get_tree().quit()


func _composite_stage() -> bool:
	var world := Node3D.new()
	add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	camera.position.z = 40
	camera.environment = Environment.new()
	camera.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment.tonemap_exposure = 0.25
	world.add_child(camera)
	camera.make_current()
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)
	mesh.mesh = quad
	var base := StandardMaterial3D.new()
	base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = base
	world.add_child(mesh)
	var material := ShaderMaterial.new()
	material.shader = Composite.POSTLIT
	material.render_priority = -127
	material.set_shader_parameter(
		"game_to_source", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / 0.0254), Vector3.ZERO)
	)
	material.set_shader_parameter("source_probe_dimensions", Vector3(1, 1, 6))
	for name in Adapter.BUFFER_NAMES:
		var array := PackedVector4Array()
		array.resize(128)
		array[0] = {
			"origin_yaw": Vector4.ZERO,
			"min": Vector4(-5000, -5000, -5000, 0),
			"size": Vector4(10000, 10000, 10000, 0),
			"inv_edge": Vector4(10000, 10000, 10000, 0),
			"atlas_size": Vector4(1, 1, 1, 0),
			"atlas_offset": Vector4.ZERO
		}[name]
		material.set_shader_parameter("source_probe_" + name, array)
	var color := Vector3(0.2, 0.3, 0.4)
	var cases := [
		["far", {}, Vector3(0.36, 0.54, 0.72)],
		["near", {"distance": 8.0}, color],
		["zero-strength", {"contrast_strength": 0.0}, color],
		["zero-fog", {"fog_modification": 0.0}, color],
		["not-ready", {"inputs_ready": false}, color],
		["invalid-map", {"source_probe_count": 0}, color],
		["uncovered", {"outside": true}, color],
		["dark", {"color": Vector3.ZERO}, Vector3.ZERO],
		["directional", {"away": 0.25}, Vector3(0.28, 0.42, 0.56)],
		["bright-both", {"all": 1.0}, color],
		["exposure", {"source_exposure": 1.0}, Vector3(0.12, 0.18, 0.24)],
		[
			"global-only",
			{"source_exposure": 1.0, "material_adjustment": false},
			Vector3(0.36, 0.54, 0.72)
		],
		[
			"hdr",
			{"color": Vector3(2, 1.5, 0.5), "surface_albedo": Vector3.ONE},
			Vector3(1.6, 1.3, 0.9)
		],
		["black-texture", {"black_texture": true}, Vector3(0.04, 0.06, 0.08)]
	]
	var defaults := {
		"inputs_ready": true,
		"contrast_strength": 0.8,
		"fog_modification": 1.0,
		"source_probe_count": 1,
		"surface_albedo": Vector3.ONE * 0.5,
		"average_albedo": Vector3.ONE * 0.5,
		"source_exposure": 0.5,
		"material_adjustment": true
	}
	for test in cases:
		var options: Dictionary = test[1]
		for key in defaults:
			material.set_shader_parameter(key, options.get(key, defaults[key]))
		camera.position.z = options.get("distance", 40.0)
		var input: Vector3 = options.get("color", color)
		base.albedo_color = Color(input.x, input.y, input.z).linear_to_srgb()
		var layers: Array[Image] = []
		for face in range(6):
			var image := Image.create(1, 1, false, Image.FORMAT_RGBAF)
			var light: float = options.get("all", options.get("away", 0.0) if face == 5 else 0.0)
			image.fill(Color(light, light, light, 1))
			layers.append(image)
		var volume := ImageTexture3D.new()
		assert(volume.create(Image.FORMAT_RGBAF, 1, 1, 6, false, layers) == OK)
		material.set_shader_parameter("source_probe_texture", volume)
		var origins := PackedVector4Array()
		origins.resize(128)
		origins[0] = Vector4(100000, 0, 0, 0) if options.get("outside", false) else Vector4.ZERO
		material.set_shader_parameter("source_probe_origin_yaw", origins)
		var black := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		black.fill(Color.BLACK)
		material.set_shader_parameter("surface_texture", ImageTexture.create_from_image(black))
		material.set_shader_parameter("use_surface_texture", options.get("black_texture", false))
		base.next_pass = material
		var image := await _capture("stage-" + test[0])
		var pixel := image.get_pixel(image.get_width() / 2, image.get_height() / 2).srgb_to_linear()
		var actual := Vector3(pixel.r, pixel.g, pixel.b) / 0.25
		var expected: Vector3 = test[2]
		assert(actual.distance_to(expected) < 0.025, "%s / %s / %s" % [test[0], actual, expected])
		_records.append(
			{
				"composite_stage": test[0],
				"actual": str(actual),
				"expected": str(expected),
				"error": actual.distance_to(expected)
			}
		)
	world.queue_free()
	await get_tree().process_frame
	return true


func _roles(args: PackedStringArray) -> bool:
	var bundle: String = args[args.find("--bundle") + 1]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bundle))
	var level_data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + data.level + ".json")
	)
	var world := Node3D.new()
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-25, 145, 0)
	world.add_child(sun)
	var level: Node3D = preload("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.level_id = data.level
	world.add_child(level)
	var alignment := Adapter.alignment_from_visual(level.get_node("VisualRoot/LevelVisual"))
	var adapter := Adapter.new()
	assert(adapter.configure(bundle, level_data, alignment, true))
	var composite := Composite.new()
	var options := {
		"purpose": "diagnostic",
		"accept_average_candidate": true,
		"fog_input_kind": "diagnostic-constant",
		"strength": 0.8,
		"fog_modification": 1.0
	}
	assert(
		composite.configure(
			adapter,
			"res://assets/local_reference/cs_official/source-character-contrast-inputs.json",
			options
		)
	)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color("323b47")
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	camera.environment.ambient_light_color = Color.WHITE
	camera.environment.ambient_light_energy = 0.5
	world.add_child(camera)
	camera.make_current()
	var p: Array = data.spawn_samples[0].position_source
	var position := alignment * Vector3(p[0], p[1], p[2] - 64)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 2, position + Vector3.DOWN * 5
	)
	var ground := world.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not ground.is_empty())
	for id in ["ct-st6", "ct-sas-officer", "ct-fbi", "t-phoenix", "t-elite", "t-blackwolf"]:
		var model := Appearance.instantiate(id)
		assert(model != null)
		world.add_child(model)
		model.position = ground.position + Vector3.UP * 0.02
		for distance_m in [3.0, 40.0]:
			level.visible = distance_m < 10.16
			camera.position = model.position + Vector3(0, 0.9, -distance_m)
			camera.look_at(model.position + Vector3.UP * 0.9)
			var label := "%s-%dm" % [id, distance_m]
			var baseline := await _capture(label + "-baseline")
			var count := composite.attach(model)
			assert(count > 0, "no eligible live character materials: " + id)
			assert(composite.attach(model) == 0)
			for proxy in model.find_children("PostlitSurface*", "MeshInstance3D", true, false):
				var source := proxy.get_parent() as MeshInstance3D
				assert(proxy.skin == source.skin)
				assert(proxy.mesh.get_blend_shape_count() == source.mesh.get_blend_shape_count())
				if source.skin != null:
					assert(proxy.get_node(proxy.skeleton) == source.get_node(source.skeleton))
			var active := await _capture(label + "-composite")
			var difference := _difference(baseline, active)
			assert(
				difference > 0.0005 if distance_m > 10.16 else difference < 0.0001,
				label + " postlit difference=" + str(difference)
			)
			_records.append({"role": label, "difference": difference, "surfaces": count})
			model.position.x += 0.25
			await _capture(label + "-moved")
			model.position.x -= 0.25
			composite.detach()
		model.queue_free()
		await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame
	return true


func _difference(a: Image, b: Image) -> float:
	var difference := 0.0
	var count := 0
	for y in range(8, a.get_height() - 8, 4):
		for x in range(8, a.get_width() - 8, 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			difference += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return difference / count
