extends Node

const Reflection = preload("res://scripts/level/SourceReflectionTexture.gd")
const Adapter = preload("res://scripts/level/SourceReflectionDiagnostic.gd")
const Inputs = preload("res://scripts/characters/SourceEnvironmentInputs.gd")
const Indirect = preload("res://scripts/characters/SourceIndirectInputs.gd")
const Composite = preload("res://scripts/characters/SourceCharacterEnvironment.gd")
const RuntimeInputs = preload("res://scripts/characters/SourceCharacterRuntimeInputs.gd")
const ControlledGame = preload("res://scripts/characters/ControlledGame.gd")


func _catalog_contract() -> void:
	var path := "user://character-catalog-" + str(Time.get_ticks_usec()) + ".json"
	var data := {"contract": "source-character-runtime-bundle-v1", "level": "test-map"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	assert(ControlledGame.bundle_catalog([path]) == {"test-map": path})
	assert(ControlledGame.bundle_catalog([path, path]).is_empty())
	for change in [{"level": []}, {"level": ""}, {"contract": "wrong"}]:
		var bad := data.duplicate()
		bad.merge(change, true)
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(bad))
		file.close()
		assert(ControlledGame.bundle_catalog([path]).is_empty())
	for text in ["{broken", " ".repeat(65537)]:
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		assert(ControlledGame.bundle_catalog([path]).is_empty())
	assert(DirAccess.remove_absolute(path) == OK)
	assert(ControlledGame.bundle_catalog([path]).is_empty())


func _bundle_contract() -> void:
	var files := []
	for path in ["r.json", "l.json", "n.json", "i.json", "blocks.bin", "brdf.bin", "atlas.bin"]:
		files.append({"path": path, "bytes": 1, "sha256": "a".repeat(64)})
	var data := {
		"schema": 1,
		"contract": "source-character-runtime-bundle-v1",
		"purpose": "controlled-candidate",
		"level": "test-map",
		"vpk_sha256": "a".repeat(64),
		"inputs":
		{
			"reflection": "r.json",
			"lighting": "l.json",
			"normalization": "n.json",
			"indirect": "i.json"
		},
		"files": files,
	}
	var level := {"id": "test-map", "sourceTrace": {"vpkSha256": "a".repeat(64)}}
	assert(RuntimeInputs.manifest_paths(data, level).size() == 4)
	for change in [
		{"schema": true},
		{"level": "other"},
		{"purpose": "shipping"},
		{"vpk_sha256": {}},
		{"files": {}},
		{"inputs": []},
	]:
		var bad := data.duplicate(true)
		bad.merge(change, true)
		assert(RuntimeInputs.manifest_paths(bad, level).is_empty())
	for path in ["../outside", "/absolute", "C:/private", "a\\b", "a//b", "./r.json"]:
		assert(not RuntimeInputs.relative(path))
	for value in [0, -1, 0.5, NAN, true, "1"]:
		var bad := data.duplicate(true)
		bad.files[0].bytes = value
		assert(RuntimeInputs.manifest_paths(bad, level).is_empty())
	var duplicate := data.duplicate(true)
	duplicate.files[1].path = "R.JSON"
	assert(RuntimeInputs.manifest_paths(duplicate, level).is_empty())


func _ready() -> void:
	_records()
	_normalization_inputs()
	_indirect_inputs()
	_bundle_contract()
	_catalog_contract()
	_material_toggle()
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


