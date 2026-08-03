extends Node

const AUDIO_FEEDBACK_SCRIPT = preload("res://scripts/audio/CombatAudioFeedback.gd")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("manifest_assets_exist_and_load", _test_manifest_assets_exist_and_load)
	await _run_test("sampled_runtime_branch_and_snapshot", _test_sampled_runtime_branch_and_snapshot)
	await _run_test("procedural_fallback_remains_available", _test_procedural_fallback_remains_available)
	if _failures.is_empty():
		print("[AudioAssetTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return
	push_error("[AudioAssetTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before := _failures.size()
	await callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[AudioAssetTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _make_feedback() -> Node3D:
	var feedback := AUDIO_FEEDBACK_SCRIPT.new() as Node3D
	add_child(feedback)
	return feedback

func _cleanup_feedback(feedback: Node3D) -> void:
	for player_name in ["ShotPlayer", "ImpactPlayer", "MovementPlayer", "MechanicalPlayer"]:
		var player := feedback.get_node(player_name)
		player.stop()
		player.stream = null
	feedback.set("_sample_bank", {})
	await get_tree().create_timer(0.15).timeout
	feedback.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _test_manifest_assets_exist_and_load() -> void:
	var feedback := _make_feedback()
	await get_tree().process_frame
	var manifest := feedback.call("get_asset_manifest") as Dictionary
	var paths: PackedStringArray = []
	for variants in manifest.values():
		for path_variant in variants:
			paths.append(String(path_variant))
	_assert_equal(paths.size(), 14, "audio manifest should track all deliberately shipped samples")
	for path in paths:
		_assert_true(ResourceLoader.exists(path), "manifest asset should exist: %s" % path)
		_assert_true(ResourceLoader.load(path) is AudioStream, "manifest asset should load as AudioStream: %s" % path)
	_assert_equal((feedback.call("get_debug_snapshot") as Dictionary).get("sample_assets"), 14, "all sample assets should enter the runtime bank")
	await _cleanup_feedback(feedback)

func _test_sampled_runtime_branch_and_snapshot() -> void:
	var feedback := _make_feedback()
	await get_tree().process_frame
	feedback.call("play_shot", {"hit": false, "weapon_slot": 0}, Vector3.ZERO)
	feedback.call("play_shot", {"hit": false, "weapon_slot": 1}, Vector3.ZERO)
	for surface in ["concrete", "metal", "wood", "water"]:
		feedback.call("play_footstep", Vector3.ZERO, surface, false)
	feedback.call("play_landing", Vector3.ZERO, "concrete", 0.8)
	GameState.current_weapon_slot = 0
	feedback.call("play_reload_started")
	var snapshot := feedback.call("get_debug_snapshot") as Dictionary
	_assert_equal(snapshot.get("shots"), 2, "sample branch should retain shot telemetry")
	_assert_equal(snapshot.get("footsteps"), 4, "sample branch should retain material footstep telemetry")
	_assert_equal(snapshot.get("landings"), 1, "sample branch should retain landing telemetry")
	_assert_equal(snapshot.get("reloads"), 1, "sample branch should retain reload telemetry")
	_assert_equal(snapshot.get("sampled_events"), 8, "all covered events should use imported samples")
	_assert_equal(snapshot.get("fallback_events"), 0, "complete bank should not unexpectedly synthesize covered events")
	await _cleanup_feedback(feedback)

func _test_procedural_fallback_remains_available() -> void:
	var feedback := _make_feedback()
	await get_tree().process_frame
	feedback.call("set_sample_assets_enabled", false)
	feedback.call("play_shot", {"hit": false, "weapon_slot": 0}, Vector3.ZERO)
	feedback.call("play_footstep", Vector3.ZERO, "metal", false)
	feedback.call("play_landing", Vector3.ZERO, "water", 0.5)
	feedback.call("play_reload_started")
	var snapshot := feedback.call("get_debug_snapshot") as Dictionary
	_assert_equal(snapshot.get("fallback_events"), 4, "disabled or missing sample assets should use procedural fallbacks")
	_assert_equal(snapshot.get("sampled_events"), 0, "forced fallback should not report sampled playback")
	_assert_true(feedback.get_node("ShotPlayer").stream is AudioStreamWAV, "shot fallback should remain a generated waveform")
	_assert_true(feedback.get_node("MovementPlayer").stream is AudioStreamWAV, "movement fallback should remain a generated waveform")
	_assert_true(feedback.get_node("MechanicalPlayer").stream is AudioStreamWAV, "mechanical fallback should remain a generated waveform")
	await _cleanup_feedback(feedback)
