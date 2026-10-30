extends SceneTree

const BASE := "res://.godot/r49-radar-contract/"
const COMPILED := "res://.godot/imported/r49-radar-contract.scn"
var failures := 0
var checks := 0
var atlas_script: Script
var data: Dictionary
var receipt: Dictionary
var files: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _write(path: String, value: String) -> void:
	if path not in files:
		assert(not FileAccess.file_exists(path))
		files.append(path)
	FileAccess.open(path, FileAccess.WRITE).store_string(value)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("RADAR_CONTRACT_FAIL ", label)


func _verify() -> bool:
	var atlas = atlas_script.new()
	atlas.directory = BASE
	atlas.level_id = "fixture"
	atlas.manifest = data
	if not atlas._configure_identity(data, BASE + "atlas.json", data.source):
		return false
	atlas.status = "verifying_source"
	for _frame in range(100):
		atlas._poll_identity()
		if atlas.status != "verifying_source":
			return atlas.status == "ready"
		await process_frame
	return false


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BASE)
	var args := OS.get_cmdline_user_args()
	atlas_script = load(args[0] if not args.is_empty() else "res://scripts/ui/RadarAtlas.gd")
	var source := BASE + "raw.bin"
	_write(source, "original source")
	_write(COMPILED, "compiled source")
	_write(source + ".import", "author import")
	data = {
		"source": source,
		"source_sha256": FileAccess.get_sha256(source),
		"source_import_sha256": FileAccess.get_sha256(source + ".import"),
		"level_sha256": "a".repeat(64)
	}
	_write(BASE + "atlas.json", JSON.stringify(data))
	_check(await _verify(), "legacy raw author import")
	var remap := ConfigFile.new()
	remap.set_value("remap", "path", COMPILED)
	remap.save(source + ".import")
	receipt = data.duplicate(true)
	receipt.merge(
		{
			"schema": 1,
			"atlas_sha256": FileAccess.get_sha256(BASE + "atlas.json"),
			"shipped_import_sha256": FileAccess.get_sha256(source + ".import"),
			"compiled": COMPILED,
			"compiled_sha256": FileAccess.get_sha256(COMPILED)
		}
	)
	_write(BASE + "export_identity.json", JSON.stringify(receipt))
	_check(await _verify(), "raw and compiled export remap coexist")
	_write(source, "tampered source")
	_check(not await _verify(), "raw tamper cannot fall back")
	_write(source, "original source")
	_write(COMPILED, "tampered compiled")
	_check(not await _verify(), "compiled tamper despite valid raw")
	_write(COMPILED, "compiled source")
	for key in [
		"source",
		"source_sha256",
		"source_import_sha256",
		"level_sha256",
		"atlas_sha256",
		"shipped_import_sha256",
		"compiled",
		"compiled_sha256"
	]:
		var invalid := receipt.duplicate(true)
		invalid[key] = "wrong"
		_write(BASE + "export_identity.json", JSON.stringify(invalid))
		_check(not await _verify(), "receipt binding " + key)
	_write(BASE + "export_identity.json", JSON.stringify(receipt))
	DirAccess.remove_absolute(source)
	_check(await _verify(), "compiled-only export")
	_write(COMPILED, "tampered compiled")
	_check(not await _verify(), "compiled-only tamper")
	for path in files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("RADAR_RAW_EXPORT_CONTRACT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
