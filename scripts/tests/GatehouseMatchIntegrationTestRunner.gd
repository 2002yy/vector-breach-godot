extends Node

const MAIN_SCENE := preload("res://scenes/Main.tscn")

var _failures: PackedStringArray = []
var _passes: int = 0


func _ready() -> void:
	await _run_all_tests()
	if _failures.is_empty():
		print("[GatehouseMatchIntegrationTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return

	push_error("[GatehouseMatchIntegrationTests] FAIL (%d failures)" % _failures.size())
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)


func _run_all_tests() -> void:
	await _run_test("gatehouse_t_start_real_scene_halftime_reload", _test_t_start)
	await _run_test("gatehouse_ct_start_real_scene_halftime_reload", _test_ct_start)
	await _run_test("gatehouse_six_six_overtime_pair_real_scene", _test_overtime_pair)
	await _run_test("gatehouse_opposite_side_new_match_isolation", _test_new_match_isolation)
	await _run_test("gatehouse_duplicate_end_restart_is_idempotent", _test_duplicate_end_restart_idempotence)


func _run_test(test_name: String, callable: Callable) -> void:
	var failed_before := _failures.size()
	print("[GatehouseMatchIntegrationTests] START %s" % test_name)
	await callable.call()
	if _failures.size() == failed_before:
		_passes += 1
		print("[GatehouseMatchIntegrationTests] PASS %s" % test_name)


func _test_t_start() -> void:
	await _test_real_scene_halftime("T")


func _test_ct_start() -> void:
	await _test_real_scene_halftime("CT")


func _test_overtime_pair() -> void:
	var prefix := "overtime pair"
	var main := await _instantiate_main("T")
	if main == null:
		_failures.append("%s: Main.tscn should instantiate" % prefix)
		return
	var initial_actors := _get_actors(main)
	var player_squad_names := _team_names(initial_actors, "T")
	var opponent_squad_names := _team_names(initial_actors, "CT")
	var serials: Array[int] = []
	var regulation_old_refs: Array[WeakRef] = []
	var regulation_old_ids: Array[int] = []

	for round_index in range(12):
		if round_index == 11:
			var old_actors := _get_actors(main)
			_dirty_competitive_state(main, old_actors, "%s regulation 12" % prefix)
			regulation_old_refs = _weak_refs(old_actors)
			regulation_old_ids = _actor_ids(old_actors)
		var current_team := String(GameState.player_team)
		var winner := current_team if round_index % 2 == 0 else _opponent(current_team)
		var serial := _settle_current_round(winner, round_index + 1, "%s regulation %d" % [prefix, round_index + 1])
		_assert_true(not serials.has(serial), "%s: regulation serials should remain unique" % prefix)
		serials.append(serial)
		if round_index < 11:
			_trigger_round_restart()
			await _await_reload_frames()

	var overtime_entry := GameState.get_match_snapshot() as Dictionary
	_assert_equal(String(overtime_entry.get("phase", "")), "overtime", "%s: 6:6 should enter overtime" % prefix)
	_assert_equal(int(overtime_entry.get("player_score", -1)), 6, "%s: player squad should enter overtime at six" % prefix)
	_assert_equal(int(overtime_entry.get("opponent_score", -1)), 6, "%s: opponent squad should enter overtime at six" % prefix)
	_assert_equal(int(overtime_entry.get("regulation_rounds", -1)), 12, "%s: overtime should follow twelve regulation rounds" % prefix)
	var overtime_start_team := String(GameState.player_team)
	_trigger_round_restart()
	_assert_equal(String(RoundManager.get_state_name()), "Freeze", "%s: overtime should reload through Main" % prefix)
	_assert_player_spawn(main, overtime_start_team, true, "%s entry" % prefix)
	var overtime_actors := _get_actors(main)
	_assert_roster(overtime_actors, overtime_start_team, "%s entry" % prefix)
	_assert_equal(_team_names(overtime_actors, overtime_start_team), player_squad_names, "%s: player-squad identities should survive regulation" % prefix)
	_assert_equal(_team_names(overtime_actors, _opponent(overtime_start_team)), opponent_squad_names, "%s: opponent identities should survive regulation" % prefix)
	_assert_no_reused_actor_instances(overtime_actors, regulation_old_ids, "%s entry" % prefix)
	_assert_refs_detached(regulation_old_refs, "%s entry" % prefix)
	_assert_player_hard_reset(main, "%s entry" % prefix)
	_assert_bot_hard_reset(overtime_actors, "%s entry" % prefix)
	_assert_c4_assignment(main, overtime_actors, overtime_start_team, "%s entry" % prefix)
	await _await_reload_frames()
	_assert_refs_freed(regulation_old_refs, "%s entry" % prefix)

	var ot1_old_actors := _get_actors(main)
	_dirty_competitive_state(main, ot1_old_actors, "%s OT1" % prefix)
	var ot1_old_refs := _weak_refs(ot1_old_actors)
	var ot1_old_ids := _actor_ids(ot1_old_actors)
	var ot1_team := String(GameState.player_team)
	var ot1_serial := _settle_current_round(ot1_team, 13, "%s OT1" % prefix)
	_assert_true(not serials.has(ot1_serial), "%s: OT1 serial should be unique" % prefix)
	serials.append(ot1_serial)
	var after_ot1 := GameState.get_match_snapshot() as Dictionary
	_assert_equal(int(after_ot1.get("overtime_rounds", -1)), 1, "%s: OT1 should be recorded once" % prefix)
	_assert_equal(String(after_ot1.get("phase", "")), "overtime", "%s: OT1 should not finish the pair" % prefix)
	_assert_equal(String(GameState.player_team), _opponent(ot1_team), "%s: OT1 should swap sides" % prefix)
	var ot1_records := after_ot1.get("rounds", []) as Array
	_assert_true(bool((ot1_records[12] as Dictionary).get("side_swap", false)), "%s: OT1 record should carry side-swap evidence" % prefix)

	var ot2_team := String(GameState.player_team)
	_trigger_round_restart()
	_assert_player_spawn(main, ot2_team, true, "%s OT2" % prefix)
	var ot2_actors := _get_actors(main)
	_assert_roster(ot2_actors, ot2_team, "%s OT2" % prefix)
	_assert_equal(_team_names(ot2_actors, ot2_team), player_squad_names, "%s: stable player identities should follow the OT1 swap" % prefix)
	_assert_equal(_team_names(ot2_actors, _opponent(ot2_team)), opponent_squad_names, "%s: stable opponent identities should follow the OT1 swap" % prefix)
	_assert_no_reused_actor_instances(ot2_actors, ot1_old_ids, "%s OT2" % prefix)
	_assert_refs_detached(ot1_old_refs, "%s OT2" % prefix)
	_assert_player_hard_reset(main, "%s OT2" % prefix)
	_assert_bot_hard_reset(ot2_actors, "%s OT2" % prefix)
	_assert_c4_assignment(main, ot2_actors, ot2_team, "%s OT2" % prefix)
	await _await_reload_frames()
	_assert_refs_freed(ot1_old_refs, "%s OT2" % prefix)

	var ot2_serial := _settle_current_round(ot2_team, 14, "%s OT2 terminal" % prefix)
	_assert_true(not serials.has(ot2_serial), "%s: OT2 serial should be unique" % prefix)
	var terminal := GameState.get_match_snapshot() as Dictionary
	_assert_equal(String(terminal.get("phase", "")), "complete", "%s: OT2 should finish the match" % prefix)
	_assert_equal(String(terminal.get("result", "")), "player_win", "%s: winning both OT rounds should resolve player win" % prefix)
	_assert_equal(int(terminal.get("overtime_rounds", -1)), 2, "%s: exactly one OT pair should run" % prefix)
	_assert_equal((terminal.get("rounds", []) as Array).size(), 14, "%s: terminal record should contain fourteen rounds" % prefix)
	_trigger_round_restart()
	_assert_equal(String(RoundManager.get_state_name()), "Warmup", "%s: terminal restart should return to menu warmup" % prefix)
	_assert_true(not bool(main.get("game_started")) and bool(main.get("menu_open")), "%s: OT terminal should close gameplay and open the summary menu" % prefix)
	_assert_true(not String(main.get("_completed_match_record_path")).is_empty(), "%s: OT terminal should persist one match record" % prefix)
	await _cleanup_main(main)


