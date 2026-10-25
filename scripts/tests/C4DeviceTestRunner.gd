extends Node

const C4_SCENE := preload("res://scenes/objective/C4Device.tscn")
const C4_RUNTIME_PATH := "res://assets/models/objectives/c4_device.glb"
const HUD_SCENE := preload("res://scenes/ui/CombatHud.tscn")

var _failures: PackedStringArray = []
var _passes: int = 0

func _ready() -> void:
	await _run_test("runtime_asset_and_stable_nodes", _test_runtime_asset_and_stable_nodes)
	await _run_test("carried_drop_pickup_state_contract", _test_carried_drop_pickup_state_contract)
	await _run_test("planted_state_and_radar_contract", _test_planted_state_and_radar_contract)
	await _run_test("armed_urgency_audio_light_contract", _test_armed_urgency_audio_light_contract)
	await _run_test("armed_feedback_resets_between_states", _test_armed_feedback_resets_between_states)
	await _run_test("frozen_gameplay_constants", _test_frozen_gameplay_constants)
	await _run_test(
		"plant_announcement_cancel_and_lifecycle", _test_plant_announcement_cancel_and_lifecycle
	)
	await _run_test(
		"plant_announcement_team_and_spectator", _test_plant_announcement_team_and_spectator
	)
	await _run_test("detonation_feedback_and_reset", _test_detonation_feedback_and_reset)
	await _run_test("blast_commits_before_settlement", _test_blast_commits_before_settlement)
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


func _test_plant_announcement_cancel_and_lifecycle() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	var banner: PanelContainer = hud.get_node("HudRoot/ObjectiveAnnouncement")
	banner.set_process(false)
	var events: Array = []
	var listener := func(site: String, serial: int) -> void: events.append([site, serial])
	RoundManager.bomb_planted.connect(listener)
	RoundManager.start_round()
	RoundManager.set_live()
	_assert_true(RoundManager.begin_plant("A", "T"), "begin real player plant")
	RoundManager.tick_objective_interaction(1.0, true)
	_assert_true(not banner.visible and events.is_empty(), "incomplete plant never announces")
	RoundManager.tick_objective_interaction(3.2, false)
	_assert_true(not banner.visible and events.is_empty(), "canceled plant never announces")
	RoundManager.begin_plant("B", "T", "ai")
	_assert_true(
		RoundManager.tick_objective_interaction(3.2, true), "AI completion uses real plant"
	)
	_assert_equal(
		events, [["B", RoundManager.round_serial]], "one committed event with site and round"
	)
	_assert_true(banner.visible, "completed plant shows announcement")
	banner.call("_process", 1.0)
	var left := float(banner.get("remaining"))
	RoundManager.set_paused_menu()
	banner.call("_process", 10.0)
	RoundManager.resume_round()
	_assert_near(
		float(banner.get("remaining")), left, 0.001, "pause/resume neither expires nor replays"
	)
	_assert_true(not RoundManager.plant_bomb("A"), "duplicate committed plant is rejected")
	_assert_equal(events.size(), 1, "resume and rejected plant produce no extra event")
	banner.call("_process", 5.0)
	_assert_true(not banner.visible, "announcement expires while persistent bomb state remains")
	_assert_equal(
		RoundManager.state, RoundManager.RoundState.BOMB_PLANTED, "expiry leaves bomb active"
	)
	RoundManager.start_round()
	RoundManager.set_live()
	RoundManager.plant_bomb("A")
	_assert_true(banner.visible, "next round may announce again")
	RoundManager.defuse_bomb()
	_assert_true(not banner.visible, "round settlement removes stale success banner")
	RoundManager.start_round()
	RoundManager.set_live()
	RoundManager.plant_bomb("B")
	RoundManager.set_warmup()
	_assert_true(not banner.visible, "return to lobby clears banner")
	RoundManager.bomb_planted.disconnect(listener)
	hud.queue_free()
	await get_tree().process_frame


