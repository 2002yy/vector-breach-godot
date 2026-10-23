extends RefCounted

const Style = preload("res://scripts/ui/TacticalMenuStyle.gd")

var owner_menu: CanvasLayer
var map_card: Button
var map_image: TextureRect
var map_name: Label
var map_mode: Label
var team_row: HBoxContainer
var team_buttons := {}
var picker: PanelContainer
var picker_grid: GridContainer
var hero: VBoxContainer
var hero_name: Label
var hero_mode: Label
var footer: HBoxContainer


func build(menu: CanvasLayer) -> void:
	owner_menu = menu
	var stack := menu.get_node("MenuPanel/Margin/VBox")
	menu.get_node("MenuPanel").offset_right = 400
	menu.get_node("MenuPanel").add_theme_stylebox_override(
		"panel", Style.box(Color(0.04, 0.055, 0.065, 0.88))
	)
	menu.get_node("Backdrop").color = Color(0.01, 0.015, 0.02, 0.12)
	stack.add_theme_constant_override("separation", 12)
	menu.get_node("MenuPanel/Margin/VBox/Title").add_theme_font_size_override("font_size", 40)
	menu.get_node("MenuPanel/Margin/VBox/Eyebrow").text = "矢量突袭  /  单机版"
	menu.get_node("MenuPanel/Margin/VBox/Subtitle").hide()
	menu.get_node("MenuPanel/Margin/VBox/Controls").hide()
	menu.get_node("MenuPanel/Margin/VBox/Preview").hide()
	map_card = Button.new()
	map_card.name = "MapCard"
	map_card.custom_minimum_size.y = 174
	Style.button(map_card)
	stack.add_child(map_card)
	stack.move_child(map_card, 4)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 12
	content.offset_bottom = -12
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_card.add_child(content)
	map_image = TextureRect.new()
	map_image.custom_minimum_size.y = 88
	map_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(map_image)
	map_name = Style.label("", 22)
	content.add_child(map_name)
	map_mode = Style.label("", 14, Style.MUTED)
	content.add_child(map_mode)
	map_card.pressed.connect(func() -> void: show_picker(not picker.visible))
	team_row = HBoxContainer.new()
	team_row.name = "TeamCards"
	team_row.add_theme_constant_override("separation", 8)
	stack.add_child(team_row)
	stack.move_child(team_row, 5)
	for team in ["CT", "T"]:
		var button := Button.new()
		button.name = team + "Card"
		button.text = "防守方  CT" if team == "CT" else "进攻方  T"
		button.custom_minimum_size.y = 56
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Style.button(button)
		team_row.add_child(button)
		team_buttons[team] = button
		button.pressed.connect(
			func() -> void:
				menu.get("team_select").select(0 if team == "T" else 1)
				menu.emit_signal("team_selected", team)
				select_team(team)
		)
	var buttons: HBoxContainer = stack.get_node("Buttons")
	buttons.custom_minimum_size.y = 58
	Style.button(buttons.get_node("StartButton"), true)
	Style.button(buttons.get_node("ResumeButton"))
	footer = HBoxContainer.new()
	footer.name = "Navigation"
	stack.add_child(footer)
	for item in [["SettingsButton", "设置"], ["HelpButton", "操作帮助"], ["QuitButton", "退出"]]:
		var button := stack.get_node_or_null(item[0]) as Button
		if button == null:
			button = Button.new()
			button.name = item[0]
			footer.add_child(button)
			button.pressed.connect(func() -> void: menu.get_tree().quit())
		else:
			button.reparent(footer)
		button.text = item[1]
		button.custom_minimum_size.y = 38
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Style.button(button)
		button.add_theme_font_size_override("font_size", 15)
	stack.move_child(footer, stack.get_node("Hints").get_index())
	_build_picker()
	hero = VBoxContainer.new()
	hero.name = "MapIdentity"
	hero.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hero.offset_left = -580
	hero.offset_right = -60
	hero.offset_top = -170
	hero.offset_bottom = -50
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(hero)
	hero_mode = Style.label("", 17, Style.BRASS)
	hero.add_child(hero_mode)
	hero_name = Style.label("", 48)
	hero_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	hero_name.add_theme_constant_override("outline_size", 5)
	hero.add_child(hero_name)
	var caption := Style.label("选择阵营，与 AI 队友共同完成任务", 18)
	for label in [hero_mode, caption]:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 4)
	hero.add_child(caption)