func _test_new_match_isolation() -> void:
	var prefix := "opposite-side new match"
	var starting_team := "T"
	var next_start_team := "CT"
	var main := await _instantiate_main(starting_team)
	if main == null:
		_failures.append("%s: Main.tscn should instantiate" % prefix)
		return
	var main_id := int(main.get_instance_id())
	var first_match_serial := int(GameState.match_serial)
	var initial_actors := _get_actors(main)
	var player_names := _team_names(initial_actors, starting_team)
	var opponent_names := _team_names(initial_actors, _opponent(starting_team))
	if player_names.is_empty() or opponent_names.is_empty():
		await _cleanup_main(main)
		return
	var tracked_player := player_names[0]
	var tracked_opponent := opponent_names[0]
	GameState.record_scoreboard_damage(tracked_player, starting_team, {
		"hit": true,
		"killed": true,
		"target_name": tracked_opponent,
		"target_team": _opponent(starting_team),
	})

	for round_number in range(1, 7):
		_settle_current_round(String(GameState.player_team), round_number, "%s terminal setup %d" % [prefix, round_number])
		_trigger_round_restart()
		await _await_reload_frames()

	var terminal_old_actors := _get_actors(main)
	_dirty_competitive_state(main, terminal_old_actors, "%s terminal fixture" % prefix)
	var terminal_old_refs := _weak_refs(terminal_old_actors)
	var terminal_old_ids := _actor_ids(terminal_old_actors)
	var terminal_round_serial := _settle_current_round(String(GameState.player_team), 7, "%s terminal" % prefix)
	var first_terminal := GameState.get_match_snapshot() as Dictionary
	_assert_equal(String(first_terminal.get("phase", "")), "complete", "%s: seventh player-squad win should finish regulation" % prefix)
	_assert_equal(int(first_terminal.get("player_score", -1)), 7, "%s: completed first match should retain its score" % prefix)
	_assert_equal((first_terminal.get("rounds", []) as Array).size(), 7, "%s: completed first match should retain seven records" % prefix)
	_trigger_round_restart()
	await _await_reload_frames()
	var first_record_path := String(main.get("_completed_match_record_path"))
	_assert_true(not first_record_path.is_empty() and FileAccess.file_exists(first_record_path), "%s: first match should expose its persisted record" % prefix)

	var transient_refs: Array[WeakRef] = []
	for group_name in ["weapon_pickups", "grenade_projectiles", "smoke_volumes"]:
		transient_refs.append(_add_transient_fixture(main, group_name))
	main.call("_on_team_selected", next_start_team)
	main.call("_on_start_pressed")

	_assert_equal(int(main.get_instance_id()), main_id, "%s: new match should reuse the same Main instance" % prefix)
	_assert_equal(int(GameState.match_serial), first_match_serial + 1, "%s: new match should advance only match serial" % prefix)
	_assert_equal(String(GameState.initial_player_team), next_start_team, "%s: new match should honor the opposite selected side" % prefix)
	_assert_equal(String(GameState.player_team), next_start_team, "%s: opposite-side new match should start on CT" % prefix)
	_assert_equal(String(GameState.match_phase), "first_half", "%s: new match should return to first half" % prefix)
	_assert_equal(GameState.player_squad_score, 0, "%s: new match should reset player score" % prefix)
	_assert_equal(GameState.opponent_squad_score, 0, "%s: new match should reset opponent score" % prefix)
	_assert_equal(GameState.match_rounds.size(), 0, "%s: new match should clear prior round records" % prefix)
	_assert_equal(GameState.regulation_rounds_played, 0, "%s: new match should clear regulation progress" % prefix)
	_assert_equal(GameState.overtime_rounds_played, 0, "%s: new match should clear overtime progress" % prefix)
	_assert_equal(GameState.settled_round_serial, -1, "%s: new match should clear settled-round authority" % prefix)
	_assert_true(int(GameState.active_round_serial) > terminal_round_serial, "%s: new match should register a fresh active round serial" % prefix)
	_assert_equal(int(GameState.active_round_serial), int(RoundManager.round_serial), "%s: Main and RoundManager should agree on the fresh serial" % prefix)
	_assert_equal(String(main.get("_completed_match_record_path")), "", "%s: new match should not retain the previous export path" % prefix)
	_assert_player_spawn(main, next_start_team, true, "%s fresh start" % prefix)

	var fresh_actors := _get_actors(main)
	_assert_roster(fresh_actors, next_start_team, "%s fresh start" % prefix)
	_assert_no_reused_actor_instances(fresh_actors, terminal_old_ids, "%s fresh start" % prefix)
	_assert_refs_detached(terminal_old_refs, "%s fresh start" % prefix)
	_assert_player_hard_reset(main, "%s fresh start" % prefix)
	_assert_bot_hard_reset(fresh_actors, "%s fresh start" % prefix)
	_assert_scoreboard_fully_reset(tracked_player, tracked_opponent, "%s fresh start" % prefix)
	_assert_c4_assignment(main, fresh_actors, next_start_team, "%s fresh start" % prefix)

	await _await_reload_frames()
	_assert_refs_freed(terminal_old_refs, "%s fresh start" % prefix)
	_assert_refs_freed(transient_refs, "%s transient cleanup" % prefix)
	_assert_no_transient_fixtures("%s transient cleanup" % prefix)
	await _cleanup_main(main)


