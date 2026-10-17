extends SceneTree

const BUILDER = preload("res://tools/authoring/ClassicCollisionLayout.gd")
const OUTPUT := "res://data/levels/match-local/dustline.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if not args.is_empty() else "dustline-depths"
	var output := OUTPUT if id == "dustline-depths" else "res://data/levels/match-local/%s.json" % id
	if FileAccess.file_exists(output):
		push_error(
			(
				"Existing baseline preserved. Archive/remove it explicitly before re-authoring: "
				+ output
			)
		)
		quit(1)
		return
	var level := load("res://scenes/level/GrayboxLevel.tscn").instantiate() as Node3D
	level.set_script(load("res://tools/authoring/ClassicAuthoringLevel.gd"))
	level.set("level_id", id)
	root.add_child(level)
	for _frame in range(3):
		await physics_frame
	var data: Dictionary = level.call("get_current_level_data")
	var layout: Dictionary
	if String(data.get("navigationAuthoring", "")) == "recast":
		var graph := preload("res://tools/authoring/ClassicNavigationBake.gd").build(level)
		layout = BUILDER.from_navigation(data, graph)
	else:
		layout = BUILDER.build(level.get_world_3d().direct_space_state, data, [])
	if layout.is_empty():
		push_error("Authoring failed: no complete connected 5v5 layout.")
		quit(1)
		return
	var collision_path := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	var hashes := {}
	var ids := ["dustline-depths", "dustline-depths-original-local"] if id == "dustline-depths" else [id]
	for level_id in ids:
		var path := "res://data/levels/%s.json" % level_id
		hashes[path] = FileAccess.get_sha256(path)
	var manifest := {
		"schema": 1,
		"authored_utc": Time.get_datetime_string_from_system(true),
		"collision_path": collision_path,
		"collision_sha256": FileAccess.get_sha256(collision_path),
		"level_sha256": hashes,
		"layout": layout,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("CLASSIC_AUTHORED=" + output)
	quit(0)
