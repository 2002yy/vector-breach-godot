extends Node3D

const Adapter = preload("res://scripts/level/SourceProbeDiagnostic.gd")
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
	mesh.mesh = BoxMesh.new()
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
	adapter.detach()
	visual.queue_free()
	for name in ["lighting.json", "volume.bin"]:
		DirAccess.remove_absolute(_folder.path_join(name))
	DirAccess.remove_absolute(_folder)
	print("SOURCE_PROBE_ADAPTER_TESTS_OK boundaries=11")
	print("[SourceProbeDiagnosticTests] PASS (1 tests)")
	get_tree().quit()


func _save(data: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
