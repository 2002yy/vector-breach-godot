extends PanelContainer

const Style = preload("res://scripts/ui/TacticalMenuStyle.gd")
const Guide = preload("res://scripts/ui/PlayerGuide.gd")

var title: Label
var status: Label
var stats: Label
var health: ProgressBar
var roster: HBoxContainer
var controls: Label
var _rows: Array[PanelContainer] = []
var _labels: Array[Label] = []
var _health_labels: Array[Label] = []
var _normal: StyleBoxFlat
var _selected: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -340
	offset_right = 340
	offset_top = -280
	offset_bottom = -100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Style.box(Color("192024eb"), Style.BRASS))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	status = _label(17, Style.BRASS)
	title = _label(24, Style.TEXT)
	stats = _label(19, Style.TEXT)
	health = ProgressBar.new()
	health.custom_minimum_size.y = 4
	health.show_percentage = false
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Style.INK
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Style.BRASS
	health.add_theme_stylebox_override("background", bar_background)
	health.add_theme_stylebox_override("fill", bar_fill)
	roster = HBoxContainer.new()
	roster.add_theme_constant_override("separation", 6)
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_normal = Style.box(Style.INK)
	_selected = Style.box(Color("30342c"), Style.BRASS)
	for box in [_normal, _selected]:
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 5
		box.content_margin_bottom = 5
	for index in range(4):
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := _label(15, Style.MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hp := _label(14, Style.MUTED)
		hp.custom_minimum_size.x = 52
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(label)
		line.add_child(hp)
		row.add_child(line)
		roster.add_child(row)
		_rows.append(row)
		_labels.append(label)
		_health_labels.append(hp)
	controls = _label(14, Style.MUTED)
	controls.text = "1–4 选择队友    左 / 右键切人    空格切换视角    Esc 暂停"
	for node in [status, title, stats, health, roster, controls]:
		stack.add_child(node)
	hide()


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func update_view(watching: Dictionary, context: Dictionary) -> void:
	visible = bool(watching.get("active", false))
	if not visible:
		return
	var has_target := bool(watching.get("has_target", false))
	offset_top = -280 if has_target else -210
	var teammates: Array = watching.get("teammates", [])
	controls.text = (
		"1–4 选择队友    左 / 右键切人    空格切换视角    Esc 暂停"
		if not teammates.is_empty()
		else "Tab 计分板    Esc 暂停"
	)
	var mode := "队友眼位" if bool(watching.get("first_person", false)) else "第三人称"
	title.text = "%s · %s" % [watching.get("name", "队友"), mode] if has_target else "已无存活队友"
	stats.visible = has_target
	health.visible = has_target
	if has_target:
		stats.text = (
			"生命 %d    护甲 %d    %s    %d / %d%s"
			% [
				int(watching.get("health", 0)),
				int(watching.get("armor", 0)),
				Guide.weapon_name(String(watching.get("weapon", ""))),
				int(watching.get("ammo", 0)),
				int(watching.get("reserve", 0)),
				"    携带 C4" if bool(watching.get("c4", false)) else ""
			]
		)
		health.value = int(watching.get("health", 0))
	var bomb: Dictionary = context.get("bomb", {})
	var round_state := String(context.get("round_state", ""))
	var remaining := String(context.get("round_time", ""))
	if round_state == "Round End":
		var complete := String(context.get("match", {}).get("phase", "")) == "complete"
		status.text = "比赛结束 · 即将进入赛果" if complete else "回合结束 · %s 后进入下一回合" % remaining
	elif bool(bomb.get("bomb_planted", false)):
		status.text = "C4 已安装 · %s 区 · %s" % [bomb.get("bomb_site", ""), remaining]
	elif not has_target:
		status.text = "你已阵亡 · 等待回合结算"
	else:
		status.text = "你已阵亡 · 观战队友"
	if teammates.size() == 1 and round_state in ["Live", "Bomb Planted"]:
		status.text = "最后一名队友 · 1 对 %d    %s" % [int(context.get("enemy_alive", 0)), status.text]
	roster.visible = not teammates.is_empty()
	for index in range(_rows.size()):
		_rows[index].visible = index < teammates.size()
		if index >= teammates.size():
			continue
		var row: Dictionary = teammates[index]
		var selected := bool(row.get("selected", false))
		_rows[index].add_theme_stylebox_override("panel", _selected if selected else _normal)
		_labels[index].text = "%d  %s" % [index + 1, row.get("name", "队友")]
		_health_labels[index].text = "%d HP" % int(row.get("health", 0))
		_labels[index].add_theme_color_override(
			"font_color", Style.TEXT if selected else Style.MUTED
		)
