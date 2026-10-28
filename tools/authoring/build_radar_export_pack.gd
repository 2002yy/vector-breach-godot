extends SceneTree
const LEVELS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	if args[0].begins_with("build"):
		assert(not FileAccess.file_exists(args[1]))
		var pack := PCKPacker.new()
		assert(pack.pck_start(args[1]) == OK)
		for level in LEVELS:
			var directory: String = "res://assets/local_reference/radar/" + level + "/v4/"
			var atlas_path := directory + "atlas.json"
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
			var source: String = data.source
			assert(FileAccess.get_sha256(source) == data.source_sha256)
			assert(FileAccess.get_sha256(source + ".import") == data.source_import_sha256)
			var level_path: String = "res://data/levels/" + level + ".json"
			assert(FileAccess.get_sha256(level_path) == data.level_sha256)
			var config := ConfigFile.new()
			assert(config.load(source + ".import") == OK)
			var compiled := String(config.get_value("remap", "path"))
			var receipt := {
				"schema": 1,
				"compiled": compiled,
				"compiled_sha256": FileAccess.get_sha256(compiled),
				"atlas_sha256": FileAccess.get_sha256(atlas_path),
				"shipped_import_sha256": FileAccess.get_sha256(source + ".import")
			}
			for key in ["source", "source_sha256", "source_import_sha256", "level_sha256"]:
				receipt[key] = data[key]
			if args[0] == "build_stale":
				receipt.compiled_sha256 = "a".repeat(64)
			var temporary: String = "user://radar-receipt-" + level + ".json"
			var output := FileAccess.open(temporary, FileAccess.WRITE)
			output.store_string(JSON.stringify(receipt))
			output.close()
			if args[0] != "build_no_receipt":
				assert(pack.add_file(directory + "export_identity.json", temporary) == OK)
			var files := [atlas_path, level_path, source + ".import"]
			if args[0] != "build_missing":
				files.append(compiled)
			for layer in data.layers:
				files.append(directory + String(layer.texture))
			for path in files:
				assert(pack.add_file(path, path) == OK)
		assert(pack.flush() == OK)
		print("RADAR_EXPORT_PACK_BUILT")
	else:
		assert(ProjectSettings.load_resource_pack(args[1], true))
		var script = load("res://RadarAtlas.gd")
		var count := 0
		for level in LEVELS:
			var atlas = script.new()
			var deadline := Time.get_ticks_msec() + 30000
			while not atlas.load_level(level) and atlas.status == "verifying_source":
				assert(Time.get_ticks_msec() < deadline)
				await process_frame
			if args[0] != "check":
				assert(atlas.status == "source_identity_mismatch")
				print("RADAR_EXPORT_NEGATIVE_OK ", args[0])
				quit()
				return
			assert(atlas.status == "ready", atlas.status)
			assert(not FileAccess.file_exists(String(atlas.manifest.source)))
			for layer in atlas.manifest.layers:
				var result: Dictionary = {}
				while result.is_empty():
					result = atlas.select_layer(float(layer.height))
					assert(Time.get_ticks_msec() < deadline, atlas.status)
					await process_frame
				count += 1
			atlas = null
		print("RADAR_EXPORT_READY maps=3 slices=", count)
	quit()