func _test_duplicate_end_restart_idempotence() -> void:
	var prefix := "duplicate end/restart"
	var main := await _instantiate_main("T")
	if main == null:
		_failures.append("%s: Main.tscn should instantiate" % prefix)
		return

	var first_serial := int(RoundManager.round_serial)
	RoundManager.set_live()
	RoundManager.end_round("T", "ELIMINATION")
	RoundManager.end_round("CT", "TIME")
	var once_settled := GameState.get_match_snapshot() as Dictionary
	_assert_equal((once_settled.get("rounds", []) as Array).size(), 1, "%s: duplicate end should append one record" % prefix)
	_assert_equal(int(once_settled.get("player_score", -1)), 1, "%s: duplicate end should award one point" % prefix)
	_assert_equal(int(GameState.settled_round_serial), first_serial, "%s: duplicate end should settle one serial" % prefix)
	_assert_equal(String(RoundManager.round_winner), "T", "%s: duplicate end should not replace the first winner" % prefix)

	_trigger_round_restart()
	var advanced_serial := int(RoundManager.round_serial)
	var once_reloaded_ids := _actor_ids(_get_actors(main))
	_assert_equal(advanced_serial, first_serial + 1, "%s: first restart should advance exactly one round" % prefix)
	RoundManager.restart_requested.emit()
	_assert_equal(int(RoundManager.round_serial), advanced_serial, "%s: duplicate restart should not advance serial again" % prefix)
	_assert_equal(_actor_ids(_get_actors(main)), once_reloaded_ids, "%s: duplicate restart should not rebuild or duplicate actors" % prefix)
	_assert_equal(_get_actors(main).size(), 5, "%s: duplicate restart should retain exactly five AI" % prefix)
	_assert_equal(GameState.match_rounds.size(), 1, "%s: duplicate restart should not resettle the round" % prefix)
	await _await_reload_frames()

	for round_number in range(2, 7):
		_settle_current_round(String(GameState.player_team), round_number, "%s setup %d" % [prefix, round_number])
		_trigger_round_restart()
		await _await_reload_frames()

	var files_before := _match_record_files()
	var terminal_actor_ids := _actor_ids(_get_actors(main))
	var terminal_serial := int(RoundManager.round_serial)
	RoundManager.set_live()
	var terminal_winner := String(GameState.player_team)
	RoundManager.end_round(terminal_winner, "ELIMINATION")
	RoundManager.end_round(_opponent(terminal_winner), "TIME")
	var terminal_snapshot := GameState.get_match_snapshot() as Dictionary
	_assert_equal((terminal_snapshot.get("rounds", []) as Array).size(), 7, "%s: terminal duplicate end should append only round seven" % prefix)
	_assert_equal(int(terminal_snapshot.get("player_score", -1)), 7, "%s: terminal duplicate end should award only one point" % prefix)
	_assert_equal(String(terminal_snapshot.get("phase", "")), "complete", "%s: first terminal end should finish the match" % prefix)
	_assert_equal(int(GameState.settled_round_serial), terminal_serial, "%s: terminal serial should settle once" % prefix)

	_trigger_round_restart()
	var export_path := String(main.get("_completed_match_record_path"))
	var files_after_first := _match_record_files()
	var actors_after_first := _actor_ids(_get_actors(main))
	_assert_true(not export_path.is_empty() and FileAccess.file_exists(export_path), "%s: first terminal restart should export a record" % prefix)
	_assert_equal(_new_file_count(files_before, files_after_first), 1, "%s: first terminal restart should create one export" % prefix)
	_assert_equal(actors_after_first, terminal_actor_ids, "%s: terminal summary should retain one existing actor roster" % prefix)
	RoundManager.restart_requested.emit()
	var files_after_duplicate := _match_record_files()
	_assert_equal(String(main.get("_completed_match_record_path")), export_path, "%s: duplicate terminal restart should reuse the first export path" % prefix)
	_assert_equal(files_after_duplicate, files_after_first, "%s: duplicate terminal restart should not export again" % prefix)
	_assert_equal(_actor_ids(_get_actors(main)), actors_after_first, "%s: duplicate terminal restart should not duplicate actors" % prefix)
	_assert_equal(_get_actors(main).size(), 5, "%s: terminal duplicate restart should retain exactly five AI" % prefix)
	_assert_equal(int(RoundManager.round_serial), terminal_serial, "%s: terminal duplicate restart should not advance round serial" % prefix)
	_assert_equal(GameState.match_rounds.size(), 7, "%s: terminal duplicate restart should retain seven records" % prefix)
	await _await_reload_frames()
	_assert_equal(_match_record_files(), files_after_first, "%s: deferred persistence should remain idempotent" % prefix)
	await _cleanup_main(main)


