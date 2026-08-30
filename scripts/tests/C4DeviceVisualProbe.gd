extends Node

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "gatehouse"
const PERF_WARMUP_FRAMES := 15
const PERF_SAMPLE_FRAMES := 60
const EVIDENCE_PATH := "res://reports/step16-c4-evidence.json"

func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Node3D
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame

	var target_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if target_index < 0:
		_fail("C4 visual probe could not find Gatehouse")
		return
	main.call("_on_map_selected", target_index)
	main.call("_on_start_pressed")
	for _frame in range(12):
		await get_tree().physics_frame

	var player := main.get_node("Player") as CharacterBody3D
	var c4 := main.get_node("C4Device") as Node3D
	var weapon_view_model := main.get_node_or_null("Player/CameraPivot/Camera3D/WeaponViewModel") as Node3D
	if player == null or c4 == null:
		_fail("C4 visual probe could not resolve gameplay player/C4 nodes")
		return

	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	if weapon_view_model != null:
		weapon_view_model.visible = false

	var forward := -player.global_transform.basis.z.normalized()
	var anchor := player.global_position - Vector3.UP * 0.82 + forward * 1.45
	var camera_position := player.global_position

	RoundManager.start_round()
	RoundManager.set_live()
	c4.call("set_carried", "T")
	var hidden_baseline := await _sample_frame_timing()

	c4.call("drop_at", anchor)
	var dropped_perf := await _sample_frame_timing()
	var dropped := await _capture_view(player, "dropped", camera_position, anchor + Vector3.UP * 0.09)

	RoundManager.start_round()
	RoundManager.set_live()
	c4.call("plant_at", anchor, "A")
	if not RoundManager.plant_bomb("A"):
		_fail("C4 visual probe could not enter real BOMB_PLANTED state")
		return
	c4.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var planted_light := (c4.get_node("MeshRoot/StatusLight") as OmniLight3D).light_energy
	var planted := await _capture_view(player, "planted", camera_position, anchor + Vector3.UP * 0.09)
	var planted_calm_perf := await _sample_frame_timing()

	RoundManager.time_remaining = 8.0
	c4.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var planted_urgent_perf := await _sample_frame_timing()

	RoundManager.time_remaining = 4.0
	c4.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var urgent_light := (c4.get_node("MeshRoot/StatusLight") as OmniLight3D).light_energy
	var urgent_pitch := (c4.get_node("BeepPlayer") as AudioStreamPlayer3D).pitch_scale
	var urgent := await _capture_view(player, "urgent", camera_position, anchor + Vector3.UP * 0.09)

	var images := {
		"dropped": dropped,
		"planted": planted,
		"urgent": urgent,
	}
	var images_saved := true
	for image_variant in images.values():
		images_saved = images_saved and not String(image_variant).is_empty()

	var performance := {
		"hidden_baseline": hidden_baseline,
		"dropped": dropped_perf,
		"planted_calm": planted_calm_perf,
		"planted_urgent": planted_urgent_perf,
		"comparisons_vs_hidden_baseline": {
			"dropped": _compare_performance(dropped_perf, hidden_baseline),
			"planted_calm": _compare_performance(planted_calm_perf, hidden_baseline),
			"planted_urgent": _compare_performance(planted_urgent_perf, hidden_baseline),
		},
	}
	var snapshot := {
		"schema_version": 1,
		"purpose": "local_forward_plus_visual_performance_evidence",
		"level": TARGET_LEVEL_ID,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"video_adapter_api_version": RenderingServer.get_video_adapter_api_version(),
		"performance_sampling": {
			"warmup_frames": PERF_WARMUP_FRAMES,
			"sample_frames": PERF_SAMPLE_FRAMES,
			"measurement": "wall_clock_time_between_process_frames",
			"acceptance_note": "telemetry_only_no_hard_gpu_threshold",
		},
		"performance": performance,
		"images": images,
		"c4_state": String(c4.get("device_state")),
		"site": String(c4.get("site_label")),
		"planted_light_energy": planted_light,
		"urgent_light_energy": urgent_light,
		"urgent_pitch_scale": urgent_pitch,
		"time_remaining": RoundManager.time_remaining,
	}
	var evidence_saved := _write_evidence(snapshot)
	print("C4_VISUAL_PROBE=" + JSON.stringify(snapshot))
	print("C4_VISUAL_PROBE_EVIDENCE=" + ProjectSettings.globalize_path(EVIDENCE_PATH) if evidence_saved else "C4_VISUAL_PROBE_EVIDENCE=")
	get_tree().quit(0 if images_saved and evidence_saved else 1)

func _sample_frame_timing() -> Dictionary:
	for _frame in range(PERF_WARMUP_FRAMES):
		await get_tree().process_frame
	var samples: Array[float] = []
	var previous_usec := Time.get_ticks_usec()
	for _frame in range(PERF_SAMPLE_FRAMES):
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		samples.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
	if samples.is_empty():
		return {}
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var total_ms := 0.0
	for frame_ms in samples:
		total_ms += frame_ms
	var average_ms := total_ms / float(samples.size())
	var p95_index := clampi(int(ceil(float(sorted_samples.size()) * 0.95)) - 1, 0, sorted_samples.size() - 1)
	return {
		"frames": samples.size(),
		"average_frame_ms": average_ms,
		"p95_frame_ms": float(sorted_samples[p95_index]),
		"average_fps": 1000.0 / maxf(average_ms, 0.001),
		"min_frame_ms": float(sorted_samples[0]),
		"max_frame_ms": float(sorted_samples[sorted_samples.size() - 1]),
	}

func _compare_performance(sample: Dictionary, baseline: Dictionary) -> Dictionary:
	var baseline_average := maxf(float(baseline.get("average_frame_ms", 0.0)), 0.001)
	var baseline_p95 := maxf(float(baseline.get("p95_frame_ms", 0.0)), 0.001)
	var sample_average := float(sample.get("average_frame_ms", 0.0))
	var sample_p95 := float(sample.get("p95_frame_ms", 0.0))
	return {
		"average_frame_ms_delta": sample_average - baseline_average,
		"average_frame_ms_delta_pct": ((sample_average / baseline_average) - 1.0) * 100.0,
		"p95_frame_ms_delta": sample_p95 - baseline_p95,
		"p95_frame_ms_delta_pct": ((sample_p95 / baseline_p95) - 1.0) * 100.0,
	}

func _write_evidence(snapshot: Dictionary) -> bool:
	var reports_dir := ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(reports_dir)
	var output := FileAccess.open(ProjectSettings.globalize_path(EVIDENCE_PATH), FileAccess.WRITE)
	if output == null:
		push_error("C4 visual probe could not open evidence JSON for writing")
		return false
	output.store_string(JSON.stringify(snapshot, "\t"))
	output.close()
	return FileAccess.file_exists(EVIDENCE_PATH)

func _capture_view(
	player: CharacterBody3D,
	label: String,
	position: Vector3,
	target: Vector3
) -> String:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.look_at(target, Vector3.UP)
	var camera_pivot := player.get_node("CameraPivot") as Node3D
	camera_pivot.rotation.x = 0.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var reports_dir := ProjectSettings.globalize_path("res://reports")
	DirAccess.make_dir_recursive_absolute(reports_dir)
	var resource_path := "res://reports/step16-c4-%s.png" % label
	var save_error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(resource_path))
	return resource_path if save_error == OK else ""

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
