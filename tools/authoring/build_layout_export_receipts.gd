extends SceneTree
const LEVELS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 3)
	if args[0] == "prepare":
		var rows := []
		for id in LEVELS:
			var path: String = "res://data/levels/" + id + ".json"
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			var manifest_path: String = data.get(
				"match_manifest", "res://data/levels/match-local/dustline.json"
			)
			var manifest: Dictionary = JSON.parse_string(
				FileAccess.get_file_as_string(manifest_path)
			)
			assert(FileAccess.get_sha256(manifest.collision_path) == manifest.collision_sha256)
			assert(FileAccess.get_sha256(path) == manifest.level_sha256[path])
			rows.append(
				{
					"level": id,
					"manifest_path": manifest_path,
					"source": manifest.collision_path,
					"source_sha256": manifest.collision_sha256,
					"manifest_sha256": FileAccess.get_sha256(manifest_path),
					"level_sha256": FileAccess.get_sha256(path)
				}
			)
		assert(not FileAccess.file_exists(args[1]))
		FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(rows))
	else:
		assert(not FileAccess.file_exists(args[2]))
		if args.size() > 3:
			assert(ProjectSettings.load_resource_pack(args[3], false))
		# build argument1 is a source-verified descriptor; actual product is mounted by host.
		var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		var pack := PCKPacker.new()
		assert(pack.pck_start(args[2]) == OK)
		for row in rows:
			assert(not FileAccess.file_exists(row.source))
			assert(FileAccess.get_sha256(row.manifest_path) == row.manifest_sha256)
			assert(
				(
					FileAccess.get_sha256("res://data/levels/" + row.level + ".json")
					== row.level_sha256
				)
			)
			var config := ConfigFile.new()
			assert(config.load(String(row.source) + ".import") == OK)
			var receipt: Dictionary = row.duplicate(true)
			receipt.schema = 1
			receipt.compiled = config.get_value("remap", "path")
			receipt.compiled_sha256 = FileAccess.get_sha256(receipt.compiled)
			receipt.shipped_import_sha256 = FileAccess.get_sha256(String(row.source) + ".import")
			assert(String(receipt.compiled_sha256).length() == 64)
			var temporary: String = args[2] + "." + row.level + ".json"
			FileAccess.open(temporary, FileAccess.WRITE).store_string(JSON.stringify(receipt))
			assert(pack.add_file(String(row.manifest_path) + ".export.json", temporary) == OK)
		if args.size() > 3:
			for row in rows:
				var directory: String = "res://assets/local_reference/radar/" + row.level + "/v4/"
				var atlas: Dictionary = JSON.parse_string(
					FileAccess.get_file_as_string(directory + "atlas.json")
				)
				var files: Array = ["atlas.json", "export_identity.json"]
				for layer in atlas.layers:
					files.append(layer.texture)
				for name in files:
					var raw := FileAccess.get_file_as_bytes(directory + name)
					assert(not raw.is_empty())
					var temporary: String = args[2] + ".radar-" + row.level + "-" + name
					FileAccess.open(temporary, FileAccess.WRITE).store_buffer(raw)
					assert(pack.add_file(directory + name, temporary) == OK)
		assert(pack.flush() == OK)
	print("LAYOUT_RECEIPTS_OK")
	quit()
