extends SceneTree
## Build data-only radar identities against the actual exported .import bytes.

const LEVELS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 3)
	var before := {}
	for level in LEVELS:
		var path: String = (
			"res://assets/local_reference/radar/" + level + "/v4/export_identity.json"
		)
		before[level] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		assert(String(before[level]).is_empty(), "Main pack already owns radar identity")
	assert(ProjectSettings.load_resource_pack(args[1], false))
	if args[0] == "check":
		_check.call_deferred()
		return
	var rows := []
	var pack := PCKPacker.new()
	if args[0] == "build":
		assert(not FileAccess.file_exists(args[2]))
		assert(pack.pck_start(args[2]) == OK)
	for level in LEVELS:
		var directory: String = "res://assets/local_reference/radar/" + level + "/v4/"
		var atlas_path: String = directory + "atlas.json"
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
		assert(not FileAccess.file_exists(String(data.source)))
		var config := ConfigFile.new()
		assert(config.load(String(data.source) + ".import") == OK)
		var compiled := String(config.get_value("remap", "path"))
		var receipt := {
			"schema": 1,
			"compiled": compiled,
			"compiled_sha256": FileAccess.get_sha256(compiled),
			"atlas_sha256": FileAccess.get_sha256(atlas_path),
			"shipped_import_sha256": FileAccess.get_sha256(String(data.source) + ".import")
		}
		for key in ["source", "source_sha256", "source_import_sha256", "level_sha256"]:
			receipt[key] = data[key]
		var identity_path: String = directory + "export_identity.json"
		rows.append(
			{
				"level": level,
				"main_identity_sha256": before[level],
				"mounted_identity_sha256": FileAccess.get_sha256(identity_path),
				"receipt": receipt
			}
		)
		if args[0] == "build":
			var level_path: String = "res://data/levels/" + level + ".json"
			var level_data: Dictionary = JSON.parse_string(
				FileAccess.get_file_as_string(level_path)
			)
			var manifest_path: String = level_data.get(
				"match_manifest", "res://data/levels/match-local/dustline.json"
			)
			var layout_path := manifest_path + ".export.json"
			var layout_raw := FileAccess.get_file_as_bytes(layout_path)
			assert(not layout_raw.is_empty())
			var layout: Dictionary = JSON.parse_string(layout_raw.get_string_from_utf8())
			assert(layout.shipped_import_sha256 == receipt.shipped_import_sha256)
			assert(layout.compiled_sha256 == receipt.compiled_sha256)
			assert(layout.compiled == receipt.compiled)
			assert(layout.level_sha256 == FileAccess.get_sha256(level_path))
			var layout_temp: String = args[2] + ".layout-" + level + ".json"
			_write(layout_temp, layout_raw)
			assert(pack.add_file(layout_path, layout_temp) == OK)
			var temporary: String = args[2] + "." + level + ".json"
			_write(temporary, JSON.stringify(receipt).to_utf8_buffer())
			assert(pack.add_file(identity_path, temporary) == OK)
			var files := ["atlas.json"]
			for layer in data.layers:
				files.append(String(layer.texture))
			for name in files:
				var raw := FileAccess.get_file_as_bytes(directory + name)
				assert(not raw.is_empty())
				var target: String = args[2] + "." + level + "." + name
				_write(target, raw)
				assert(pack.add_file(directory + name, target) == OK)
	if args[0] == "build":
		assert(pack.flush() == OK)
	FileAccess.open(args[2] + ".inspection.json", FileAccess.WRITE).store_string(
		JSON.stringify(rows)
	)
	print("SHIPPED_RADAR_RECEIPTS_OK")
	quit()


func _write(path: String, raw: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(raw)
	file.close()


func _check() -> void:
	var script = load("res://scripts/ui/RadarAtlas.gd")
	var count := 0
	for level in LEVELS:
		var atlas = script.new()
		var deadline := Time.get_ticks_msec() + 30000
		while not atlas.load_level(level) and atlas.status == "verifying_source":
			assert(Time.get_ticks_msec() < deadline)
			await process_frame
		assert(atlas.status == "ready", atlas.status)
		for layer in atlas.manifest.layers:
			var result: Dictionary = {}
			while result.is_empty():
				result = atlas.select_layer(float(layer.height))
				assert(Time.get_ticks_msec() < deadline)
				await process_frame
			count += 1
	print("SHIPPED_RADAR_READY slices=", count)
	quit()
