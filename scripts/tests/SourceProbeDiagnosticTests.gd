extends Node3D

const Adapter = preload("res://scripts/level/SourceProbeDiagnostic.gd")
const Composite = preload("res://scripts/characters/SourceCharacterPostlit.gd")
var _folder := "user://probe-adapter-tests-" + str(OS.get_process_id())
var _path: String
var _data: Dictionary
var _level := {"id": "fixture", "sourceTrace": {"vpkSha256": "a".repeat(64)}}
var _alignment := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0254), Vector3.ZERO)


func _ready() -> void:
	get_tree().create_timer(15).timeout.connect(func() -> void: get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute(_folder)
	_path = _folder.path_join("lighting.json")
	var floats := PackedFloat32Array()
	for face in range(6):
		floats.append_array(PackedFloat32Array([float(face + 1), 2.0, 3.0, 1.0]))
	var raw := floats.to_byte_array()
	var file := FileAccess.open(_folder.path_join("volume.bin"), FileAccess.WRITE)
	file.store_buffer(raw)
	file.close()
	var probe := {
		"sample_supported": true,
		"enabled": true,
		"texture": "native.vtex",
		"origin": [0, 0, 0],
		"bounds_min": [-1, -1, -1],
		"bounds_size": [2, 2, 2],
		"edge_fade": [0, 0, 0],
		"atlas_size": [1, 1, 1],
		"atlas_offset": [0, 0, 0],
		"priority": 0,
		"yaw_degrees": 0
	}
	_data = {
		"schema": 1,
		"contract": "source-map-lighting-diagnostic-v1",
		"level": "fixture",
		"source_trace": {"vpkSha256": "a".repeat(64)},
		"probes": [probe],
		"child_lumps_not_instantiated": [],
		"sources":
		{
			"native.vtex":
			{
				"decoded":
				{
					"layout": "zyx-rgba-f32-le",
					"dimensions": [1, 1, 6],
					"file": "volume.bin",
					"sha256": FileAccess.get_sha256(_folder.path_join("volume.bin"))
				}
			}
		}
	}
	_save(_data)
	var adapter := Adapter.new()
	assert(not adapter.configure(_path, _level, _alignment))
	assert(adapter.configure(_path, _level, _alignment, true))
	assert(not Adapter.valid_alignment(Transform3D.IDENTITY))
	assert(
		not Adapter.valid_alignment(
			Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		)
	)
	var visual := Node3D.new()
	add_child(visual)
	var alignment := Node3D.new()
	alignment.name = "OfficialSourceAlignment"
	alignment.position = Vector3(17.018, 4.064, -21.5138)
	alignment.rotation.y = PI / 2
	visual.add_child(alignment)
	var transform := Adapter.alignment_from_visual(visual)
	assert(Adapter.valid_alignment(transform))
	assert(
		(
			(transform * Vector3(100, 200, 300)).distance_to(Vector3(19.558, 11.684, -26.5938))
			< 0.00001
		)
	)
	var mesh := MeshInstance3D.new()
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
	mesh.mesh = geometry
	var original := StandardMaterial3D.new()
	mesh.material_override = null
	mesh.mesh.surface_set_material(0, original)
	visual.add_child(mesh)
	assert(adapter.attach(visual) == 1)
	assert(adapter.attach(visual) == 0)
	assert(original.next_pass == null, "shared original must never change")
	var copied := mesh.get_surface_override_material(0)
	assert(copied != original and copied.next_pass != null)
	adapter.detach()
	assert(mesh.get_surface_override_material(0) == null)
	original.next_pass = StandardMaterial3D.new()
	assert(adapter.attach(visual) == 0, "preserve foreign pass")
	original.next_pass = null
	var material := ShaderMaterial.new()
	material.shader = Adapter.DISPLAY
	assert(adapter.bind(material))
	var invalid := _data.duplicate(true)
	invalid.source_trace.vpkSha256 = "b".repeat(64)
	_save(invalid)
	assert(not adapter.configure(_path, _level, _alignment, true))
	assert(material.get_shader_parameter("source_probe_count") == 0)
	assert(material.get_shader_parameter("source_probe_texture") == null)
	for field in ["sha256", "file", "dimensions", "layout"]:
		invalid = _data.duplicate(true)
		invalid.sources["native.vtex"].decoded[field] = {
			"sha256": "bad", "file": "../outside", "dimensions": [1.5, 1, 6], "layout": "rgba8"
		}[field]
		_save(invalid)
		assert(not adapter.configure(_path, _level, _alignment, true))
	invalid = _data.duplicate(true)
	invalid.probes = "malformed"
	_save(invalid)
	assert(not adapter.configure(_path, _level, _alignment, true))
	invalid = _data.duplicate(true)
	invalid.probes[0].atlas_offset = [1, 0, 0]
	_save(invalid)
	assert(not adapter.configure(_path, _level, _alignment, true))
	var sorted := _data.duplicate(true)
	var high := probe.duplicate(true)
	high.priority = 2
	high.origin = [20, 0, 0]
	var peer := high.duplicate(true)
	peer.origin = [30, 0, 0]
	sorted.probes = [probe, high, peer]
	_save(sorted)
	assert(adapter.configure(_path, _level, _alignment, true))
	assert(adapter.bind(material))
	var buffer: PackedVector4Array = material.get_shader_parameter("source_probe_origin_yaw")
	assert(
		buffer[0].x == 20 and buffer[1].x == 30 and buffer[2].x == 0,
		"priority ties must preserve source order"
	)
	assert(await _composite(adapter, visual, mesh))
	adapter.detach()
	visual.queue_free()
	for name in ["lighting.json", "volume.bin", "source-materials.json", "character-inputs.json"]:
		DirAccess.remove_absolute(_folder.path_join(name))
	DirAccess.remove_absolute(_folder)
	print("SOURCE_PROBE_ADAPTER_TESTS_OK boundaries=11")
	print("SOURCE_CHARACTER_COMPOSITE_TESTS_OK boundaries=8")
	print("[SourceProbeDiagnosticTests] PASS (1 tests)")
	get_tree().quit()


func _save(data: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))