func _test_real_scene_halftime(starting_team: String) -> void:
	var prefix := "%s start" % starting_team
	var main := await _instantiate_main(starting_team)
	if main == null:
		_failures.append("%s: Main.tscn should instantiate" % prefix)
		return

	var level := main.get_node("Level") as Node3D
	var level_data := level.call("get_current_level_data") as Dictionary
	_assert_equal(String(level_data.get("id", "")), "gatehouse", "%s: Main should load Gatehouse" % prefix)
	_assert_equal(String(GameState.current_level_id), "gatehouse", "%s: GameState should track Gatehouse" % prefix)
	_assert_equal(String(GameState.player_team), starting_team, "%s: selected side should start the real match" % prefix)
	_assert_equal(String(GameState.match_phase), "first_half", "%s: start should enter first half" % prefix)
	_assert_equal(String(RoundManager.get_state_name()), "Freeze", "%s: real start should enter freeze time" % prefix)
	_assert_player_spawn(main, starting_team, false, "%s initial" % prefix)

	var initial_actors := _get_actors(main)
	_assert_roster(initial_actors, starting_team, "%s initial" % prefix)
	_assert_c4_assignment(main, initial_actors, starting_team, "%s initial" % prefix)
	var player_squad_names := _team_names(initial_actors, starting_team)
	var opponent_squad_names := _team_names(initial_actors, _opponent(starting_team))
	if player_squad_names.is_empty() or opponent_squad_names.is_empty():
		await _cleanup_main(main)
		return

	var tracked_player_name := player_squad_names[0]
	var tracked_opponent_name := opponent_squad_names[0]
	GameState.record_scoreboard_damage(tracked_player_name, starting_team, {
		"hit": true,
		"killed": true,
		"target_name": tracked_opponent_name,
		"target_team": _opponent(starting_team),
	})

	var serials: Array[int] = []
	var old_actor_refs: Array[WeakRef] = []
	var old_actor_ids: Array[int] = []
	var old_visual_id: int = 0
	for round_index in range(6):
		_assert_equal(String(RoundManager.get_state_name()), "Freeze", "%s round %d should begin in freeze" % [prefix, round_index + 1])
		var round_serial := int(RoundManager.round_serial)
		_assert_true(round_serial > 0, "%s round %d should expose a positive serial" % [prefix, round_index + 1])
		_assert_true(not serials.has(round_serial), "%s round serials should be unique" % prefix)
		serials.append(round_serial)
		_assert_equal(int(GameState.active_round_serial), round_serial, "%s round %d serial should be registered before settlement" % [prefix, round_index + 1])

		if round_index == 5:
			_dirty_competitive_state(main, _get_actors(main), "%s pre-halftime" % prefix)
			var visual_root := level.get_node("VisualRoot")
			if visual_root.get_child_count() > 0:
				old_visual_id = int(visual_root.get_child(0).get_instance_id())
			else:
				_failures.append("%s: Gatehouse visual should exist before halftime reload" % prefix)
			for actor in _get_actors(main):
				old_actor_refs.append(weakref(actor))
				old_actor_ids.append(int(actor.get_instance_id()))

		var round_team := String(GameState.player_team)
		var winner := round_team if round_index % 2 == 0 else _opponent(round_team)
		RoundManager.set_live()
		RoundManager.end_round(winner, "ELIMINATION")
		_assert_equal(String(RoundManager.get_state_name()), "Round End", "%s round %d should legally reach round end" % [prefix, round_index + 1])
		var match_snapshot := GameState.get_match_snapshot() as Dictionary
		var records := match_snapshot.get("rounds", []) as Array
		_assert_equal(records.size(), round_index + 1, "%s round %d should append exactly one match record" % [prefix, round_index + 1])
		if not records.is_empty():
			var last_record := records.back() as Dictionary
			_assert_equal(int(last_record.get("round_serial", -1)), round_serial, "%s round %d should retain its legal serial" % [prefix, round_index + 1])
			_assert_equal(String(last_record.get("player_team", "")), round_team, "%s round %d should record the side used for settlement" % [prefix, round_index + 1])

		if round_index < 5:
			_trigger_round_restart()
			await _await_reload_frames()
			_assert_equal(String(RoundManager.get_state_name()), "Freeze", "%s round %d should reload through Main" % [prefix, round_index + 2])
			_assert_true(int(RoundManager.round_serial) > round_serial, "%s Main reload should advance the round serial" % prefix)

	var halftime_snapshot := GameState.get_match_snapshot() as Dictionary
	var swapped_team := _opponent(starting_team)
	_assert_equal(String(halftime_snapshot.get("phase", "")), "second_half", "%s: six settlements should enter second half" % prefix)
	_assert_equal(int(halftime_snapshot.get("regulation_rounds", -1)), 6, "%s: exactly six regulation rounds should settle" % prefix)
	_assert_equal(int(halftime_snapshot.get("player_score", -1)), 3, "%s: stable player squad score should survive halftime" % prefix)
	_assert_equal(int(halftime_snapshot.get("opponent_score", -1)), 3, "%s: stable opponent squad score should survive halftime" % prefix)
	_assert_equal(String(GameState.player_team), swapped_team, "%s: player side should swap after the sixth settlement" % prefix)
	var halftime_records := halftime_snapshot.get("rounds", []) as Array
	if halftime_records.size() == 6:
		_assert_true(bool((halftime_records[5] as Dictionary).get("side_swap", false)), "%s: sixth record should carry the side-swap evidence" % prefix)

	_trigger_round_restart()
	_assert_equal(String(RoundManager.get_state_name()), "Freeze", "%s: Main should synchronously rebuild the halftime round" % prefix)
	_assert_equal(String(level.call("get_current_level_data").get("id", "")), "gatehouse", "%s: Main reload should retain Gatehouse" % prefix)
	_assert_player_spawn(main, swapped_team, true, "%s halftime" % prefix)

	var visual_root_after := level.get_node("VisualRoot")
	if old_visual_id != 0 and visual_root_after.get_child_count() > 0:
		_assert_true(int(visual_root_after.get_child(0).get_instance_id()) != old_visual_id, "%s: Main should replace the Gatehouse visual instance at halftime" % prefix)

	var halftime_actors := _get_actors(main)
	_assert_roster(halftime_actors, swapped_team, "%s halftime" % prefix)
	_assert_equal(_team_names(halftime_actors, swapped_team), player_squad_names, "%s: stable player-squad AI identities should follow the side swap" % prefix)
	_assert_equal(_team_names(halftime_actors, starting_team), opponent_squad_names, "%s: stable opponent AI identities should follow the side swap" % prefix)
	_assert_no_reused_actor_instances(halftime_actors, old_actor_ids, "%s halftime" % prefix)
	for old_ref in old_actor_refs:
		var old_actor := old_ref.get_ref() as Node
		_assert_true(old_actor == null or old_actor.get_parent() == null, "%s: old AI nodes should be detached during Main reload" % prefix)

	_assert_player_hard_reset(main, "%s halftime" % prefix)
	_assert_bot_hard_reset(halftime_actors, "%s halftime" % prefix)
	_assert_scoreboard_identity(tracked_player_name, tracked_opponent_name, swapped_team, "%s halftime" % prefix)
	_assert_c4_assignment(main, halftime_actors, swapped_team, "%s halftime" % prefix)

	await _await_reload_frames()
	for old_ref in old_actor_refs:
		_assert_true(old_ref.get_ref() == null, "%s: detached AI nodes should be freed after the reload frame" % prefix)
	_assert_player_spawn(main, swapped_team, false, "%s halftime settled" % prefix)
	await _cleanup_main(main)


