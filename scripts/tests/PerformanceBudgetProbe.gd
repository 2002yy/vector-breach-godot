extends Node3D

const GRAYBOX_LEVEL_SCENE = preload("res://scenes/level/GrayboxLevel.tscn")
const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 180
const HARD_MIN_AVERAGE_FPS := 15.0
const HARD_MAX_AVERAGE_FRAME_MS := 66.67
const HARD_MAX_P95_FRAME_MS := 100.0
const HARD_MAX_OBJECTS := 5000
const HARD_MAX_PRIMITIVES := 5_000_000
const HARD_MAX_DRAW_CALLS := 5000
const HARD_MAX_VIDEO_MEMORY := 2 * 1024 * 1024 * 1024

func _ready() -> void:
	_build_environment()
	var level: Node3D = GRAYBOX_LEVEL_SCENE.instantiate()
	level.set("level_id", "foundry-reforged")
	add_child(level)
	_build_camera()
	for _frame in range(WARMUP_FRAMES):
		await get_tree().process_frame
	var frame_times_ms: Array[float] = []
	var previous_tick := Time.get_ticks_usec()
	for _frame in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var tick := Time.get_ticks_usec()
		frame_times_ms.append(float(tick - previous_tick) / 1000.0)
		previous_tick = tick
	await RenderingServer.frame_post_draw

	var average_ms := _average(frame_times_ms)
	var p95_ms := _percentile(frame_times_ms, 0.95)
	var metrics := {
		"averageFps": 1000.0 / average_ms if average_ms > 0.0 else 0.0,
		"averageFrameMs": average_ms,
		"p95FrameMs": p95_ms,
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"drawCalls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"textureMemoryBytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"bufferMemoryBytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"videoMemoryBytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"nodeCount": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resourceCount": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	}
	var warnings := _trend_warnings(metrics)
	var failures := _hard_failures(metrics)
	var screenshot_path := ProjectSettings.globalize_path("user://performance-budget-foundry.png")
	var screenshot_error := get_viewport().get_texture().get_image().save_png(screenshot_path)
	if screenshot_error != OK:
		failures.append("screenshot save failed: %d" % screenshot_error)
	var report := {
		"schemaVersion": 1,
		"capturedAtUnix": Time.get_unix_time_from_system(),
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"warmupFrames": WARMUP_FRAMES,
		"sampleFrames": SAMPLE_FRAMES,
		"metrics": metrics,
		"warnings": warnings,
		"hardFailures": failures,
		"screenshot": screenshot_path
	}
	var report_path := ProjectSettings.globalize_path("user://performance-budget-foundry.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		failures.append("report open failed")
	else:
		report_file.store_string(JSON.stringify(report, "  "))
		report_file.close()
	print("PERFORMANCE_BUDGET_PROBE=" + JSON.stringify({
		"report": report_path,
		"screenshot": screenshot_path,
		"metrics": metrics,
		"warnings": warnings,
		"hardFailures": failures
	}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.085, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.64, 0.7)
	environment.ambient_light_energy = 0.66
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.84, 0.68)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(-17.0, 5.5, -34.0)
	camera.look_at_from_position(camera.position, Vector3(-7.0, 2.0, -18.0), Vector3.UP)
	camera.fov = 72.0
	camera.current = true
	add_child(camera)

func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size()) if not values.is_empty() else 0.0

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var index := clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]

func _trend_warnings(metrics: Dictionary) -> PackedStringArray:
	var warnings := PackedStringArray()
	if float(metrics.averageFps) < 45.0:
		warnings.append("average FPS below 45")
	if float(metrics.averageFrameMs) > 22.23:
		warnings.append("average frame time above 22.23 ms")
	if float(metrics.p95FrameMs) > 33.34:
		warnings.append("p95 frame time above 33.34 ms")
	if int(metrics.objects) > 2500:
		warnings.append("visible objects above 2500")
	if int(metrics.primitives) > 2_500_000:
		warnings.append("primitives above 2500000")
	if int(metrics.drawCalls) > 2500:
		warnings.append("draw calls above 2500")
	if int(metrics.videoMemoryBytes) > 1024 * 1024 * 1024:
		warnings.append("video memory above 1 GiB")
	return warnings

func _hard_failures(metrics: Dictionary) -> PackedStringArray:
	var failures := PackedStringArray()
	if float(metrics.averageFps) < HARD_MIN_AVERAGE_FPS:
		failures.append("average FPS below hard minimum")
	if float(metrics.averageFrameMs) > HARD_MAX_AVERAGE_FRAME_MS:
		failures.append("average frame time above hard maximum")
	if float(metrics.p95FrameMs) > HARD_MAX_P95_FRAME_MS:
		failures.append("p95 frame time above hard maximum")
	if int(metrics.objects) > HARD_MAX_OBJECTS:
		failures.append("visible objects above hard maximum")
	if int(metrics.primitives) > HARD_MAX_PRIMITIVES:
		failures.append("primitives above hard maximum")
	if int(metrics.drawCalls) > HARD_MAX_DRAW_CALLS:
		failures.append("draw calls above hard maximum")
	if int(metrics.videoMemoryBytes) > HARD_MAX_VIDEO_MEMORY:
		failures.append("video memory above hard maximum")
	return failures
