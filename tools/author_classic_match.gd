extends SceneTree

const BUILDER = preload("res://tools/authoring/ClassicCollisionLayout.gd")
const OUTPUT := "res://data/levels/match-local/dustline.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(OUTPUT):
		push_error(
			(
				"Existing baseline preserved. Archive/remove it explicitly before re-authoring: "
				+ OUTPUT
			)
		)
		quit(1)
		return
	var level := load("res://scenes/level/GrayboxLevel.tscn").instantiate() as Node3D
	level.set("level_id", "dustline-depths")
	root.add_child(level)
	for _frame in range(3):
		await physics_frame
	var data: Dictionary = level.call("get_current_level_data")
	var layout := BUILDER.build(level.get_world_3d().direct_space_state, data, [])
	if layout.is_empty():
		push_error("Authoring failed: no complete connected 5v5 layout.")
		quit(1)
		return
	var collision_path := String(data.get("runtime_collision_scene", data.get("visual_scene", "")))
	var hashes := {}
	for id in ["dustline-depths", "dustline-depths-original-local"]:
		var path := "res://data/levels/%s.json" % id
		hashes[path] = FileAccess.get_sha256(path)
	var manifest := {
		"schema": 1,
		"authored_utc": Time.get_datetime_string_from_system(true),
		"collision_path": collision_path,
		"collision_sha256": FileAccess.get_sha256(collision_path),
		"level_sha256": hashes,
		"layout": layout,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("CLASSIC_AUTHORED=" + OUTPUT)
	quit(0)
