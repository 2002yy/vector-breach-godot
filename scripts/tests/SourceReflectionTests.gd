extends Node

const Reflection = preload("res://scripts/level/SourceReflectionTexture.gd")
const Adapter = preload("res://scripts/level/SourceReflectionDiagnostic.gd")


func _ready() -> void:
	_records()
	var payload := PackedByteArray()
	payload.resize(96)
	var data := {
		"schema": 1,
		"contract": "source-reflection-blocks-v1",
		"format": "BC6H-UFLOAT",
		"layout": "mip-ascending/cube/face/BC6H-blocks",
		"width": 4,
		"cubes": 1,
		"mip_count": 1,
		"face_order": ["+X", "-X", "+Y", "-Y", "+Z", "-Z"],
		"mips":
		[
			{
				"level": 0,
				"size": 4,
				"offset": 0,
				"face_bytes": 16,
				"bytes": 96,
				"sha256": Reflection._sha(payload)
			}
		]
	}
	assert(Reflection.validate(data, payload))
	for change in [
		{"cubes": 0},
		{"cubes": 129},
		{"cubes": 1.5},
		{"width": 3},
		{"width": NAN},
		{"mip_count": 4},
		{"mips": []},
		{"format": "RGBA8"},
		{"layout": "LPV"},
		{"face_order": ["+Z", "-Z", "+Y", "-Y", "+X", "-X"]}
	]:
		var invalid := data.duplicate(true)
		invalid.merge(change, true)
		assert(not Reflection.validate(invalid, payload), str(change))
	for field in ["offset", "face_bytes", "bytes", "level", "sha256"]:
		var invalid := data.duplicate(true)
		invalid.mips[0][field] = "invalid"
		assert(not Reflection.validate(invalid, payload), field)
	assert(not Reflection.validate(data, payload.slice(1)))
	var changed := payload.duplicate()
	changed[0] = 1
	assert(not Reflection.validate(data, changed))
	changed = payload.duplicate()
	changed.append(0)
	assert(not Reflection.validate(data, changed))
	var source := Reflection.new()
	assert(not await source.create(data, payload), "headless cannot allocate reflection textures")
	source.release()
	print("[SourceReflectionTests] PASS (1 tests)")
	get_tree().quit()


func _records() -> void:
	var probe := {
		"enabled": true,
		"sample_supported": true,
		"texture": "lpv",
		"priority": 1,
		"yaw_degrees": 0,
		"origin": [0, 0, 0],
		"bounds_min": [-1, -1, -1],
		"bounds_size": [2, 2, 2],
		"edge_fade": [0, 0, 0],
		"atlas_size": [1, 1, 1],
		"atlas_offset": [0, 0, 0],
		"cube_index": 1,
		"native": {"classname": "env_combined_light_probe_volume"}
	}
	var first := probe.duplicate(true)
	first.cube_index = 0
	var data := {
		"level": "map",
		"source_trace": {"vpkSha256": "a".repeat(64)},
		"probes": [probe, first],
		"cubes": 2
	}
	var level := {"id": "map", "sourceTrace": data.source_trace}
	var alignment := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0254), Vector3.ZERO)
	assert(Adapter.records(data, level, alignment)[0].cube_index == 0)
	assert(Adapter.records(data, {}, alignment).is_empty())
	assert(Adapter.records(data, level, Transform3D.IDENTITY).is_empty())
	for change in [
		{"cube_index": 1.5},
		{"cube_index": 2},
		{"sample_supported": false},
		{"bounds_size": [0, 1, 1]},
		{"edge_fade": [-1, 0, 0]},
		{"native": {}}
	]:
		var invalid := data.duplicate(true)
		invalid.probes[0].merge(change, true)
		assert(Adapter.records(invalid, level, alignment).is_empty())
	var duplicate := data.duplicate(true)
	duplicate.probes[0].cube_index = 0
	assert(Adapter.records(duplicate, level, alignment).is_empty())
