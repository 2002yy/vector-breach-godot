extends Node

const Reflection = preload("res://scripts/level/SourceReflectionTexture.gd")


func _ready() -> void:
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
