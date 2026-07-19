extends Node

signal phase_changed(state_name: String)
signal round_ended(winner: String, reason: String)
signal restart_requested
signal objective_interaction_changed(snapshot: Dictionary)
signal bomb_exploded(site_label: String)

enum RoundState {
	WARMUP,
	FREEZE,
	LIVE,
	BOMB_PLANTED,
	ROUND_END,
	PAUSED_MENU,
}

var state: RoundState = RoundState.WARMUP
var _state_before_pause: RoundState = RoundState.WARMUP
var freeze_duration: float = 5.0
var round_duration: float = 115.0
var bomb_duration: float = 40.0
var round_end_duration: float = 5.0
var time_remaining: float = 115.0
var bomb_carried: bool = true
var bomb_site: String = ""
var round_winner: String = ""
var round_reason: String = ""
var interaction_type: String = ""
var interaction_site: String = ""
var interaction_elapsed: float = 0.0
var interaction_duration: float = 0.0

func _process(delta: float) -> void:
	match state:
		RoundState.FREEZE:
			time_remaining = maxf(0.0, time_remaining - delta)
			if time_remaining == 0.0:
				set_live()
		RoundState.LIVE:
			time_remaining = maxf(0.0, time_remaining - delta)
			if time_remaining == 0.0:
				end_round("CT", "TIME")
		RoundState.BOMB_PLANTED:
			time_remaining = maxf(0.0, time_remaining - delta)
			if time_remaining == 0.0:
				end_round("T", "BOMB EXPLODED")
				bomb_exploded.emit(bomb_site)
		RoundState.ROUND_END:
			time_remaining = maxf(0.0, time_remaining - delta)
			if time_remaining == 0.0:
				restart_requested.emit()

func set_warmup() -> void:
	_set_state(RoundState.WARMUP)

func set_live() -> void:
	if state != RoundState.LIVE:
		time_remaining = round_duration
	_set_state(RoundState.LIVE)

func start_round(duration: float = 115.0) -> void:
	round_duration = maxf(1.0, duration)
	time_remaining = freeze_duration
	bomb_carried = true
	bomb_site = ""
	round_winner = ""
	round_reason = ""
	cancel_objective_interaction()
	_set_state(RoundState.FREEZE)

func set_paused_menu() -> void:
	if state != RoundState.PAUSED_MENU:
		_state_before_pause = state
	_set_state(RoundState.PAUSED_MENU)

func resume_round() -> void:
	_set_state(_state_before_pause if _state_before_pause != RoundState.PAUSED_MENU else RoundState.LIVE)

func plant_bomb(site_label: String) -> bool:
	if state != RoundState.LIVE or not bomb_carried:
		return false
	bomb_carried = false
	bomb_site = site_label
	time_remaining = bomb_duration
	_set_state(RoundState.BOMB_PLANTED)
	cancel_objective_interaction()
	return true

func defuse_bomb() -> bool:
	if state != RoundState.BOMB_PLANTED:
		return false
	cancel_objective_interaction()
	end_round("CT", "BOMB DEFUSED")
	return true

func begin_plant(site_label: String, player_team: String) -> bool:
	if state != RoundState.LIVE or not bomb_carried or player_team != "T" or site_label.is_empty():
		return false
	if interaction_type == "plant" and interaction_site == site_label:
		return true
	interaction_type = "plant"
	interaction_site = site_label
	interaction_elapsed = 0.0
	interaction_duration = 3.2
	_emit_objective_interaction()
	return true

func begin_defuse(player_team: String, has_defuse_kit: bool) -> bool:
	if state != RoundState.BOMB_PLANTED or player_team != "CT":
		return false
	if interaction_type == "defuse":
		return true
	interaction_type = "defuse"
	interaction_site = bomb_site
	interaction_elapsed = 0.0
	interaction_duration = 5.0 if has_defuse_kit else 10.0
	_emit_objective_interaction()
	return true

func tick_objective_interaction(delta: float, still_valid: bool) -> bool:
	if interaction_type.is_empty():
		return false
	if not still_valid:
		cancel_objective_interaction()
		return false
	interaction_elapsed = minf(interaction_duration, interaction_elapsed + maxf(delta, 0.0))
	_emit_objective_interaction()
	if interaction_elapsed < interaction_duration:
		return false
	var completed_type := interaction_type
	var completed_site := interaction_site
	if completed_type == "plant":
		return plant_bomb(completed_site)
	if completed_type == "defuse":
		return defuse_bomb()
	return false

func cancel_objective_interaction() -> void:
	if interaction_type.is_empty() and interaction_elapsed == 0.0:
		return
	interaction_type = ""
	interaction_site = ""
	interaction_elapsed = 0.0
	interaction_duration = 0.0
	_emit_objective_interaction()

func is_objective_interacting() -> bool:
	return not interaction_type.is_empty()

func end_round(winner: String, reason: String) -> void:
	if state == RoundState.ROUND_END:
		return
	round_winner = winner
	round_reason = reason
	time_remaining = round_end_duration
	_set_state(RoundState.ROUND_END)
	round_ended.emit(winner, reason)

func can_player_move() -> bool:
	return state in [RoundState.LIVE, RoundState.BOMB_PLANTED]

func can_buy() -> bool:
	return state == RoundState.FREEZE

func get_state_name() -> String:
	match state:
		RoundState.WARMUP:
			return "Warmup"
		RoundState.FREEZE:
			return "Freeze"
		RoundState.LIVE:
			return "Live"
		RoundState.BOMB_PLANTED:
			return "Bomb Planted"
		RoundState.ROUND_END:
			return "Round End"
		RoundState.PAUSED_MENU:
			return "Paused/Menu"
		_:
			return "Unknown"

func get_state_label() -> String:
	match state:
		RoundState.WARMUP:
			return "热身"
		RoundState.FREEZE:
			return "冻结/购买"
		RoundState.LIVE:
			return "回合进行中"
		RoundState.BOMB_PLANTED:
			return "C4已安装"
		RoundState.ROUND_END:
			return "回合结束"
		RoundState.PAUSED_MENU:
			return "暂停/菜单"
		_:
			return "未知"

func get_time_remaining() -> float:
	return time_remaining

func get_time_label() -> String:
	var total_seconds := maxi(0, int(ceil(time_remaining)))
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]

func get_objective_snapshot() -> Dictionary:
	return {
		"bomb_carried": bomb_carried,
		"bomb_planted": state == RoundState.BOMB_PLANTED,
		"bomb_site": bomb_site,
		"round_winner": round_winner,
		"round_reason": round_reason,
		"can_buy": can_buy(),
		"interaction_type": interaction_type,
		"interaction_progress": interaction_elapsed / interaction_duration if interaction_duration > 0.0 else 0.0,
		"interaction_seconds": maxf(0.0, interaction_duration - interaction_elapsed),
	}

func _set_state(next_state: RoundState) -> void:
	state = next_state
	phase_changed.emit(get_state_name())

func _emit_objective_interaction() -> void:
	objective_interaction_changed.emit(get_objective_snapshot())