func _build_picker() -> void:
	picker = PanelContainer.new()
	picker.name = "MapPicker"
	picker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	picker.offset_left = -920
	picker.offset_right = -40
	picker.offset_top = 70
	picker.add_theme_stylebox_override("panel", Style.box(Color(0.055, 0.075, 0.085, 0.98)))
	owner_menu.add_child(picker)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	picker.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Style.label("选择地图", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseMaps"
	close.text = "关闭"
	Style.button(close)
	header.add_child(close)
	close.pressed.connect(func() -> void: show_picker(false))
	picker_grid = GridContainer.new()
	picker_grid.columns = 3
	picker_grid.add_theme_constant_override("h_separation", 12)
	picker_grid.add_theme_constant_override("v_separation", 12)
	column.add_child(picker_grid)
	picker.hide()


func show_picker(show: bool) -> void:
	if show:
		owner_menu.call("dismiss_overlay")
		for child in picker_grid.get_children():
			child.free()
		var options: Array = owner_menu.get("_map_options")
		var original_dust_available := false
		for option in options:
			if String(option.id) == "dustline-depths-original-local":
				original_dust_available = true
		for index in range(options.size()):
			var option: Dictionary = options[index]
			if String(option.id) == "dustline-depths" and original_dust_available:
				continue
			if (
				owner_menu.call("_is_test_map", String(option.id))
				!= owner_menu.get("_show_archive")
			):
				continue
			var card := Button.new()
			card.name = "Map_" + String(option.id).replace("-", "_")
			card.custom_minimum_size = Vector2(260, 150)
			Style.button(card)
			if index == int(owner_menu.get("_selected_map_index")):
				card.add_theme_stylebox_override("normal", Style.box(Style.PANEL, Style.BRASS))
			var column := VBoxContainer.new()
			column.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(column)
			column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			column.offset_left = 12
			column.offset_right = -12
			column.offset_top = 12
			var image := TextureRect.new()
			image.custom_minimum_size.y = 82
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			image.texture = thumbnail(option)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(image)
			column.add_child(
				Style.label(short_name(String(option.id), String(option.get("name", ""))), 19)
			)
			column.add_child(Style.label(mode(String(option.id)), 14, Style.MUTED))
			picker_grid.add_child(card)
			card.pressed.connect(
				func() -> void:
					owner_menu.emit_signal("map_selected", index)
					show_picker(false)
					map_card.grab_focus()
			)
	picker.visible = show
	hero.visible = not show


func update(option: Dictionary, can_resume: bool) -> void:
	var id := String(option.id)
	map_name.text = short_name(id, String(option.get("name", "")))
	map_mode.text = mode(id) + "    更换地图"
	map_image.texture = thumbnail(option)
	map_card.disabled = can_resume
	team_row.visible = id == "gatehouse" or "classic" in id or id.begins_with("dustline")
	for button in team_buttons.values():
		button.disabled = can_resume
	hero_name.text = map_name.text
	hero_mode.text = mode(id)
	select_team("T" if owner_menu.get("team_select").selected == 0 else "CT")


func select_team(team: String) -> void:
	for id in team_buttons:
		var button: Button = team_buttons[id]
		var color: Color = Style.CT if id == "CT" else Style.BRASS
		button.add_theme_stylebox_override(
			"normal",
			Style.box(
				Color("243139") if id == team else Style.INK,
				color if id == team else Color("343d40")
			)
		)
		button.add_theme_color_override("font_color", color if id == team else Style.MUTED)
		button.set_meta("selected", id == team)


static func short_name(id: String, fallback: String) -> String:
	if "inferno" in id:
		return "炼狱小镇 · Inferno"
	if "mirage" in id:
		return "荒漠迷城 · Mirage"
	if id.begins_with("dustline"):
		return "沙线 · Dust II"
	return {"gatehouse": "门厅区", "training-range": "独立训练场", "foundry-reforged": "铸造厂·重构"}.get(
		id, fallback
	)


static func mode(id: String) -> String:
	if id == "gatehouse":
		return "3 对 3 爆破 · AI 对战"
	if "classic" in id or id.begins_with("dustline"):
		return "5 对 5 经典爆破 · AI 对战"
	return "自由练习"


static func thumbnail(option: Dictionary) -> Texture2D:
	var id := String(option.id)
	var path := "res://assets/local_reference/cs_official/ui/maps/" + id + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if id in ["gatehouse", "training-range", "foundry-reforged"]:
		path = "res://assets/maps/" + ("yard" if id == "training-range" else id) + "-preview.png"
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


static func background(option: Dictionary) -> Texture2D:
	var path := (
		"res://assets/local_reference/cs_official/ui/maps/" + String(option.id) + "-background.png"
	)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return thumbnail(option)
