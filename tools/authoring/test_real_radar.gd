extends SceneTree

const Atlas = preload("res://scripts/ui/RadarAtlas.gd")
var checks := 0


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
			var selected: Dictionary = atlas.select_layer(float(layer.height))
			_check(not selected.is_empty())
			_check(is_equal_approx(float(selected.height), float(layer.height)))
			_check(atlas.textures.size() <= 2)
		atlas.textures.clear()
		atlas.manifest.layers[0].sha256 = "0".repeat(64)
		_check(atlas.select_layer(float(atlas.manifest.layers[0].height)).is_empty())
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
	print("REAL_RADAR_CONTRACT_OK checks=", checks)
	quit(0)