func _composite(adapter: RefCounted, root: Node, mesh: MeshInstance3D) -> bool:
	var source := FileAccess.open(_folder.path_join("source-materials.json"), FileAccess.WRITE)
	source.store_string("{}")
	source.close()
	var native := {
		"ShaderName": "csgo_character.vfx",
		"FloatParams": {"g_fDistanceContrastExposure": 0.8},
		"IntParams": {"F_DISTANCE_CONTRAST_ADJUSTMENT": 1}
	}
	var original := ShaderMaterial.new()
	native = JSON.parse_string(JSON.stringify(native))
	original.shader = preload("res://scripts/characters/native_character.gdshader")
	original.resource_name = "fixture"
	original.set_shader_parameter("base_color", Vector4.ONE)
	original.set_shader_parameter("uv_scale", Vector3.ONE)
	original.set_shader_parameter("uv_offset", Vector3.ZERO)
	original.set_shader_parameter("use_base", false)
	original.set_meta("source_material_parameters", native)
	mesh.mesh.surface_set_material(0, original)
	var profile := {
		"schema": 1,
		"contract": "source-character-contrast-inputs-v1",
		"materials_manifest_sha256":
		FileAccess.get_sha256(_folder.path_join("source-materials.json")),
		"materials":
		[
			{
				"name": "fixture",
				"native_material": native,
				"average_basis": "vtex-reflectivity-candidate",
				"reflectivity_rgba": [0.5, 0.5, 0.5, 1]
			}
		]
	}
	var profile_path := _folder.path_join("character-inputs.json")
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(profile))
	file.close()
	var composite := Composite.new()
	var options := {
		"purpose": "diagnostic",
		"accept_average_candidate": true,
		"fog_input_kind": "diagnostic-constant",
		"strength": 0.8,
		"fog_modification": 1.0
	}
	assert(not composite.configure(adapter, profile_path))
	assert(composite.configure(adapter, profile_path, options))
	assert(composite.attach(root) == 1)
	assert(composite.attach(root) == 0)
	assert(mesh.get_active_material(0) == original and original.next_pass == null)
	var proxy := mesh.get_node("PostlitSurface0") as MeshInstance3D
	var overlay := proxy.material_override as ShaderMaterial
	assert(is_equal_approx(overlay.get_shader_parameter("source_exposure"), 0.2))
	original.set_shader_parameter("eye_left_center", Vector3(1, 2, 3))
	assert(mesh.get_active_material(0).get_shader_parameter("eye_left_center") == Vector3(1, 2, 3))
	var foreign := StandardMaterial3D.new()
	mesh.material_overlay = foreign
	composite.detach()
	assert(mesh.material_overlay == foreign)
	mesh.material_overlay = null
	var rejected := options.duplicate()
	rejected.fog_input_kind = "unverified-engine-fog"
	assert(not composite.configure(adapter, profile_path, rejected))
	assert(composite.attach(root) == 0)
	assert(composite.configure(adapter, profile_path, options))
	var morph_mesh := ArrayMesh.new()
	morph_mesh.add_blend_shape("body")
	var base_arrays := []
	base_arrays.resize(Mesh.ARRAY_MAX)
	base_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var shape_arrays := []
	shape_arrays.resize(Mesh.ARRAY_MAX)
	shape_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3.RIGHT, Vector3.RIGHT * 2, Vector3.ONE]
	)
	morph_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base_arrays, [shape_arrays])
	morph_mesh.surface_set_material(0, original)
	mesh.mesh = morph_mesh
	mesh.set_blend_shape_value(0, 0.4)
	assert(composite.attach(root) == 1)
	var follower := mesh.get_node("PostlitSurface0") as MeshInstance3D
	assert(is_equal_approx(follower.get_blend_shape_value(0), 0.4))
	mesh.set_blend_shape_value(0, 0.8)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(is_equal_approx(follower.get_blend_shape_value(0), 0.8))
	composite.detach()
	return true
