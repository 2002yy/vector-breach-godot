extends Node

signal phase_changed(state_name: String)
signal round_ended(winner: String, reason: String)
signal restart_requested

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
	return true

func defuse_bomb() -> bool:
	if state != RoundState.BOMB_PLANTED:
		return false
	end_round("CT", "BOMB DEFUSED")
	return true

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
	}

func _set_state(next_state: RoundState) -> void:
	state = next_state
	phase_changed.emit(get_state_name())
