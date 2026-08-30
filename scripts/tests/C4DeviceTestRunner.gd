extends Node

const C4_SCENE := preload("res://scenes/objective/C4Device.tscn")
const C4_RUNTIME_PATH := "res://assets/models/objectives/c4_device.glb"

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("runtime_asset_and_stable_nodes", _test_runtime_asset_and_stable_nodes)
	await _run_test("carried_drop_pickup_state_contract", _test_carried_drop_pickup_state_contract)
	await _run_test("planted_state_and_radar_contract", _test_planted_state_and_radar_contract)
	await _run_test("armed_urgency_audio_light_contract", _test_armed_urgency_audio_light_contract)
	await _run_test("armed_feedback_resets_between_states", _test_armed_feedback_resets_between_states)
	await _run_test("frozen_gameplay_constants", _test_frozen_gameplay_constants)
	if _failures.is_empty():
		print("[C4DeviceTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return
	push_error("[C4DeviceTests] FAIL (%d/%d failed)" % [_failures.size(), _passes + _failures.size()])
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before := _failures.size()
	await callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[C4DeviceTests] PASS %s" % test_name)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_near(actual: float, expected: float, epsilon: float, message: String) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _make_device() -> Node3D:
	var device := C4_SCENE.instantiate() as Node3D
	add_child(device)
	await get_tree().process_frame
	return device

func _cleanup_device(device: Node3D) -> void:
	var beep_player := device.get_node_or_null("BeepPlayer") as AudioStreamPlayer3D
	if beep_player != null:
		beep_player.stop()
		beep_player.stream = null
	device.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _test_runtime_asset_and_stable_nodes() -> void:
	_assert_true(ResourceLoader.exists(C4_RUNTIME_PATH), "C4 runtime GLB must exist")
	_assert_true(ResourceLoader.load(C4_RUNTIME_PATH) is PackedScene, "C4 runtime GLB must import as PackedScene")
	var device := await _make_device()
	var mesh_root := device.get_node_or_null("MeshRoot") as Node3D
	_assert_true(mesh_root != null, "C4 must preserve MeshRoot control surface")
	_assert_true(device.get_node_or_null("MeshRoot/Visual") != null, "C4 must instance the production GLB below MeshRoot")
	_assert_true(device.get_node_or_null("MeshRoot/Body") == null, "legacy BoxMesh Body must not remain after production-asset integration")
	_assert_true(device.get_node_or_null("MeshRoot/StatusLight") is OmniLight3D, "C4 must preserve StatusLight")
	_assert_true(device.get_node_or_null("BeepPlayer") is AudioStreamPlayer3D, "C4 must preserve BeepPlayer")
	_assert_true(mesh_root != null and not mesh_root.visible, "initial carried state must hide world model")
	_assert_true((device.get_node("BeepPlayer") as AudioStreamPlayer3D).stream is AudioStreamWAV, "C4 beep procedural fallback must still initialize")
	await _cleanup_device(device)

func _test_carried_drop_pickup_state_contract() -> void:
	var device := await _make_device()
	var drop_position := Vector3(3.0, 0.0, 4.0)
	device.call("drop_at", drop_position)
	_assert_equal(device.get("device_state"), "dropped", "drop must enter dropped state")
	_assert_true((device.get_node("MeshRoot") as Node3D).visible, "dropped C4 must expose world model")
	_assert_true((device.global_position - drop_position).length() < 0.0001, "drop must preserve requested world position")
	_assert_true(device.call("can_pick_up", drop_position + Vector3(1.79, 0.0, 0.0), "T"), "T must pick up within frozen 1.8m radius")
	_assert_true(not device.call("can_pick_up", drop_position + Vector3(1.81, 0.0, 0.0), "T"), "pickup must reject positions beyond frozen 1.8m radius")
	_assert_true(not device.call("can_pick_up", drop_position, "CT"), "CT must not pick up dropped C4")
	_assert_true(device.call("pick_up", "T"), "T pickup must succeed from dropped state")
	_assert_equal(device.get("device_state"), "carried", "pickup must return to carried state")
	_assert_true(not (device.get_node("MeshRoot") as Node3D).visible, "carried C4 must hide world model")
	await _cleanup_device(device)

func _test_planted_state_and_radar_contract() -> void:
	var device := await _make_device()
	var plant_position := Vector3(-2.0, 0.0, 5.0)
	device.call("plant_at", plant_position, "B")
	_assert_equal(device.get("device_state"), "planted", "plant must enter planted state")
	_assert_equal(device.get("site_label"), "B", "plant must preserve site label")
	_assert_true((device.get_node("MeshRoot") as Node3D).visible, "planted C4 must expose world model")
	_assert_true(device.call("is_player_in_interaction_range", plant_position + Vector3(1.99, 0.0, 0.0)), "interaction must work inside frozen 2.0m range")
	_assert_true(not device.call("is_player_in_interaction_range", plant_position + Vector3(2.01, 0.0, 0.0)), "interaction must reject beyond frozen 2.0m range")
	var radar := device.call("get_radar_record") as Dictionary
	_assert_equal(radar.get("kind"), "c4", "radar kind schema must remain c4")
	_assert_equal(radar.get("state"), "planted", "radar state must track planted")
	_assert_equal(radar.get("site"), "B", "radar site schema must remain stable")
	_assert_true(radar.has("x") and radar.has("z"), "radar x/z keys must remain stable")
	await _cleanup_device(device)

func _test_armed_urgency_audio_light_contract() -> void:
	var device := await _make_device()
	var emitted_urgencies: Array[float] = []
	device.connect("beep_emitted", func(_world_position: Vector3, urgency: float) -> void:
		emitted_urgencies.append(urgency)
	)
	RoundManager.start_round()
	RoundManager.set_live()
	device.call("plant_at", Vector3.ZERO, "A")
	_assert_true(RoundManager.plant_bomb("A"), "test setup must enter the real BOMB_PLANTED state")
	RoundManager.time_remaining = RoundManager.bomb_duration
	device.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var calm_interval := float(device.get("_beep_timer"))
	var status_light := device.get_node("MeshRoot/StatusLight") as OmniLight3D
	_assert_true(not emitted_urgencies.is_empty(), "armed C4 must emit the beep signal in the real planted state")
	_assert_near(emitted_urgencies[-1], 0.0, 0.02, "full bomb timer should begin near zero urgency")
	_assert_true(status_light.light_energy > 2.0, "beep event must visibly pulse StatusLight brightness")

	RoundManager.time_remaining = 4.0
	device.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var urgent_interval := float(device.get("_beep_timer"))
	_assert_true(emitted_urgencies.size() >= 2, "urgent armed state must emit another beep signal")
	_assert_true(emitted_urgencies[-1] > 0.85, "last four seconds must produce high urgency independent of color")
	_assert_true(urgent_interval < calm_interval * 0.4, "beep cadence must accelerate materially as detonation approaches")
	_assert_true((device.get_node("BeepPlayer") as AudioStreamPlayer3D).pitch_scale > 1.2, "urgent beep pitch must increase as an additional non-color cue")
	RoundManager.set_warmup()
	await _cleanup_device(device)

func _test_armed_feedback_resets_between_states() -> void:
	var device := await _make_device()
	var status_light := device.get_node("MeshRoot/StatusLight") as OmniLight3D
	var beep_player := device.get_node("BeepPlayer") as AudioStreamPlayer3D
	RoundManager.start_round()
	RoundManager.set_live()
	device.call("plant_at", Vector3.ZERO, "A")
	_assert_true(RoundManager.plant_bomb("A"), "reset test setup must enter the real BOMB_PLANTED state")
	RoundManager.time_remaining = 4.0
	device.set("_beep_timer", 0.0)
	await get_tree().process_frame
	_assert_true(status_light.light_energy > 2.0, "reset test must begin from an active armed light pulse")
	_assert_true(beep_player.pitch_scale > 1.2, "reset test must begin from urgent pitch")

	device.call("set_carried", "T")
	_assert_near(status_light.light_energy, 0.45, 0.0001, "carried transition must clear stale armed light energy")
	_assert_near(beep_player.pitch_scale, 1.0, 0.0001, "carried transition must restore default beep pitch")
	_assert_true(not beep_player.playing, "carried transition must stop an in-flight armed beep")

	device.call("drop_at", Vector3(1.0, 0.0, 1.0))
	_assert_near(status_light.light_energy, 0.45, 0.0001, "dropped C4 must not inherit a prior round's armed pulse")
	_assert_near(beep_player.pitch_scale, 1.0, 0.0001, "dropped C4 must retain default non-armed pitch")
	_assert_equal(device.get("site_label"), "", "dropped C4 must not leak a previous plant site label")
	RoundManager.set_warmup()
	await _cleanup_device(device)

func _test_frozen_gameplay_constants() -> void:
	var device := await _make_device()
	_assert_near(float(device.get("explosion_radius")), 22.0, 0.0001, "Step 16 must not change explosion radius")
	_assert_near(float(device.get("lethal_radius")), 5.5, 0.0001, "Step 16 must not change lethal radius")
	await _cleanup_device(device)