func _instantiate_main(starting_team: String) -> Node3D:
	GameState.reset_runtime_state()
	GameState.player_team = starting_team
	GameState.set_menu_state(true)
	GameState.set_game_started(false)
	RoundManager.set_warmup()
	var main := MAIN_SCENE.instantiate() as Node3D
	if main == null:
		return null
	add_child(main)
	await _await_reload_frames()
	main.call("_on_team_selected", starting_team)
	await get_tree().process_frame
	main.call("_on_start_pressed")
	await _await_reload_frames()
	return main


func _cleanup_main(main: Node3D) -> void:
	if is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _await_reload_frames() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _trigger_round_restart() -> void:
	RoundManager.call("_process", float(RoundManager.round_end_duration) + 0.1)


func _settle_current_round(winner: String, expected_record_count: int, prefix: String) -> int:
	_assert_equal(String(RoundManager.get_state_name()), "Freeze", "%s: round should begin in freeze" % prefix)
	var serial := int(RoundManager.round_serial)
	_assert_true(serial > 0, "%s: active round should expose a positive serial" % prefix)
	_assert_equal(int(GameState.active_round_serial), serial, "%s: GameState should register the active serial" % prefix)
	RoundManager.set_live()
	RoundManager.end_round(winner, "ELIMINATION")
	_assert_equal(String(RoundManager.get_state_name()), "Round End", "%s: legal settlement should reach round end" % prefix)
	var records := GameState.match_rounds
	_assert_equal(records.size(), expected_record_count, "%s: settlement should append exactly one record" % prefix)
	if not records.is_empty():
		_assert_equal(int((records.back() as Dictionary).get("round_serial", -1)), serial, "%s: record should retain the active serial" % prefix)
	return serial


