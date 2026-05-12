extends Node

enum RoundState {
	WARMUP,
	LIVE,
	PAUSED_MENU
}

var state: RoundState = RoundState.WARMUP

func set_warmup() -> void:
	state = RoundState.WARMUP

func set_live() -> void:
	state = RoundState.LIVE

func set_paused_menu() -> void:
	state = RoundState.PAUSED_MENU

func get_state_name() -> String:
	match state:
		RoundState.WARMUP:
			return "Warmup"
		RoundState.LIVE:
			return "Live"
		RoundState.PAUSED_MENU:
			return "Paused/Menu"
		_:
			return "Unknown"

func get_state_label() -> String:
	match state:
		RoundState.WARMUP:
			return "\u70ed\u8eab/\u83dc\u5355"
		RoundState.LIVE:
			return "\u8fdb\u884c\u4e2d"
		RoundState.PAUSED_MENU:
			return "\u6682\u505c/\u83dc\u5355"
		_:
			return "\u672a\u77e5"
