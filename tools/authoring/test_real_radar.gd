extends SceneTree

const Atlas = preload("res://scripts/ui/RadarAtlas.gd")
var checks := 0
var timings: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool) -> void:
	checks += 1
	if not value:
		push_error("REAL_RADAR_CONTRACT_FAILED check=%s" % checks)
		quit(1)
		assert(value)


func _run() -> void:
	var data := {
		"schema": 1,
		"level": "synthetic",
		"world_rect": [-10, 20, 80, 40],
		"layers":
		[
			{"height": 0.0, "texture": "layer.png", "sha256": "a".repeat(64)},
			{"height": 4.0, "texture": "upper.png", "sha256": "b".repeat(64)}
		]
	}
	for key in ["source_sha256", "source_import_sha256", "level_sha256"]:
		data[key] = "a".repeat(64)
	_check(Atlas.valid_manifest(data, "synthetic"))
	_check(Atlas.import_identity_matches(data, "a".repeat(64)))
	_check(not Atlas.import_identity_matches(data, "b".repeat(64)))
	var missing_import := data.duplicate(true)
	missing_import.erase("source_import_sha256")
	_check(not Atlas.valid_manifest(missing_import, "synthetic"))
	_check(not Atlas.import_identity_matches(missing_import, "a".repeat(64)))
	_check(not Atlas.valid_manifest(data, "other"))
	_check(Atlas.world_uv(Vector2(30, 30), data.world_rect).is_equal_approx(Vector2(0.5, 0.25)))
	_check(Atlas.nearest_layer(data.layers, 0.0) == 0)
	_check(Atlas.nearest_layer(data.layers, 4.0) == 1)
	_check(Atlas.nearest_layer(data.layers, 2.1, 0) == 0)
	_check(Atlas.nearest_layer(data.layers, 2.4, 0) == 1)
	_check(Atlas.nearest_layer(data.layers, 20.0) == -1)
	_check(Atlas.floor_sample(0.0, 1.5, false, false) == 0.0)
	_check(Atlas.floor_sample(0.0, 4.0, true, false) == 4.0)
	_check(Atlas.floor_sample(0.0, 8.0, false, true) == 8.0)
	var bad := data.duplicate(true)
	bad.layers[0].texture = "../outside.png"
	_check(not Atlas.valid_manifest(bad, "synthetic"))
	bad = data.duplicate(true)
	bad.world_rect[2] = 0
	_check(not Atlas.valid_manifest(bad, "synthetic"))
	var radar = load("res://scripts/ui/RadarDisplay.gd").new()
	radar.set_snapshot(
		{
			"level_id": "unknown-map",
			"radar_load_identity": "1",
			"feet_height": 2.0,
			"grounded": true
		}
	)
	radar.set_snapshot(
		{
			"level_id": "unknown-map",
			"radar_load_identity": "1",
			"feet_height": 8.0,
			"grounded": false
		}
	)
	_check(radar.get_debug_snapshot().atlas_floor_height == 2.0)
	radar.set_snapshot(
		{
			"level_id": "unknown-map",
			"radar_load_identity": "2",
			"feet_height": 8.0,
			"grounded": false
		}
	)
	_check(radar.get_debug_snapshot().atlas_floor_height == 8.0)
	radar.free()
	var absent = Atlas.new()
	_check(not absent.load_level("unknown-map"))
	_check(absent.select_layer(0.0).is_empty())
	for level_id in Atlas.LEVELS:
		var atlas = Atlas.new()
		atlas.load_level(level_id)
		for frame in range(1000):
			if atlas.status != "verifying_source":
				break
			await create_timer(0.01).timeout
			atlas.load_level(level_id)
		_check(atlas.status == "ready")
		for anchor in atlas.manifest.calibration:
			var point := Vector2(float(anchor.world_xz[0]), float(anchor.world_xz[1]))
			var uv := Atlas.world_uv(point, atlas.manifest.world_rect)
			_check(uv.is_equal_approx(Vector2(float(anchor.uv[0]), float(anchor.uv[1]))))
		for layer in atlas.manifest.layers:
			var started := Time.get_ticks_usec()
			var selected: Dictionary = atlas.select_layer(float(layer.height))
			_check(selected.is_empty())
			var cold_us := Time.get_ticks_usec() - started
			var poll_us := 0
			for frame in range(1000):
				await create_timer(0.001).timeout
				started = Time.get_ticks_usec()
				selected = atlas.select_layer(float(layer.height))
				poll_us = maxi(poll_us, Time.get_ticks_usec() - started)
				if not selected.is_empty():
					break
			started = Time.get_ticks_usec()
			atlas.select_layer(float(layer.height))
			timings.append(
				{
					"level": level_id,
					"height": layer.height,
					"request_us": cold_us,
					"poll_upload_max_us": poll_us,
					"cached_us": Time.get_ticks_usec() - started
				}
			)
			_check(not selected.is_empty())
			_check(is_equal_approx(float(selected.height), float(layer.height)))
			_check(atlas.textures.size() <= 2)
		# An uncached request superseded by another slice must never publish its image.
		atlas.textures.clear()
		atlas.select_layer(float(atlas.manifest.layers[0].height))
		atlas.select_layer(float(atlas.manifest.layers[1].height))
		var final_slice: Dictionary = {}
		for frame in range(1000):
			await create_timer(0.001).timeout
			final_slice = atlas.select_layer(float(atlas.manifest.layers[1].height))
			if not final_slice.is_empty():
				break
		_check(not final_slice.is_empty() and int(final_slice.layer_index) == 1)
		_check(not atlas.textures.has(0))
		# Reload while a decode is pending; no old generation texture can survive.
		atlas.textures.clear()
		atlas.select_layer(float(atlas.manifest.layers[0].height))
		var old_generation: int = atlas.generation
		atlas.load_level(level_id, "reload-1")
		_check(atlas.generation == old_generation + 1)
		_check(atlas.textures.is_empty() and atlas.active_layer == -1)
		atlas.load_level(level_id, "reload-2")
		_check(atlas.generation == old_generation + 2)
		for frame in range(1000):
			if atlas.status != "verifying_source":
				break
			await create_timer(0.01).timeout
			atlas.load_level(level_id, "reload-2")
		_check(atlas.status == "ready")
		_check(atlas.generation == old_generation + 2)
		_check(atlas.textures.is_empty())
		var reloaded_slice: Dictionary = {}
		for frame in range(1000):
			await create_timer(0.001).timeout
			reloaded_slice = atlas.select_layer(float(atlas.manifest.layers[1].height))
			if not reloaded_slice.is_empty():
				break
		_check(not reloaded_slice.is_empty() and not atlas.textures.has(0))
		atlas.textures.clear()
		atlas.manifest.layers[0].sha256 = "0".repeat(64)
		_check(atlas.select_layer(float(atlas.manifest.layers[0].height)).is_empty())
		for frame in range(1000):
			await create_timer(0.001).timeout
			atlas.select_layer(float(atlas.manifest.layers[0].height))
			if atlas.status != "ready":
				break
		_check(atlas.status == "texture_identity_mismatch")
	var drift = Atlas.new()
	drift.load_level(Atlas.LEVELS[0])
	drift.manifest.source_sha256 = "0".repeat(64)
	for frame in range(1000):
		if drift.status != "verifying_source":
			break
		await create_timer(0.01).timeout
		drift.load_level(Atlas.LEVELS[0])
	_check(drift.status == "source_identity_mismatch")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var report := FileAccess.open(args[0], FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks": checks, "timings": timings}, "  "))
	print("REAL_RADAR_CONTRACT_OK checks=", checks)
	quit(0)