func _actor_ids(actors: Array[CharacterBody3D]) -> Array[int]:
	var ids: Array[int] = []
	for actor in actors:
		ids.append(int(actor.get_instance_id()))
	ids.sort()
	return ids


func _weak_refs(actors: Array[CharacterBody3D]) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for actor in actors:
		refs.append(weakref(actor))
	return refs


func _assert_refs_detached(refs: Array[WeakRef], prefix: String) -> void:
	for old_ref in refs:
		var old_node := old_ref.get_ref() as Node
		_assert_true(old_node == null or old_node.get_parent() == null, "%s: replaced actor should detach synchronously" % prefix)


func _assert_refs_freed(refs: Array[WeakRef], prefix: String) -> void:
	for old_ref in refs:
		_assert_true(old_ref.get_ref() == null, "%s: queued transient should be freed after reload frames" % prefix)


func _add_transient_fixture(main: Node3D, group_name: String) -> WeakRef:
	var fixture := Node3D.new()
	fixture.name = "GatehouseIsolationTransient_%s" % group_name
	main.add_child(fixture)
	fixture.add_to_group(group_name)
	return weakref(fixture)


func _assert_no_transient_fixtures(prefix: String) -> void:
	for group_name in ["weapon_pickups", "grenade_projectiles", "smoke_volumes"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node) and String(node.name).begins_with("GatehouseIsolationTransient_"):
				_failures.append("%s: %s should not retain the prior match fixture" % [prefix, group_name])


func _assert_scoreboard_fully_reset(tracked_player: String, tracked_opponent: String, prefix: String) -> void:
	_assert_true(GameState.unit_scoreboard.has(tracked_player), "%s: reused stable identity should be present in the fresh roster" % prefix)
	_assert_true(GameState.unit_scoreboard.has(tracked_opponent), "%s: reused opponent identity should be present in the fresh roster" % prefix)
	for record_variant in GameState.unit_scoreboard.values():
		var record := record_variant as Dictionary
		_assert_equal(int(record.get("kills", -1)), 0, "%s: fresh scoreboard kills should reset" % prefix)
		_assert_equal(int(record.get("deaths", -1)), 0, "%s: fresh scoreboard deaths should reset" % prefix)
		_assert_equal(int(record.get("hits", -1)), 0, "%s: fresh scoreboard hits should reset" % prefix)


