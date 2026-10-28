extends Node
## Optional exported asset sidecar; existing product resources always win.

const PACK_NAME := "VectorBreach-radar.pck"
var status := "uninitialized"


func _enter_tree() -> void:
	status = bootstrap(not OS.has_feature("editor"), OS.get_executable_path())


static func bootstrap(exported_runtime: bool, executable_path: String) -> String:
	if not exported_runtime:
		return "source_skipped"
	var path := executable_path.get_base_dir().path_join(PACK_NAME)
	if not FileAccess.file_exists(path):
		return "absent"
	var file := FileAccess.open(path, FileAccess.READ)
	if (
		file == null
		or file.get_length() < 16
		or file.get_buffer(4).get_string_from_ascii() != "GDPC"
	):
		return "invalid"
	# Never let a sidecar override executable scripts, project settings or map resources.
	return "mounted" if ProjectSettings.load_resource_pack(path, false) else "invalid"
