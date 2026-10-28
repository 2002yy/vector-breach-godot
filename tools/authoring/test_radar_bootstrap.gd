extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bootstrap_script = load("res://RadarPackBootstrap.gd")
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	var directory := args[0]
	assert(not DirAccess.dir_exists_absolute(directory))
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var executable := directory.path_join("VectorBreach.exe")
	var sidecar := directory.path_join("VectorBreach-radar.pck")
	assert(bootstrap_script.bootstrap(false, executable) == "source_skipped")
	assert(bootstrap_script.bootstrap(true, executable) == "absent")
	FileAccess.open(sidecar, FileAccess.WRITE).store_string("not a valid pack")
	assert(bootstrap_script.bootstrap(true, executable) == "invalid")
	assert(DirAccess.remove_absolute(sidecar) == OK)
	var payload := directory.path_join("payload.txt")
	FileAccess.open(payload, FileAccess.WRITE).store_string("sidecar")
	var pack := PCKPacker.new()
	assert(pack.pck_start(sidecar) == OK)
	assert(pack.add_file("res://existing.txt", payload) == OK)
	assert(pack.add_file("res://new-radar-asset.txt", payload) == OK)
	assert(pack.flush() == OK)
	assert(bootstrap_script.bootstrap(false, executable) == "source_skipped")
	assert(not FileAccess.file_exists("res://new-radar-asset.txt"))
	assert(bootstrap_script.bootstrap(true, executable) == "mounted")
	assert(FileAccess.get_file_as_string("res://existing.txt") == "product")
	assert(FileAccess.get_file_as_string("res://new-radar-asset.txt") == "sidecar")
	print("RADAR_BOOTSTRAP_OK source_absent_corrupt_mount_no_override")
	quit()
