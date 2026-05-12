extends CanvasLayer

@export var marker_duration: float = 0.12
@export var message_duration: float = 0.55
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var kill_color: Color = Color(1.0, 0.78, 0.24, 1.0)
@export var neutral_color: Color = Color(0.85, 0.85, 0.85, 1.0)

@onready var marker_label: Label = $CenterMarker
@onready var message_label: Label = $BottomMessage

var _marker_timer: float = 0.0
var _message_timer: float = 0.0

func _ready() -> void:
	marker_label.visible = false
	message_label.visible = false

func _process(delta: float) -> void:
	if _marker_timer > 0.0:
		_marker_timer = maxf(0.0, _marker_timer - delta)
		if _marker_timer == 0.0:
			marker_label.visible = false

	if _message_timer > 0.0:
		_message_timer = maxf(0.0, _message_timer - delta)
		if _message_timer == 0.0:
			message_label.visible = false

func show_shot_feedback(result: Dictionary) -> void:
	if not bool(result.get("hit", false)):
		return

	var damage_result: Dictionary = result.get("damage_result", {}) as Dictionary
	if damage_result.is_empty() or not bool(damage_result.get("hit", false)):
		_show_message("\u547d\u4e2d\u5730\u5f62", neutral_color)
		return

	var killed: bool = bool(damage_result.get("killed", false))
	var remaining_health: int = int(damage_result.get("remaining_health", 0))
	var marker_color: Color = kill_color if killed else hit_color
	marker_label.modulate = marker_color
	marker_label.visible = true
	_marker_timer = marker_duration

	if killed:
		_show_message("\u51fb\u5012\u76ee\u6807", kill_color)
	else:
		_show_message("\u547d\u4e2d  \u5269\u4f59HP %d" % remaining_health, hit_color)

func _show_message(text_value: String, color_value: Color) -> void:
	message_label.text = text_value
	message_label.modulate = color_value
	message_label.visible = true
	_message_timer = message_duration