func _material_toggle() -> void:
	for explicit_override in [false, true]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		var original := StandardMaterial3D.new()
		mesh.mesh.material = original
		var previous: Material = original if explicit_override else null
		var copy := ShaderMaterial.new()
		copy.shader = Shader.new()
		copy.shader.code = "shader_type spatial; uniform bool source_env_enabled = true;"
		mesh.set_surface_override_material(0, copy)
		var composite := Composite.new()
		composite.materials.append(copy)
		composite._bindings.append(
			{
				"mesh": mesh,
				"surface": 0,
				"previous": previous,
				"original": original,
				"copy": copy,
				"active": true
			}
		)
		assert(composite.set_enabled(false) == 1)
		assert(copy.get_shader_parameter("source_env_enabled") == false)
		assert(mesh.get_surface_override_material(0) == previous)
		assert(mesh.get_active_material(0) == original)
		assert(composite.set_enabled(false) == 0)
		assert(composite.set_enabled(true) == 1)
		assert(copy.get_shader_parameter("source_env_enabled") == true)
		assert(mesh.get_surface_override_material(0) == copy)
		assert(composite.set_enabled(true) == 0)
		var external := StandardMaterial3D.new()
		mesh.set_surface_override_material(0, external)
		assert(composite.set_enabled(false) == 0)
		mesh.set_surface_override_material(0, copy)
		assert(composite.set_enabled(false) == 1)
		mesh.set_surface_override_material(0, external)
		assert(composite.set_enabled(true) == 0)
		composite.detach()
		assert(mesh.get_surface_override_material(0) == external)
		mesh.free()


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


func _indirect_inputs() -> void:
	var lighting := {"level": "map", "source_trace": {"vpkSha256": "a"}}
	var data := {
		"schema": 1,
		"contract": "source-indirect-diagnostic-v1",
		"kind": "viewer-derived-source-sun-SH1",
		"level": "map",
		"source_trace": lighting.source_trace,
		"lighting_sha256": "b",
		"ambient_sh": [[0, 0, 1, 2], [0, 0, 1, 2], [0, 0, 1, 2]]
	}
	assert(Indirect.valid(data, lighting, "b"))
	for field in ["level", "source_trace", "lighting_sha256", "kind", "contract", "schema"]:
		var bad := data.duplicate(true)
		bad[field] = "wrong"
		assert(not Indirect.valid(bad, lighting, "b"))
	for value in [NAN, INF, "1"]:
		var bad := data.duplicate(true)
		bad.ambient_sh[0][0] = value
		assert(not Indirect.valid(bad, lighting, "b"))
	var inputs := Indirect.new()
	assert(not inputs.configure("res://missing-indirect.json", "res://missing-lighting.json"))
	assert(not inputs.bind(ShaderMaterial.new()))


func _normalization_inputs() -> void:
	var raw := PackedByteArray()
	raw.resize(64 * 64 * 3 * 16)
	var reflection := {
		"level": "map",
		"source_trace": {"vpkSha256": "a".repeat(64)},
		"sha256": "b".repeat(64),
		"compiled_sha256": "c".repeat(64),
		"cubes": 1,
		"mip_count": 7
	}
	var coefficients := []
	coefficients.resize(27)
	coefficients.fill(0.0)
	var data := {
		"schema": 1,
		"contract": "source-reflection-normalization-v1",
		"level": "map",
		"source_trace": reflection.source_trace,
		"reflection_sha256": reflection.sha256,
		"compiled_reflection_sha256": reflection.compiled_sha256,
		"normalization_sh": [[0, 0, 0, 0]],
		"native_sh":
		{
			"compiled_sha256": reflection.compiled_sha256,
			"cubes": 1,
			"native_coefficients": coefficients
		},
		"brdf":
		{
			"file": "brdf-rgba-f32.bin",
			"compiled_sha256": Inputs.BRDF_SHA,
			"sha256": Reflection._sha(raw)
		}
	}
	assert(Inputs.validate(data, reflection, raw))
	for field in ["reflection_sha256", "compiled_reflection_sha256", "contract"]:
		var invalid := data.duplicate(true)
		invalid[field] = "invalid"
		assert(not Inputs.validate(invalid, reflection, raw))
	var changed := data.duplicate(true)
	changed.normalization_sh[0][0] = 1
	assert(not Inputs.validate(changed, reflection, raw))
	changed = data.duplicate(true)
	changed.native_sh.native_coefficients[0] = NAN
	assert(not Inputs.validate(changed, reflection, raw))
	assert(not Inputs.validate(data, reflection, raw.slice(1)))