func _test_plant_announcement_team_and_spectator() -> void:
	var previous_team := GameState.player_team
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	var banner: PanelContainer = hud.get_node("HudRoot/ObjectiveAnnouncement")
	for team in ["T", "CT"]:
		GameState.player_team = team
		for dead in [false, true]:
			RoundManager.start_round()
			RoundManager.set_live()
			hud.call(
				"update_display",
				{
					"game_started": true,
					"menu_open": false,
					"spectator": {"active": dead, "has_target": false}
				}
			)
			RoundManager.begin_plant("A", "T", "player")
			RoundManager.tick_objective_interaction(3.2, true)
			_assert_true(banner.is_visible_in_tree(), "%s dead=%s sees success" % [team, dead])
			var detail: Label = banner.get("detail")
			_assert_true(
				detail.text.contains("保护" if team == "T" else "拆除"), "team-specific action"
			)
			hud.call("update_display", {"game_started": true, "menu_open": true})
			_assert_true(not banner.is_visible_in_tree(), "menu hides banner with HUD")
	RoundManager.set_warmup()
	GameState.player_team = previous_team
	hud.queue_free()
	await get_tree().process_frame


func _test_detonation_feedback_and_reset() -> void:
	var device := await _make_device()
	_assert_true(not device.call("detonate"), "carried C4 cannot detonate")
	device.call("plant_at", Vector3.ZERO, "A")
	_assert_true(device.call("detonate"), "planted C4 creates feedback")
	var effect: Node3D = device.get_node("ExplosionEffect")
	effect.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert_true(not device.get_node("MeshRoot").visible, "consumed bomb mesh is hidden")
	_assert_true(not device.get_node("BeepPlayer").playing, "blast stops armed beeps")
	_assert_true(not device.call("detonate"), "duplicate blast is rejected")
	_assert_equal(
		device.get_node("ExplosionEffect"), effect, "duplicate cannot spawn another effect"
	)
	_assert_true(
		device.call("is_explosion_presenting"), "initial blast reserves a viewing interval"
	)
	var audio: AudioStreamPlayer3D = effect.get("audio")
	_assert_true(
		audio.stream is AudioStreamWAV and audio.stream.get_length() > 1.0, "spatial blast tail"
	)
	effect.call("_process", 1.3)
	_assert_true(
		not device.call("is_explosion_presenting"), "result may appear after the initial blast"
	)
	RoundManager.set_paused_menu()
	var previous_age := float(effect.get("age"))
	effect.call("_process", 5.0)
	_assert_near(float(effect.get("age")), previous_age, 0.001, "pause holds visual lifetime")
	_assert_true(audio.stream_paused, "pause holds blast audio")
	RoundManager.set_warmup()
	device.call("set_carried", "T")
	_assert_true(not is_instance_valid(effect), "new round frees visual and audio together")
	_assert_true(not device.call("is_explosion_presenting"), "reset cannot suppress next result")
	device.call("plant_at", Vector3.ZERO, "B")
	device.call("detonate")
	device.get_node("ExplosionEffect").set_process(false)
	device.get_node("ExplosionEffect").call("_process", 2.5)
	await get_tree().process_frame
	_assert_true(
		not device.call("is_explosion_presenting"), "expired effect releases owner reference"
	)
	await _cleanup_device(device)
	# Headless frames can finish before AudioServer retires the stopped WAV playback.
	await get_tree().create_timer(0.08).timeout


func _test_blast_commits_before_settlement() -> void:
	var events: Array = []
	var blast := func(_site: String) -> void:
		events.append("blast")
		_assert_equal(
			RoundManager.state, RoundManager.RoundState.ROUND_END, "winner locked before damage"
		)
		RoundManager.end_round("CT", "ELIMINATION")
	var ended := func(winner: String, reason: String) -> void: events.append([winner, reason])
	RoundManager.bomb_exploded.connect(blast)
	RoundManager.round_ended.connect(ended)
	RoundManager.start_round()
	RoundManager.set_live()
	RoundManager.plant_bomb("A")
	RoundManager.time_remaining = 0.01
	RoundManager.call("_process", 0.02)
	_assert_equal(
		events, ["blast", ["T", "BOMB EXPLODED"]], "blast precedes settlement exactly once"
	)
	RoundManager.call("_process", 0.01)
	RoundManager.end_round("T", "BOMB EXPLODED")
	_assert_equal(
		events.size(), 2, "repeated ticks and callbacks cannot replay blast or settlement"
	)
	for reason in ["BOMB DEFUSED", "ELIMINATION", "TIME"]:
		events.clear()
		RoundManager.start_round()
		RoundManager.set_live()
		if reason != "TIME":
			RoundManager.plant_bomb("B")
		if reason == "BOMB DEFUSED":
			RoundManager.defuse_bomb()
		else:
			RoundManager.end_round("CT", reason)
		_assert_equal(events, [["CT", reason]], "non-blast victory cannot explode")
	RoundManager.bomb_exploded.disconnect(blast)
	RoundManager.round_ended.disconnect(ended)
	RoundManager.set_warmup()
