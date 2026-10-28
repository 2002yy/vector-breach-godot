extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var radar = load("res://scripts/ui/RadarDisplay.gd").new()
	root.add_child(radar)
	assert(not radar.is_processing())
	radar.prepare_level("inferno-classic-local", "load-1")
	var atlas = radar.get("_atlas")
	var first: int = atlas.generation
	assert(atlas.status == "verifying_source")
	radar.set_snapshot({"level_id": "mirage-classic-local", "radar_load_identity": "old"})
	assert(atlas.generation == first and radar.is_processing())
	radar.cancel_preparation()
	assert(atlas.generation > first and atlas.status == "no_local_atlas")
	assert(not radar.is_processing())
	radar.prepare_level("mirage-classic-local", "load-2")
	var deadline := Time.get_ticks_msec() + 30000
	while atlas.status == "verifying_source":
		assert(Time.get_ticks_msec() < deadline)
		await process_frame
	assert(atlas.status == "ready" and not radar.is_processing())
	var prepared: int = atlas.generation
	radar.set_snapshot({"level_id": "inferno-classic-local", "radar_load_identity": "old"})
	assert(atlas.generation == prepared and atlas.status == "ready")
	radar.set_snapshot({"level_id": "mirage-classic-local", "radar_load_identity": "old"})
	assert(atlas.generation == prepared and radar.get("_preparing_identity") == "load-2")
	radar.set_snapshot({"level_id": "inferno-classic-local", "radar_load_identity": "load-2"})
	assert(atlas.generation == prepared and radar.get("_preparing_identity") == "load-2")
	radar.set_snapshot({"level_id": "mirage-classic-local", "radar_load_identity": "load-2"})
	assert(atlas.generation == prepared)
	assert(radar.get("_preparing_identity") == "")
	radar.prepare_level("mirage-classic-local", "load-3")
	assert(atlas.generation > prepared)
	radar.cancel_preparation()
	radar.queue_free()
	await process_frame
	print("RADAR_PREWARM_OK lifecycle=cancel_replace_snapshot_reload")
	quit()
