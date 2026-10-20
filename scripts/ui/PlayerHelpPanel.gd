extends PanelContainer

signal closed

const Style = preload("res://scripts/ui/TacticalMenuStyle.gd")
const Guide = preload("res://scripts/ui/PlayerGuide.gd")

var body: RichTextLabel
var _rows: VBoxContainer
var _tabs: Array[Button] = []
var _level_id := "gatehouse"
var _selected_tab := 0


func _init() -> void:
	name = "PlayerHelp"
	visible = false
	add_theme_stylebox_override("panel", Style.box(Color(0.055, 0.075, 0.085, 0.98)))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 20)
	add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	var title := Style.label("操作与对局指南", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseHelp"
	close_button.text = "关闭  F1"
	Style.button(close_button)
	header.add_child(close_button)
	close_button.pressed.connect(
		func() -> void:
			hide()
			closed.emit()
	)
	var tabs := HBoxContainer.new()
	tabs.name = "GuideTabs"
	tabs.add_theme_constant_override("separation", 8)
	stack.add_child(tabs)
	for index in range(3):
		var button := Button.new()
		button.name = ["BasicsTab", "CombatTab", "BombTab"][index]
		button.text = ["基础操作", "战斗技巧", "爆破规则"][index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46
		Style.button(button)
		tabs.add_child(button)
		_tabs.append(button)
		button.pressed.connect(func() -> void: select_tab(index))
	var scroll := ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "GuideRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)
	body = RichTextLabel.new()
	body.name = "GuideNote"
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size.y = 50
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_color_override("default_color", Style.MUTED)
	stack.add_child(body)
	select_tab(0)


func set_context(level_id: String) -> void:
	if _level_id == level_id:
		return
	_level_id = level_id
	select_tab(_selected_tab)


func select_tab(index: int) -> void:
	_selected_tab = clampi(index, 0, 2)
	for i in range(_tabs.size()):
		_tabs[i].add_theme_stylebox_override(
			"normal",
			Style.box(
				Color("354045") if i == _selected_tab else Style.INK,
				Style.BRASS if i == _selected_tab else Color.TRANSPARENT
			)
		)
		_tabs[i].set_meta("selected", i == _selected_tab)
	for child in _rows.get_children():
		child.free()
	var sections := Guide.sections(_level_id)
	for record in sections[_selected_tab].rows:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 55
		row.add_theme_constant_override("separation", 20)
		var keycap := PanelContainer.new()
		keycap.custom_minimum_size.x = 155
		keycap.add_theme_stylebox_override("panel", Style.box(Color("242d31")))
		var key := Style.label(record[0], 18, Style.BRASS)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keycap.add_child(key)
		row.add_child(keycap)
		var action := Style.label(record[1], 19)
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action)
		_rows.add_child(row)
	body.text = sections[_selected_tab].note
	var scroll := find_child("HelpScroll", true, false) as ScrollContainer
	scroll.scroll_vertical = 0
