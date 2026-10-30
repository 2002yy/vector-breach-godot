extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	for label in ["first", "second"]:
		var path: String = args[0] + "/" + label
		assert(not FileAccess.file_exists(path + ".pck"))
		var file := FileAccess.open(path + ".json", FileAccess.WRITE)
		file.store_string(label)
		file.close()
		var pack := PCKPacker.new()
		assert(pack.pck_start(path + ".pck") == OK)
		assert(pack.add_file("res://priority-fixture.json", path + ".json") == OK)
		assert(pack.flush() == OK)
	assert(ProjectSettings.load_resource_pack(args[0] + "/first.pck", false))
	print("PRIORITY_FIRST ", FileAccess.get_file_as_string("res://priority-fixture.json"))
	assert(ProjectSettings.load_resource_pack(args[0] + "/second.pck", false))
	print("PRIORITY_FALSE ", FileAccess.get_file_as_string("res://priority-fixture.json"))
	assert(FileAccess.get_file_as_string("res://priority-fixture.json") == "first")
	assert(ProjectSettings.load_resource_pack(args[0] + "/second.pck", true))
	assert(FileAccess.get_file_as_string("res://priority-fixture.json") == "second")
	print("RADAR_DATA_PACK_PRIORITY_OK")
	quit()