func _match_record_files() -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open("user://match-records")
	if directory == null:
		return files
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			files.append("user://match-records/%s" % file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files


func _new_file_count(before: Array[String], after: Array[String]) -> int:
	var count := 0
	for file_path in after:
		if not before.has(file_path):
			count += 1
	return count


func _get_actors(main: Node3D) -> Array[CharacterBody3D]:
	var actors: Array[CharacterBody3D] = []
	var sandbox := main.get_node("CombatSandbox")
	for child in sandbox.get_children():
		if child is CharacterBody3D and child.has_method("get_combat_snapshot"):
			actors.append(child as CharacterBody3D)
	return actors


func _team_names(actors: Array[CharacterBody3D], team: String) -> Array[String]:
	var names: Array[String] = []
	for actor in actors:
		var snapshot := actor.call("get_combat_snapshot") as Dictionary
		if String(snapshot.get("team", "")) == team:
			names.append(String(snapshot.get("name", "")))
	names.sort()
	return names


func _assert_roster(actors: Array[CharacterBody3D], local_team: String, prefix: String) -> void:
	var friendly := 0
	var enemy := 0
	var unique_names: Dictionary = {}
	for actor in actors:
		var snapshot := actor.call("get_combat_snapshot") as Dictionary
		var actor_team := String(snapshot.get("team", ""))
		if actor_team == local_team:
			friendly += 1
		else:
			enemy += 1
		unique_names[String(snapshot.get("name", ""))] = true
	_assert_equal(actors.size(), 5, "%s: real Gatehouse should spawn five AI" % prefix)
	_assert_equal(friendly, 2, "%s: player squad should have two AI teammates" % prefix)
	_assert_equal(enemy, 3, "%s: opposing squad should have three AI enemies" % prefix)
	_assert_equal(unique_names.size(), 5, "%s: all five AI identities should be unique" % prefix)
	_assert_equal(GameState.friendly_alive, 3, "%s: local player plus two allies should report 3 alive" % prefix)
	_assert_equal(GameState.enemy_alive, 3, "%s: opposing squad should report 3 alive" % prefix)


func _assert_player_spawn(main: Node3D, team: String, exact_y: bool, prefix: String) -> void:
	var level := main.get_node("Level")
	var level_data := level.call("get_current_level_data") as Dictionary
	var spawn_groups := level_data.get("spawnGroups", {}) as Dictionary
	var team_spawns := spawn_groups.get(team, []) as Array
	if team_spawns.is_empty():
		_failures.append("%s: Gatehouse should author %s spawn points" % [prefix, team])
		return
	var middle_index := floori(float(team_spawns.size()) / 2.0)
	var authored_spawn := team_spawns[middle_index] as Array
	if authored_spawn.size() < 2:
		_failures.append("%s: authored %s spawn should contain x/z" % [prefix, team])
		return
	var expected := Vector3(float(authored_spawn[0]), float(level_data.get("startHeight", 1.05)), float(authored_spawn[1]))
	var expected_yaw := deg_to_rad(180.0 if team == "T" else 0.0)
	var player := main.get_node("Player") as CharacterBody3D
	_assert_vec3_close(GameState.player_spawn, expected, 0.001, "%s: GameState should use the authored team spawn" % prefix)
	if exact_y:
		_assert_vec3_close(player.global_position, expected, 0.001, "%s: Main reload should reset the player to the authored spawn" % prefix)
	else:
		_assert_vec2_close(Vector2(player.global_position.x, player.global_position.z), Vector2(expected.x, expected.z), 0.06, "%s: live player should remain on the authored team spawn" % prefix)
		_assert_true(player.global_position.y > 0.4 and player.global_position.y <= expected.y + 0.06, "%s: player spawn height should settle onto Gatehouse floor" % prefix)
	_assert_angle_close(GameState.player_spawn_yaw_radians, expected_yaw, 0.001, "%s: GameState should expose the authored team yaw" % prefix)
	_assert_angle_close(player.rotation.y, expected_yaw, 0.001, "%s: actual player should face the authored team direction" % prefix)


func _dirty_competitive_state(main: Node3D, actors: Array[CharacterBody3D], prefix: String) -> void:
	GameState.player_money = 10000
	main.call("_purchase_item", "rifle")
	main.call("_purchase_item", "armor_helmet")
	GameState.player_defuse_kit = true
	var weapon_system := main.get_node("WeaponSystem")
	var weapon_snapshot := weapon_system.call("get_runtime_snapshot") as Dictionary
	var view_snapshot := main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel").call("get_debug_snapshot") as Dictionary
	_assert_equal(int(weapon_snapshot.get("weapon_slot", -1)), 0, "%s: fixture should own/equip a rifle before the hard reset" % prefix)
	_assert_equal(int(view_snapshot.get("weapon_slot", -1)), 0, "%s: fixture view model should show the rifle before the hard reset" % prefix)
	_assert_true(GameState.player_money != 800 and GameState.player_armor == 100 and GameState.player_defuse_kit, "%s: fixture should expose non-default player economy/equipment" % prefix)
	for actor in actors:
		actor.set("equipped_weapon_id", "rifle")
		actor.set("max_armor", 100)
		actor.set("current_armor", 100)
		actor.set("has_helmet", true)
		actor.set("has_defuse_kit", true)
		var brain := actor.get_node("TacticalBotBrain")
		brain.set("ai_money", 9000)
		brain.set("has_defuse_kit", true)
		var snapshot := actor.call("get_combat_snapshot") as Dictionary
		_assert_equal(String(snapshot.get("weapon", "")), "rifle", "%s: fixture bot should carry a rifle before reset" % prefix)
		_assert_equal(int(snapshot.get("armor", -1)), 100, "%s: fixture bot should carry armor before reset" % prefix)
		_assert_equal(int((snapshot.get("ai", {}) as Dictionary).get("money", -1)), 9000, "%s: fixture bot should carry non-default money before reset" % prefix)


func _assert_player_hard_reset(main: Node3D, prefix: String) -> void:
	_assert_equal(GameState.player_money, 800, "%s: halftime should reset player money to $800" % prefix)
	_assert_equal(GameState.player_armor, 0, "%s: halftime should remove player armor" % prefix)
	_assert_true(not GameState.player_helmet, "%s: halftime should remove player helmet" % prefix)
	_assert_true(not GameState.player_defuse_kit, "%s: halftime should remove player defuse kit" % prefix)
	var weapon_system := main.get_node("WeaponSystem")
	var weapon_snapshot := weapon_system.call("get_runtime_snapshot") as Dictionary
	_assert_equal(int(weapon_snapshot.get("weapon_slot", -1)), 1, "%s: WeaponSystem should return to the default pistol slot" % prefix)
	_assert_true(not bool(weapon_system.call("is_slot_owned", 0)), "%s: halftime hard reset should remove the purchased rifle" % prefix)
	var view_snapshot := main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel").call("get_debug_snapshot") as Dictionary
	_assert_equal(int(view_snapshot.get("weapon_slot", -1)), 1, "%s: first-person view model should return to the pistol slot" % prefix)
	_assert_true(bool(view_snapshot.get("pistol_visible", false)) and not bool(view_snapshot.get("rifle_visible", true)), "%s: first-person hard-reset model visibility should match the pistol" % prefix)


func _assert_bot_hard_reset(actors: Array[CharacterBody3D], prefix: String) -> void:
	for actor in actors:
		var snapshot := actor.call("get_combat_snapshot") as Dictionary
		var ai := snapshot.get("ai", {}) as Dictionary
		_assert_equal(String(snapshot.get("weapon", "")), "pistol", "%s: bot snapshot should reset to pistol" % prefix)
		_assert_equal(int(snapshot.get("armor", -1)), 0, "%s: bot snapshot should reset to zero armor" % prefix)
		_assert_true(not bool(snapshot.get("helmet", true)), "%s: bot snapshot should reset helmet" % prefix)
		_assert_true(not bool(snapshot.get("defuse_kit", true)), "%s: bot snapshot should reset defuse kit" % prefix)
		_assert_equal(int(ai.get("money", -1)), 800, "%s: bot snapshot should reset to $800" % prefix)


func _assert_scoreboard_identity(player_name: String, opponent_name: String, player_team: String, prefix: String) -> void:
	var player_record := GameState.unit_scoreboard.get(player_name, {}) as Dictionary
	var opponent_record := GameState.unit_scoreboard.get(opponent_name, {}) as Dictionary
	_assert_equal(int(player_record.get("kills", 0)), 1, "%s: stable player AI identity should retain its kill" % prefix)
	_assert_equal(int(player_record.get("hits", 0)), 1, "%s: stable player AI identity should retain its hit" % prefix)
	_assert_equal(String(player_record.get("team", "")), player_team, "%s: stable player AI identity should adopt the swapped side" % prefix)
	_assert_equal(int(opponent_record.get("deaths", 0)), 1, "%s: stable opponent AI identity should retain its death" % prefix)
	_assert_equal(String(opponent_record.get("team", "")), _opponent(player_team), "%s: stable opponent AI identity should adopt the swapped side" % prefix)


func _assert_c4_assignment(main: Node3D, actors: Array[CharacterBody3D], player_team: String, prefix: String) -> void:
	var c4_nodes := main.find_children("C4Device", "", true, false)
	_assert_equal(c4_nodes.size(), 1, "%s: Main should contain exactly one C4 device" % prefix)
	var c4 := main.get_node_or_null("C4Device")
	if c4 == null:
		return
	_assert_equal(String(c4.get("device_state")), "carried", "%s: fresh round C4 should be carried" % prefix)
	_assert_equal(String(c4.get("carrier_team")), "T", "%s: fresh round C4 should belong to the current T side" % prefix)
	_assert_true(bool(RoundManager.bomb_carried), "%s: round authority should agree that C4 is carried" % prefix)
	var ai_carriers := 0
	for actor in actors:
		var snapshot := actor.call("get_combat_snapshot") as Dictionary
		var objective := snapshot.get("objective", {}) as Dictionary
		if bool(objective.get("carrier", false)):
			ai_carriers += 1
			_assert_equal(String(snapshot.get("team", "")), "T", "%s: any AI C4 carrier must be on T" % prefix)
	var logical_holders := ai_carriers + (1 if player_team == "T" else 0)
	_assert_equal(logical_holders, 1, "%s: exactly one current T combatant should own C4" % prefix)
	_assert_equal(ai_carriers, 0 if player_team == "T" else 1, "%s: C4 carrier role should follow the player's current side" % prefix)


func _assert_no_reused_actor_instances(actors: Array[CharacterBody3D], old_ids: Array[int], prefix: String) -> void:
	for actor in actors:
		_assert_true(not old_ids.has(int(actor.get_instance_id())), "%s: halftime should create new AI instances" % prefix)


func _opponent(team: String) -> String:
	return "CT" if team == "T" else "T"


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])


func _assert_vec3_close(actual: Vector3, expected: Vector3, epsilon: float, message: String) -> void:
	if actual.distance_to(expected) > epsilon:
		_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])


func _assert_vec2_close(actual: Vector2, expected: Vector2, epsilon: float, message: String) -> void:
	if actual.distance_to(expected) > epsilon:
		_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])


func _assert_angle_close(actual: float, expected: float, epsilon: float, message: String) -> void:
	if absf(wrapf(actual - expected, -PI, PI)) > epsilon:
		_failures.append("%s | expected=%s actual=%s epsilon=%s" % [message, str(expected), str(actual), str(epsilon)])
