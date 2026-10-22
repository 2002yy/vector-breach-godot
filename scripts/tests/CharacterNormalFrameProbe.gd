extends "res://scripts/tests/CharacterEnvironmentProbe.gd"

const FRAME_PREFIX := """
#include "res://scripts/characters/source_normal_frame.gdshaderinc"
uniform int diagnostic_mode = 0;
varying vec3 diagnostic_new;
varying vec3 diagnostic_old;
"""
const FRAME_FRAGMENT := """
diagnostic_new=source_mapped_normal(NORMAL_MAP,NORMAL_MAP_DEPTH,TANGENT,BINORMAL,NORMAL);
vec3 old_micro=use_normal ? NORMAL_MAP*2.0-1.0 : vec3(0,0,1);
old_micro.xy*=NORMAL_MAP_DEPTH;
old_micro.z=sqrt(max(1.0-dot(old_micro.xy,old_micro.xy),0.0));
diagnostic_old=safe_normalize(basis_t*old_micro.x+basis_b*old_micro.y
    +geom_normal*old_micro.z,geom_normal);
ALBEDO=vec3(1.0); METALLIC=0.0; AO=1.0;
RADIANCE=vec4(0,0,0,1); IRRADIANCE=vec4(0,0,0,1); EMISSION=vec3(0.0);
"""
const FRAME_LIGHT := """
void light() {
vec3 n=diagnostic_mode==0 ? NORMAL : (diagnostic_mode==1 ? diagnostic_new : diagnostic_old);
DIFFUSE_LIGHT+=n*0.5+0.5;
}
"""


func _ready() -> void:
	get_tree().create_timer(240).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var out: String = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	await _numeric_frame(out, args[args.find("--normal-cases") + 1])
	await _ssao_boundary(out)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_energy = 0
	add_child(world)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35
	camera.position = Vector3(0, 1.65, -1.8)
	add_child(camera)
	camera.look_at(Vector3(0, 1.65, 0))
	camera.make_current()
	var records := []
	for id in Appearance.NAMES:
		var model := Appearance.instantiate(id)
		assert(model != null)
		add_child(model)
		model.look_at(Vector3(0, 0, -2))
		var materials := []
		var follower := (
			preload("res://scripts/characters/SourceEnvironmentMaterialFollower.gd").new()
		)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				var original := mesh.get_active_material(surface) as ShaderMaterial
				if original == null or original.shader.code.count(Composite.ANCHOR) != 1:
					continue
				var copy: ShaderMaterial = original.duplicate()
				var shader := Shader.new()
				var code: String = original.shader.code
				code = code.substr(0, code.find("void light() {")) + FRAME_LIGHT
				shader.code = (
					code
					. replace(
						"// Source character channel contracts",
						FRAME_PREFIX + "// Source character channel contracts"
					)
					. replace(Composite.ANCHOR, Composite.ANCHOR + FRAME_FRAGMENT)
				)
				copy.shader = shader
				mesh.set_surface_override_material(surface, copy)
				materials.append(copy)
				follower.bindings.append({"original": original, "copy": copy, "mesh": mesh})
		assert(not materials.is_empty())
		model.add_child(follower)
		var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for pose in [0.0, 0.6]:
			player.play("run")
			player.pause()
			player.seek(player.get_animation("run").length * pose, true)
			model.scale = Vector3.ONE if pose == 0.0 else Vector3(0.8, 1.15, 1.1)
			for strength in [0.0, 0.5, 1.0, 2.0]:
				var images := []
				var label := "%s-pose-%s-strength-%s" % [id, pose, strength]
				for mode in range(3):
					for material in materials:
						material.set_shader_parameter("normal_strength", strength)
						material.set_shader_parameter("diagnostic_mode", mode)
					images.append(await _capture(out, label + "-mode-%s" % mode))
				var error := _difference(images[0], images[1])
				assert(error < 0.00002, "mapped frame must agree with engine light NORMAL")
				records.append(
					{
						"label": label,
						"error": error,
						"legacy_error": _difference(images[0], images[2]),
						"materials": materials.size()
					}
				)
		model.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(out.path_join("normal-frames.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("CHARACTER_NORMAL_FRAME_OK ", records.size())
	get_tree().quit()


func _numeric_frame(out: String, path: String) -> void:
	var tests: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(tests.size() == 216)
	var input := Image.create(tests.size(), 4, false, Image.FORMAT_RGBAF)
	for index in range(tests.size()):
		var test: Dictionary = tests[index]
		for row in range(4):
			var values: Array = [test.encoded, test.tangent, test.bitangent, test.normal][row]
			input.set_pixel(
				index, row, Color(values[0], values[1], values[2], test.depth if row == 0 else 1.0)
			)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(tests.size(), 1)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = viewport.size
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/tests/source_normal_frame_numeric.gdshader")
	material.set_shader_parameter("cases", ImageTexture.create_from_image(input))
	rect.material = material
	viewport.add_child(rect)
	var actual := await _read(viewport)
	var maximum := 0.0
	for index in range(tests.size()):
		var expected: Array = tests[index].expected
		var pixel := actual.get_pixel(index, 0)
		for c in range(3):
			var error := absf(pixel[c] - expected[c])
			maximum = maxf(maximum, error)
			assert(is_finite(pixel[c]) and error < 0.002)
	assert(actual.save_png(out.path_join("normal-numeric.png")) == OK)
	var file := FileAccess.open(out.path_join("normal-numeric.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": tests.size(), "max_error": maximum}, "\t"))
	viewport.queue_free()
	await get_tree().process_frame


func _ssao_boundary(out: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	world.environment.ssao_radius = 0.5
	world.environment.ssao_intensity = 4.0
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
	material.shader = preload("res://scripts/tests/source_ssao_boundary.gdshader")
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
	var images := []
	for emission in [false, true]:
		material.set_shader_parameter("emission_mode", emission)
		for enabled in [false, true]:
			world.environment.ssao_enabled = enabled
			for frame in range(10):
				await get_tree().process_frame
			var actual := await _read(viewport)
			assert(
				(
					actual.save_png(
						out.path_join("ssao-emission-%s-enabled-%s.png" % [emission, enabled])
					)
					== OK
				)
			)
			images.append(actual)
	var lit_difference := _difference(images[0], images[1])
	var emission_difference := _difference(images[2], images[3])
	assert(lit_difference > 0.0001, "SSAO control must affect actual indirect receiver")
	assert(emission_difference < 0.00001, "emission-path SSAO boundary changed")
	var file := FileAccess.open(out.path_join("ssao-boundary.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{"builtin_difference": lit_difference, "emission_difference": emission_difference}, "\t"
		)
	)
	viewport.queue_free()
	await get_tree().process_frame
