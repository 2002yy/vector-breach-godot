extends Node

const HIT_FEEDBACK_LAYER_SCENE = preload("res://scenes/ui/HitFeedbackLayer.tscn")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_all_tests()
	if _failures.is_empty():
		print("[HitFeedbackLayerTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return

	push_error("[HitFeedbackLayerTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_all_tests() -> void:
	await _run_test("initial_state_and_miss_stay_hidden", _test_initial_state_and_miss_stay_hidden)
	await _run_test("terrain_hit_shows_neutral_message_then_hides", _test_terrain_hit_shows_neutral_message_then_hides)
	await _run_test("nonlethal_hit_shows_marker_and_remaining_hp", _test_nonlethal_hit_shows_marker_and_remaining_hp)
	await _run_test("kill_hit_shows_kill_text_and_color_then_hides", _test_kill_hit_shows_kill_text_and_color_then_hides)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before: int = _failures.size()
	await callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[HitFeedbackLayerTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_color_close(actual: Color, expected: Color, epsilon: float, message: String) -> void:
	var close_enough := absf(actual.r - expected.r) <= epsilon \
		and absf(actual.g - expected.g) <= epsilon \
		and absf(actual.b - expected.b) <= epsilon \
		and absf(actual.a - expected.a) <= epsilon
	if close_enough:
		return
	_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])

func _instantiate_layer() -> CanvasLayer:
	var layer: CanvasLayer = HIT_FEEDBACK_LAYER_SCENE.instantiate()
	add_child(layer)
	return layer

func _cleanup_layer(layer: CanvasLayer) -> void:
	layer.queue_free()
	await get_tree().process_frame

func _advance_layer(layer: CanvasLayer, delta: float) -> void:
	layer.call("_process", delta)

func _test_initial_state_and_miss_stay_hidden() -> void:
	var layer: CanvasLayer = _instantiate_layer()
	await get_tree().process_frame
	var marker_label: Label = layer.get_node("CenterMarker")
	var message_label: Label = layer.get_node("BottomMessage")
	_assert_true(not marker_label.visible, "marker should start hidden")
	_assert_true(not message_label.visible, "message should start hidden")
	layer.call("show_shot_feedback", {"hit": false})
	_assert_true(not marker_label.visible, "marker should stay hidden on miss")
	_assert_true(not message_label.visible, "message should stay hidden on miss")
	await _cleanup_layer(layer)

func _test_terrain_hit_shows_neutral_message_then_hides() -> void:
	var layer: CanvasLayer = _instantiate_layer()
	await get_tree().process_frame
	var marker_label: Label = layer.get_node("CenterMarker")
	var message_label: Label = layer.get_node("BottomMessage")
	layer.call("show_shot_feedback", {
		"hit": true,
		"damage_result": {}
	})
	_assert_true(not marker_label.visible, "terrain hit should not show center marker")
	_assert_true(message_label.visible, "terrain hit should show bottom message")
	_assert_equal(message_label.text, "命中地形", "terrain hit should show neutral terrain text")
	_assert_color_close(message_label.modulate, layer.get("neutral_color"), 0.001, "terrain hit should use neutral color")
	_advance_layer(layer, float(layer.get("message_duration")) + 0.01)
	_assert_true(not message_label.visible, "terrain hit message should hide after timer elapses")
	await _cleanup_layer(layer)

func _test_nonlethal_hit_shows_marker_and_remaining_hp() -> void:
	var layer: CanvasLayer = _instantiate_layer()
	await get_tree().process_frame
	var marker_label: Label = layer.get_node("CenterMarker")
	var message_label: Label = layer.get_node("BottomMessage")
	layer.call("show_shot_feedback", {
		"hit": true,
		"damage_result": {
			"hit": true,
			"killed": false,
			"remaining_health": 66
		}
	})
	_assert_true(marker_label.visible, "nonlethal hit should show center marker")
	_assert_true(message_label.visible, "nonlethal hit should show message")
	_assert_equal(message_label.text, "命中  剩余HP 66", "nonlethal hit should show remaining hp text")
	_assert_color_close(marker_label.modulate, layer.get("hit_color"), 0.001, "nonlethal hit marker should use hit color")
	_advance_layer(layer, float(layer.get("marker_duration")) + 0.01)
	_assert_true(not marker_label.visible, "nonlethal hit marker should hide after marker timer elapses")
	_assert_true(message_label.visible, "message should still be visible until its longer timer elapses")
	_advance_layer(layer, float(layer.get("message_duration")) + 0.01)
	_assert_true(not message_label.visible, "nonlethal hit message should hide after message timer elapses")
	await _cleanup_layer(layer)

func _test_kill_hit_shows_kill_text_and_color_then_hides() -> void:
	var layer: CanvasLayer = _instantiate_layer()
	await get_tree().process_frame
	var marker_label: Label = layer.get_node("CenterMarker")
	var message_label: Label = layer.get_node("BottomMessage")
	layer.call("show_shot_feedback", {
		"hit": true,
		"damage_result": {
			"hit": true,
			"killed": true,
			"remaining_health": 0
		}
	})
	_assert_true(marker_label.visible, "kill hit should show center marker")
	_assert_true(message_label.visible, "kill hit should show message")
	_assert_equal(message_label.text, "击倒目标", "kill hit should show kill confirmation text")
	_assert_color_close(marker_label.modulate, layer.get("kill_color"), 0.001, "kill hit marker should use kill color")
	_assert_color_close(message_label.modulate, layer.get("kill_color"), 0.001, "kill hit message should use kill color")
	_advance_layer(layer, float(layer.get("marker_duration")) + 0.01)
	_advance_layer(layer, float(layer.get("message_duration")) + 0.01)
	_assert_true(not marker_label.visible, "kill marker should hide after timer elapses")
	_assert_true(not message_label.visible, "kill message should hide after timer elapses")
	await _cleanup_layer(layer)
