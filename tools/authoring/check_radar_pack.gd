extends SceneTree
## Build an exact-byte radar evidence pack, then validate it from an isolated project.

const LEVELS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	if args[0].begins_with("build"):
		assert(not FileAccess.file_exists(args[1]), "Choose a new evidence pack path")
		var pack := PCKPacker.new()
		assert(pack.pck_start(args[1]) == OK)
		var files := ["res://scripts/ui/RadarAtlas.gd"]
		for level in LEVELS:
			var directory: String = "res://assets/local_reference/radar/" + level + "/v4/"
			var manifest: Dictionary = JSON.parse_string(
				FileAccess.get_file_as_string(directory + "atlas.json")
			)
			files.append(directory + "atlas.json")
			files.append("res://data/levels/" + level + ".json")
			files.append(manifest.source)
			files.append(String(manifest.source) + ".import")
			for layer in manifest.layers:
				files.append(directory + String(layer.texture))
		for file in files:
			if args[0] == "build_missing" and file.ends_with("layer-00.png"):
				continue
			assert(pack.add_file(file, file) == OK, file)
		assert(pack.flush() == OK)
		print("RADAR_PACK_BUILT files=", files.size())
	else:
		assert(not FileAccess.file_exists("res://scripts/ui/RadarAtlas.gd"))
		assert(ProjectSettings.load_resource_pack(args[1], true))
		var atlas_script = load("res://scripts/ui/RadarAtlas.gd")
		var count := 0
		for level in LEVELS:
			var atlas = atlas_script.new()
			var deadline := Time.get_ticks_msec() + 30000
			while not atlas.load_level(level):
				assert(Time.get_ticks_msec() < deadline, atlas.status)
				await process_frame
			for layer in atlas.manifest.layers:
				if args[0] == "check_missing":
					deadline = Time.get_ticks_msec() + 30000
					while atlas.status == "ready":
						atlas.select_layer(float(atlas.manifest.layers[0].height))
						assert(Time.get_ticks_msec() < deadline)
						await process_frame
					assert(atlas.status == "texture_identity_mismatch")
					print("RADAR_PACK_MISSING_REJECTED")
					quit()
					return
				var result: Dictionary = {}
				deadline = Time.get_ticks_msec() + 30000
				while result.is_empty():
					result = atlas.select_layer(float(layer.height))
					assert(Time.get_ticks_msec() < deadline, atlas.status)
					await process_frame
				assert(result.texture != null)
				count += 1
			assert(atlas.textures.size() <= 2)
			print("RADAR_PACK_LEVEL_OK ", level)
			atlas = null
		print("RADAR_PACK_READY maps=3 slices=", count)
	quit()
