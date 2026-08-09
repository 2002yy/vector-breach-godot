extends Node

const CombatSandboxScript = preload("res://scripts/combat/CombatSandbox.gd")

var _failures: PackedStringArray = []
var _passes := 0
var _serial := 0

func _ready() -> void:
	_run_test("halftime_preserves_stable_score_t_start", func(): _test_halftime("T"))
	_run_test("halftime_preserves_stable_score_ct_start", func(): _test_halftime("CT"))
	_run_test("regulation_first_to_seven", _test_regulation_win)
	_run_test("six_six_forces_full_overtime_pair", _test_overtime_pair)
	_run_test("overtime_pair_can_draw", _test_overtime_draw)
	_run_test("duplicate_serial_is_idempotent", _test_duplicate_serial)
	_run_test("new_match_resets_match_authority", _test_new_match_reset)
	_run_test("gatehouse_competitive_roster_is_three_v_three", _test_gatehouse_roster)
	_run_test("match_record_exports_json", _test_export)
	if _failures.is_empty():
		print("[MatchLifecycleTests] PASS (%d tests)" % _passes)
		get_tree().quit(0)
		return
	push_error("[MatchLifecycleTests] FAIL (%d failures)" % _failures.size())
	for failure in _failures:
		push_error("  - %s" % failure)
	get_tree().quit(1)

func _run_test(test_name: String, callable: Callable) -> void:
	var before := _failures.size()
	callable.call()
	if _failures.size() == before:
		_passes += 1
		print("[MatchLifecycleTests] PASS %s" % test_name)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])

func _start(team: String = "T") -> void:
	_serial = 0
	GameState.set_level("gatehouse", "Gatehouse")
	GameState.start_match(team)

func _settle(player_squad_wins: bool) -> Dictionary:
	_serial += 1
	GameState.begin_match_round(_serial)
	var player_side := GameState.player_team
	var winner := player_side if player_squad_wins else ("CT" if player_side == "T" else "T")
	return GameState.complete_round(winner, "ELIMINATION", _serial)

func _play_regulation_six_six() -> void:
	for index in range(12):
		_settle(index % 2 == 0)

func _test_halftime(starting_team: String) -> void:
	_start(starting_team)
	for player_wins in [true, true, true, true, false, false]:
		_settle(player_wins)
	var snapshot := GameState.get_match_snapshot()
	_assert_equal(snapshot.player_score, 4, "player squad score should survive halftime")
	_assert_equal(snapshot.opponent_score, 2, "opponent score should survive halftime")
	_assert_true(snapshot.player_team != starting_team, "player side should swap exactly once")
	_assert_equal(snapshot.ct_score if snapshot.player_team == "CT" else snapshot.t_score, 4, "current player side should display stable player score")
	_assert_equal(snapshot.rounds.size(), 6, "six regulation records should be retained")

func _test_regulation_win() -> void:
	_start("T")
	for player_wins in [true, true, true, true, false, false, true, true, true]:
		_settle(player_wins)
	var snapshot := GameState.get_match_snapshot()
	_assert_equal(snapshot.phase, "complete", "first squad to seven should finish regulation")
	_assert_equal(snapshot.result, "player_win", "stable player squad should win")
	_assert_equal(snapshot.regulation_rounds, 9, "match should stop on round nine")

func _test_overtime_pair() -> void:
	_start("T")
	_play_regulation_six_six()
	_assert_equal(GameState.get_match_snapshot().phase, "overtime", "6:6 should enter overtime")
	var first := _settle(true)
	_assert_true(not first.match_complete, "OT1 must not end at 7:6")
	_assert_true(first.side_swap, "OT1 should swap sides")
	var second := _settle(true)
	_assert_true(second.match_complete, "OT2 should finish the match")
	_assert_equal(GameState.get_match_snapshot().result, "player_win", "8:6 should resolve player win")
	_assert_equal(GameState.get_match_snapshot().rounds.size(), 14, "overtime match should have exactly fourteen records")

func _test_overtime_draw() -> void:
	_start("CT")
	_play_regulation_six_six()
	_settle(true)
	_settle(false)
	var snapshot := GameState.get_match_snapshot()
	_assert_equal(snapshot.result, "draw", "split OT pair should end 7:7 draw")
	_assert_equal(snapshot.overtime_rounds, 2, "only one OT pair should run")

func _test_duplicate_serial() -> void:
	_start()
	_serial = 1
	GameState.begin_match_round(_serial)
	var first := GameState.complete_round("T", "ELIMINATION", _serial)
	var money := GameState.player_money
	var duplicate := GameState.complete_round("CT", "TIME", _serial)
	_assert_true(first.accepted, "first settlement should be accepted")
	_assert_true(not duplicate.accepted and duplicate.duplicate, "duplicate settlement should be rejected")
	_assert_equal(GameState.get_match_snapshot().rounds.size(), 1, "duplicate must not append evidence")
	_assert_equal(GameState.player_money, money, "duplicate must not award economy twice")

func _test_new_match_reset() -> void:
	_start()
	_settle(true)
	GameState.unit_scoreboard["fixture"] = {"kills": 4}
	GameState.start_match("CT")
	var snapshot := GameState.get_match_snapshot()
	_assert_equal(snapshot.player_score, 0, "new match should reset score")
	_assert_equal(snapshot.rounds.size(), 0, "new match should clear evidence")
	_assert_equal(snapshot.scoreboard.size(), 0, "new match should clear unit stats")
	_assert_equal(snapshot.player_team, "CT", "new match should honor selected start side")

func _test_gatehouse_roster() -> void:
	_start("T")
	var data := JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/gatehouse.json")) as Dictionary
	var sandbox := CombatSandboxScript.new()
	var records := sandbox.call("_build_spawn_records", data) as Array
	var friendly := records.filter(func(record): return String(record.team) == GameState.player_team)
	_assert_equal(records.size(), 5, "player should replace one authored bot")
	_assert_equal(friendly.size(), 2, "3v3 should spawn exactly two AI teammates")
	sandbox.free()

func _test_export() -> void:
	_start()
	_settle(true)
	var path := "user://match-lifecycle-test.json"
	_assert_equal(GameState.export_match_record(path), path, "export should return written path")
	var parsed := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	_assert_equal(parsed.rounds.size(), 1, "export should include ordered round evidence")
	_assert_equal(parsed.player_score, 1, "export should match authoritative score")
