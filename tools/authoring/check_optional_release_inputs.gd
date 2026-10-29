extends SceneTree
## Run in an empty project: only scripts shipped inside the supplied product PCK are used.


func _initialize() -> void:
	_run.call_deferred()


# gdlint: disable=max-returns
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4 or FileAccess.file_exists(args[3]):
		push_error("Require product PCK, sidecar, existing support root, fresh output JSON")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(args[0], false):
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(args[1], false):
		quit(1)
		return
	var router = load("res://scripts/LaunchRouter.gd")
	var inputs = load("res://scripts/characters/SourceCharacterRuntimeInputs.gd")
	if router == null or inputs == null:
		quit(1)
		return
	if (
		router.entry_for(PackedStringArray(["--controlled-game"]))
		!= "res://scenes/ControlledGame.tscn"
	):
		quit(1)
		return
	var paths := PackedStringArray()
	for short_name in ["dust2", "mirage", "inferno"]:
		paths.append(args[2].path_join("candidate-inputs/" + short_name + "/bundle.json"))
	var catalog := {}
	for path in paths:
		var bundle: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not bundle is Dictionary or not bundle.get("level") is String:
			quit(1)
			return
		catalog[bundle.level] = path
	var records := []
	if catalog.size() != 3:
		quit(1)
		return
	for id in catalog:
		var level: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/levels/" + id + ".json")
		)
		if not level is Dictionary:
			quit(1)
			return
		var inspected: Dictionary = inputs.inspect(catalog[id], level)
		if inspected.size() < 4:
			push_error("Exported runtime rejected optional input bundle: " + id)
			quit(1)
			return
		records.append({"map": id, "bundle": catalog[id], "roles_verified": inspected.keys()})
	var result := {
		"kind": "exported_optional_input_inspection_not_render_acceptance",
		"product_sha256": FileAccess.get_sha256(args[0]),
		"sidecar_sha256": FileAccess.get_sha256(args[1]),
		"maps": records,
		"gpu_configure_verified": false,
		"scene_instantiated": false
	}
	var file := FileAccess.open(args[3], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("EXPORTED_OPTIONAL_INPUTS_OK maps=3 roles=5")
	quit(0)
