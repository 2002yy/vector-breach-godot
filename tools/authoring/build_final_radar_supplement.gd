extends SceneTree
## Prepare against originals, then build/check against a real product PCK in an empty project.

const LEVELS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 3)
	if args[0] == "prepare":
		assert(not FileAccess.file_exists(args[1]))
		var entries := []
		for level in LEVELS:
			var directory: String = "res://assets/local_reference/radar/" + level + "/v4/"
			var atlas_path := directory + "atlas.json"
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
			assert(FileAccess.get_sha256(data.source) == data.source_sha256)
			assert(
				FileAccess.get_sha256(String(data.source) + ".import") == data.source_import_sha256
			)
			var level_path: String = "res://data/levels/" + level + ".json"
			assert(FileAccess.get_sha256(level_path) == data.level_sha256)
			entries.append(
				{
					"level": level,
					"directory": directory,
					"data": data,
					"atlas_sha256": FileAccess.get_sha256(atlas_path),
					"local_directory": ProjectSettings.globalize_path(directory)
				}
			)
		FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(entries))
		print("RADAR_FINAL_PREPARED")
	else:
		assert(not FileAccess.file_exists("res://scripts/ui/RadarAtlas.gd"))
		assert(ProjectSettings.load_resource_pack(args[1], true))
		if args[0] == "build":
			assert(args.size() == 4 and not FileAccess.file_exists(args[3]))
			var entries: Array = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
			var pack := PCKPacker.new()
			assert(pack.pck_start(args[3]) == OK)
			for entry in entries:
				var data: Dictionary = entry.data
				var source := String(data.source)
				assert(not FileAccess.file_exists(source))
				assert(
					(
						FileAccess.get_sha256("res://data/levels/" + entry.level + ".json")
						== data.level_sha256
					)
				)
				var config := ConfigFile.new()
				assert(config.load(source + ".import") == OK)
				var compiled := String(config.get_value("remap", "path"))
				assert(FileAccess.file_exists(compiled))
				var receipt := {
					"schema": 1,
					"compiled": compiled,
					"compiled_sha256": FileAccess.get_sha256(compiled),
					"atlas_sha256": entry.atlas_sha256,
					"shipped_import_sha256": FileAccess.get_sha256(source + ".import")
				}
				for key in ["source", "source_sha256", "source_import_sha256", "level_sha256"]:
					receipt[key] = data[key]
				var temporary := args[3] + "." + String(entry.level) + ".json"
				FileAccess.open(temporary, FileAccess.WRITE).store_string(JSON.stringify(receipt))
				assert(pack.add_file(entry.directory + "export_identity.json", temporary) == OK)
				assert(
					(
						FileAccess.get_sha256(entry.local_directory + "atlas.json")
						== entry.atlas_sha256
					)
				)
				assert(
					(
						pack.add_file(
							entry.directory + "atlas.json", entry.local_directory + "atlas.json"
						)
						== OK
					)
				)
				for layer in data.layers:
					var local_path: String = entry.local_directory + layer.texture
					assert(FileAccess.get_sha256(local_path) == layer.sha256)
					assert(pack.add_file(entry.directory + layer.texture, local_path) == OK)
			assert(pack.flush() == OK)
			print("RADAR_FINAL_SUPPLEMENT_BUILT")
		else:
			assert(ProjectSettings.load_resource_pack(args[2], true))
			var script = load("res://scripts/ui/RadarAtlas.gd")
			var slices := 0
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
					slices += 1
				atlas = null
			print("RADAR_FINAL_READY maps=3 slices=", slices)
	quit()
