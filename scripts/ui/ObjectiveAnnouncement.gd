extends PanelContainer

const MenuStyle = preload("res://scripts/ui/TacticalMenuStyle.gd")
const DISPLAY_SECONDS := 5.0

var heading: Label
var detail: Label
var remaining := 0.0
var _seen_serial := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -210
	offset_right = 210
	offset_top = 134
	offset_bottom = 218
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := MenuStyle.box(Color("192024"), MenuStyle.BRASS)
	style.bg_color.a = 0.94
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	heading = _label(24, MenuStyle.TEXT)
	detail = _label(16, MenuStyle.BRASS)
	stack.add_child(heading)
	stack.add_child(detail)
	hide()
	RoundManager.bomb_planted.connect(_on_planted)
	RoundManager.phase_changed.connect(_on_phase)
	CombatEvents.round_cleared.connect(clear)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_planted(site: String, serial: int) -> void:
	if serial == _seen_serial:
		return
	_seen_serial = serial
	heading.text = "C4 安装成功"
	detail.text = "%s 区 · 保护 C4" % site if GameState.player_team == "T" else "%s 区 · 尽快拆除 C4" % site
	remaining = DISPLAY_SECONDS
	show()


func _on_phase(_phase: String) -> void:
	if (
		RoundManager.state
		not in [RoundManager.RoundState.BOMB_PLANTED, RoundManager.RoundState.PAUSED_MENU]
	):
		clear()


func clear() -> void:
	remaining = 0.0
	hide()


func _process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
		return
	if RoundManager.state == RoundManager.RoundState.PAUSED_MENU:
		return
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0:
		hide()
