extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 3)
	var layout = load(args[1])
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var checks := 0
	for row in rows:
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/levels/" + row.level + ".json")
		)
		assert(not FileAccess.file_exists(row.source))
		assert(not layout.input_stamps(data).is_empty())
		assert(not layout.load_authored(data).is_empty())
		checks += 2
		var receipt_path: String = row.manifest_path + ".export.json"
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
		for field in [
			"manifest_sha256",
			"source_sha256",
			"level_sha256",
			"shipped_import_sha256",
			"compiled_sha256",
			"compiled"
		]:
			var receipt := original.duplicate(true)
			receipt[field] = "bad"
			var path: String = args[2].path_join("negative-") + row.level + "-" + field
			FileAccess.open(path + ".json", FileAccess.WRITE).store_string(JSON.stringify(receipt))
			var pack := PCKPacker.new()
			assert(pack.pck_start(path + ".pck") == OK)
			assert(pack.add_file(receipt_path, path + ".json") == OK)
			assert(pack.flush() == OK)
			assert(ProjectSettings.load_resource_pack(path + ".pck", true))
			assert(layout.load_authored(data).is_empty(), field)
			checks += 1
	print("LAYOUT_EXPORT_CHECKS_OK checks=", checks)
	quit()
