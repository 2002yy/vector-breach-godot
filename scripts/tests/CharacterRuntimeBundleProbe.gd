extends "res://scripts/tests/CharacterBodyProbe.gd"

const RuntimeInputs = preload("res://scripts/characters/SourceCharacterRuntimeInputs.gd")
var _runtime := RuntimeInputs.new()
var _attempt_finished := false
var _attempt_result := true


func _surfaces(_adapter: RefCounted, alignment: Transform3D, cases: Array, out: String) -> void:
	add_child(_runtime)
	var args := OS.get_cmdline_user_args()
	var path: String = args[args.find("--runtime-bundle") + 1]
	var level: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + _normalization.level + ".json")
	)
	var visual: Node
	for child in get_children():
		if child.has_method("get_current_level_data"):
			visual = child.get_node("VisualRoot/LevelVisual")
	assert(visual != null)
	assert(not await _runtime.configure(path, level, visual))
	assert(await _runtime.configure(path, level, visual, true))
	assert(_runtime.configured and _runtime.level_id == level.id)
	_inputs = _runtime.inputs
	_indirect = _runtime.indirect
	await super._surfaces(_runtime.reflection, alignment, cases, out)
	var model := Appearance.instantiate("t-blackwolf")
	add_child(model)
	var point: Array = cases[0].position
	model.position = alignment * Vector3(point[0], point[1], point[2] - 64)
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			model.position + Vector3.UP * 2, model.position + Vector3.DOWN * 5
		)
	)
	assert(not hit.is_empty())
	model.position = hit.position + Vector3.UP * 0.02
	var camera := get_viewport().get_camera_3d()
	camera.position = model.position + Vector3(0, 1.65, -1.8)
	camera.look_at(model.position + Vector3.UP * 1.65)
	model.look_at(Vector3(camera.position.x, model.position.y, camera.position.z))
	var baseline := await _capture(out, "bundle-baseline")
	assert(_runtime.attach_character(model) != null)
	var bound := await _capture(out, "bundle-attached")
	assert(_difference(baseline, bound) > 0.000001)
	var bad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	bad.files[0].sha256 = "0".repeat(64)
	var bad_path := path.get_base_dir().path_join("tampered.json")
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string(JSON.stringify(bad))
	bad_file.close()
	assert(not await _runtime.configure(bad_path, level, visual, true))
	var bad_restored := await _capture(out, "bundle-bad-hash-restored")
	assert(_difference(baseline, bad_restored) == 0.0 and not _runtime.configured)
	assert(await _runtime.configure(path, level, visual, true))
	assert(_runtime.attach_character(model) != null)
	var wrong := level.duplicate(true)
	wrong.id = "wrong-map"
	assert(not await _runtime.configure(path, wrong, visual, true))
	var restored := await _capture(out, "bundle-wrong-map-restored")
	assert(_difference(baseline, restored) == 0.0 and not _runtime.configured)
	# Cancel an upload, then configure again before that older completion returns.
	_attempt(path, level, visual)
	assert(not _runtime._pending.is_empty(), "cancellation must exercise an actual pending upload")
	_runtime.clear()
	assert(await _runtime.configure(path, level, visual, true))
	for frame in range(30):
		if _attempt_finished:
			break
		await get_tree().process_frame
	assert(_attempt_finished and not _attempt_result and _runtime.configured)
	# Removing a still-alive visual during upload must also prevent publication.
	_attempt_finished = false
	_attempt(path, level, visual)
	assert(not _runtime._pending.is_empty())
	var visual_parent := visual.get_parent()
	visual_parent.remove_child(visual)
	for frame in range(30):
		if _attempt_finished:
			break
		await get_tree().process_frame
	assert(_attempt_finished and not _attempt_result and not _runtime.configured)
	visual_parent.add_child(visual)
	assert(await _runtime.configure(path, level, visual, true))
	assert(_runtime.attach_character(model) != null)
	_runtime.queue_free()
	await get_tree().process_frame
	var exited := await _capture(out, "bundle-owner-exit-restored")
	assert(_difference(baseline, exited) == 0.0)
	model.queue_free()
	var receipt := FileAccess.open(out.path_join("bundle-lifecycle.json"), FileAccess.WRITE)
	receipt.store_string(
		JSON.stringify(
			{
				"wrong_map_error": 0,
				"bad_hash_error": 0,
				"exit_error": 0,
				"older_upload_canceled": true,
				"removed_visual_rejected": true
			}
		)
	)
	print("CHARACTER_RUNTIME_BUNDLE_OK")


func _surface_probes(_path: String, _level: Dictionary, _alignment: Transform3D) -> RefCounted:
	assert(_runtime.configured)
	return _runtime.probes


func _configure_candidate(composite: RefCounted) -> void:
	super._configure_candidate(composite)
	_runtime.track(composite)


func _attempt(path: String, level: Dictionary, visual: Node) -> void:
	_attempt_result = await _runtime.configure(path, level, visual, true)
	_attempt_finished = true
