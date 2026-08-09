extends Node

const MODEL_ROOT := "res://assets/models"
const ASSET_ROOT := "res://assets"
const LOCAL_REFERENCE_PREFIX := "res://assets/local_reference/"
const KNOWN_GLB_DEBT := "res://assets/models/dustline/dustline_depths.glb"
const MIB := 1024 * 1024
const STANDARD_GLB_HARD_BYTES := 16 * MIB
const ALL_GLB_HARD_BYTES := 112 * MIB
const TEXTURE_HARD_BYTES := 8 * MIB
const AUDIO_HARD_BYTES := 64 * MIB

var _failures: PackedStringArray = []
var _passes := 0

func _ready() -> void:
	_run_test("budget_document_exists", _test_budget_document_exists)
	_run_test("known_debt_is_path_specific", _test_known_debt_is_path_specific)
	_run_test("normal_glbs_fit_single_file_gate", _test_normal_glbs_fit_single_file_gate)
	_run_test("formal_glbs_fit_total_gate", _test_formal_glbs_fit_total_gate)
	_run_test("textures_and_audio_fit_byte_gates", _test_textures_and_audio_fit_byte_gates)
	if _failures.is_empty():
		print("[PerformanceBudgetTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return
	push_error("[PerformanceBudgetTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_test(test_name: String, callable: Callable) -> void:
	var failures_before := _failures.size()
	callable.call()
	if _failures.size() == failures_before:
		_passes += 1
		print("[PerformanceBudgetTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _test_budget_document_exists() -> void:
	_assert_true(FileAccess.file_exists("res://docs/PERFORMANCE_BUDGETS.md"), "performance budget document should exist")
	_assert_true(FileAccess.file_exists("res://tools/check_asset_budgets.ps1"), "PowerShell asset gate should exist")

func _test_known_debt_is_path_specific() -> void:
	if not FileAccess.file_exists(KNOWN_GLB_DEBT):
		return
	_assert_true(FileAccess.get_file_as_bytes(KNOWN_GLB_DEBT).size() > STANDARD_GLB_HARD_BYTES, "known debt should still be visible above the normal gate")

func _test_normal_glbs_fit_single_file_gate() -> void:
	for path in _list_files(MODEL_ROOT, ["glb"]):
		if path == KNOWN_GLB_DEBT:
			continue
		_assert_true(FileAccess.get_file_as_bytes(path).size() <= STANDARD_GLB_HARD_BYTES, "%s should fit the 16 MiB GLB gate" % path)

func _test_formal_glbs_fit_total_gate() -> void:
	var total := 0
	for path in _list_files(MODEL_ROOT, ["glb"]):
		total += FileAccess.get_file_as_bytes(path).size()
	_assert_true(total <= ALL_GLB_HARD_BYTES, "formal GLBs should fit the 112 MiB total gate; actual=%d" % total)

func _test_textures_and_audio_fit_byte_gates() -> void:
	var texture_extensions := ["png", "jpg", "jpeg", "webp", "hdr", "exr"]
	for path in _list_files(ASSET_ROOT, texture_extensions):
		if path.begins_with(LOCAL_REFERENCE_PREFIX):
			continue
		_assert_true(FileAccess.get_file_as_bytes(path).size() <= TEXTURE_HARD_BYTES, "%s should fit the 8 MiB texture gate" % path)
	var audio_total := 0
	for path in _list_files(ASSET_ROOT, ["wav", "ogg", "mp3"]):
		if not path.begins_with(LOCAL_REFERENCE_PREFIX):
			audio_total += FileAccess.get_file_as_bytes(path).size()
	_assert_true(audio_total <= AUDIO_HARD_BYTES, "formal audio should fit the 64 MiB total gate; actual=%d" % audio_total)

func _list_files(root: String, extensions: Array) -> PackedStringArray:
	var result := PackedStringArray()
	_collect_files(root, extensions, result)
	return result

func _collect_files(directory_path: String, extensions: Array, result: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_failures.append("directory should open: %s" % directory_path)
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_files(path, extensions, result)
		elif entry.get_extension().to_lower() in extensions:
			result.append(path)
	directory.list_dir_end()
