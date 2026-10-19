extends PanelContainer

signal closed

var body: RichTextLabel


func _init() -> void:
	name = "PlayerHelp"
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111713")
	style.border_color = Color("8b8053")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	var title := Label.new()
	title.text = "操作与回合说明"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("dbc774"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseHelp"
	close_button.text = "关闭 [F1]"
	close_button.custom_minimum_size = Vector2(112, 38)
	close_button.pressed.connect(
		func() -> void:
			hide()
			closed.emit()
	)
	header.add_child(close_button)
	var hint := Label.new()
	hint.text = "随时按 F1 展开或收起；下方可滚动查看全部说明。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("aaa98f"))
	stack.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	body = RichTextLabel.new()
	body.name = "HelpBody"
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("normal_font_size", 19)
	body.add_theme_color_override("default_color", Color("e4e4d4"))
	scroll.add_child(body)
