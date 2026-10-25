extends PanelContainer

const Style = preload("res://scripts/ui/TacticalMenuStyle.gd")
const STAGES := ["map", "scene", "visual", "rules", "team"]
const TITLES := ["准备地图", "布置场景", "载入画面", "检查对局", "准备队伍"]
const DETAILS := [
	"首次进入地图可能需要较长时间，请稍候。", "正在布置地图场景，请稍候。", "正在载入地图画面，请稍候。", "正在检查本场对局数据，请稍候。", "正在准备队友和对手，即将进入对局。"
]

var state := "idle"
var stage := ""
var heading: Label
var detail: Label
var _steps: HBoxContainer


func _ready() -> void:
	name = "LoadingStatus"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Style.box(Style.PANEL))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	add_child(stack)
	_steps = HBoxContainer.new()
	_steps.add_theme_constant_override("separation", 5)
	stack.add_child(_steps)
	for key in STAGES:
		var marker := ColorRect.new()
		marker.name = key
		marker.custom_minimum_size.y = 3
		marker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_steps.add_child(marker)
	heading = Style.label("", 20)
	stack.add_child(heading)
	detail = Style.label("", 15, Style.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(detail)
	clear()


func clear() -> void:
	state = "idle"
	stage = ""
	hide()


func update_stage(key: String, completed: int = 0, total: int = 0) -> void:
	var index := STAGES.find(key)
	if index < 0:
		return
	state = "loading"
	stage = key
	heading.text = TITLES[index]
	detail.text = DETAILS[index]
	if total > 0:
		detail.text = "已完成 %d / %d" % [clampi(completed, 0, total), total]
	_steps.show()
	for position in range(_steps.get_child_count()):
		_steps.get_child(position).color = (
			Style.TEXT if position == index else (Style.BRASS if position < index else Style.INK)
		)
	add_theme_stylebox_override("panel", Style.box(Style.PANEL))
	show()


func show_failure(reason: String) -> void:
	state = "failed"
	stage = ""
	heading.text = "未能开始对局"
	detail.text = (
		"地图对局数据不匹配。\n请恢复完整试玩文件，再重试或换图。" if reason == "layout" else "所选地图未能载入。\n请确认试玩文件完整，再重试或换图。"
	)
	_steps.hide()
	add_theme_stylebox_override("panel", Style.box(Style.PANEL, Color("c79980")))
	show()
