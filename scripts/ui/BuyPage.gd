extends PanelContainer

signal purchase_requested(item_id: String)
signal ready_requested
signal closed

const Official = preload("res://scripts/player/OfficialEquipment.gd")

const PRODUCTS := {
	"rifle": ["步枪", 2700, "30 发弹匣 · 90 发备弹\n中远距离压制，连射时注意控枪", "res://assets/ui/buy/rifle.png"],
	"pistol": ["手枪", 500, "12 发弹匣 · 36 发备弹\n半自动副武器，手枪局默认持有", "res://assets/ui/buy/pistol.png"],
	"armor": ["防弹衣", 650],
	"armor_helmet": ["防弹衣 + 头盔", 1000],
	"defuse_kit": ["拆弹钳", 400],
	"he_grenade": ["高爆手雷", 300],
	"flash_grenade": ["闪光弹", 200],
	"smoke_grenade": ["烟雾弹", 300],
	"sniper": ["狙击枪", 4750, "5 发弹匣 · 20 发备弹\n右键开镜；高伤害，开火间隔较长"],
	"smg": ["冲锋枪", 1500, "30 发弹匣 · 120 发备弹\n近距离连续射击，远距离衰减明显"],
	"shotgun": ["霰弹枪", 1850, "8 发弹匣 · 32 发备弹\n每发 7 枚弹丸，适合近距离守点"],
	"fire_grenade": ["燃烧弹", 500],
}
var _buttons: Dictionary = {}
var _balance: Label
var _countdown: Label
var _result: Label
var _ready_button: Button
var _weapon_images: Dictionary = {}
var _weapon_titles: Dictionary = {}
var _preview_team := ""
var _help_copy: Label
var _content_scroll: ScrollContainer


func build() -> void:
	$Margin.hide()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -510
	offset_right = 510
	offset_top = -345
	offset_bottom = 345
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111713")
	style.border_color = Color("8b8053")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	var title := _label("回合准备 · 武器与装备", 27)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var help := Button.new()
	help.name = "BuyHelpButton"
	help.text = "购买说明 [F1]"
	help.pressed.connect(toggle_help)
	header.add_child(help)
	_balance = _label("", 25)
	header.add_child(_balance)
	_countdown = _label("", 18)
	stack.add_child(_countdown)
	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "ProductsScroll"
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(_content_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	_content_scroll.add_child(content)
	_help_copy = _label("首局和换边后为手枪 + $800。后续回合积累资金，可保留存活时的装备。\n"
		+ "主武器只能持有一把，换购会将旧枪留在脚边；不退款。拾取保留剩余弹量。\n"
		+ "投掷物最多四枚，闪光弹最多两枚。防守方可购买拆弹钳。\n"
		+ "买好后点击下方就绪立即开战。说明展开时，就绪按钮仍可使用。", 18)
	_help_copy.name = "BuyHelpCopy"
	_help_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_copy.hide()
	content.add_child(_help_copy)
	var weapons := HBoxContainer.new()
	weapons.add_theme_constant_override("separation", 20)
	content.add_child(weapons)
	for item in ["rifle", "pistol"]:
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_constant_override("separation", 8)
		weapons.add_child(card)
		var texture := TextureRect.new()
		texture.name = item.capitalize() + "Image"
		texture.custom_minimum_size = Vector2(440, 180)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.texture = load(String(PRODUCTS[item][3]))
		_weapon_images[item] = texture
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(texture)
		card.add_child(_label(String(PRODUCTS[item][2]), 16))
		card.add_child(_product_button(item))
	content.add_child(_label("其他主武器（替换当前主武器）", 20))
	var primary := GridContainer.new()
	primary.columns = 3
	primary.add_theme_constant_override("h_separation", 12)
	content.add_child(primary)
	for item in ["sniper", "smg", "shotgun"]:
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(0, 105)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture = Official.preview(item, GameState.player_team)
		card.add_child(image)
		card.add_child(_label(String(PRODUCTS[item][2]), 15))
		card.add_child(_product_button(item))
		primary.add_child(card)
	content.add_child(_label("护甲与战术装备", 20))
	var equipment := GridContainer.new()
	equipment.columns = 3
	equipment.add_theme_constant_override("h_separation", 12)
	equipment.add_theme_constant_override("v_separation", 10)
	content.add_child(equipment)
	for item in [
		"armor",
		"armor_helmet",
		"defuse_kit",
		"he_grenade",
		"flash_grenade",
		"smoke_grenade",
		"fire_grenade"
	]:
		equipment.add_child(_product_button(item))
	_result = _label("首局 $800 + 手枪；步枪 $2700，需要后续回合积累资金。", 17)
	_result.custom_minimum_size.y = 28
	stack.add_child(_result)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	stack.add_child(footer)
	var close_button := Button.new()
	close_button.text = "收起购买页 [B]"
	close_button.custom_minimum_size = Vector2(260, 54)
	close_button.pressed.connect(func() -> void: closed.emit())
	footer.add_child(close_button)
	_ready_button = Button.new()
	_ready_button.name = "ReadyButton"
	_ready_button.text = "就绪开战 →"
	_ready_button.add_theme_font_size_override("font_size", 24)
	var ready_style := StyleBoxFlat.new()
	ready_style.bg_color = Color("b2a367")
	ready_style.set_corner_radius_all(6)
	_ready_button.add_theme_stylebox_override("normal", ready_style)
	_ready_button.add_theme_stylebox_override("hover", ready_style)
	_ready_button.add_theme_stylebox_override("pressed", ready_style)
	_ready_button.add_theme_color_override("font_color", Color("111713"))
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_button.pressed.connect(func() -> void: ready_requested.emit())
	footer.add_child(_ready_button)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ede8d5"))
	return label

func toggle_help() -> void:
	_help_copy.visible = not _help_copy.visible
	if _help_copy.visible:
		_content_scroll.scroll_vertical = 0


func _product_button(item: String) -> Button:
	var button := Button.new()
	button.name = item.capitalize().replace("_", "") + "Button"
	button.custom_minimum_size.y = 55
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_disabled_color", Color("a7afa4"))
	button.pressed.connect(func() -> void: purchase_requested.emit(item))
	_buttons[item] = button
	return button


func update_page(snapshot: Dictionary) -> void:
	var team := String(snapshot.get("team", "T"))
	if team != _preview_team:
		_preview_team = team
		for item in _weapon_images:
			var preview := Official.preview(item, team)
			_weapon_images[item].texture = preview if preview != null else load(String(PRODUCTS[item][3]))
			var model_name := ("M4A1-S" if team == "CT" else "AK-47") if item == "rifle" else "Glock"
			_weapon_titles[item] = String(PRODUCTS[item][0]) + (" · %s 外观" % model_name if preview != null else "")
	_balance.text = "可用资金  $%d" % int(snapshot.get("money", 0))
	_countdown.text = (
		"%s方 · 准备剩余 %d 秒 · 买好即可点击就绪，无需等到倒计时结束"
		% [
			"进攻" if snapshot.get("team", "T") == "T" else "防守",
			ceili(float(snapshot.get("seconds", 0.0)))
		]
	)
	_ready_button.disabled = not bool(snapshot.get("ready_allowed", false))
	var offers: Dictionary = snapshot.get("offers", {})
	for item in _buttons:
		var offer: Dictionary = offers.get(item, {})
		var button: Button = _buttons[item]
		button.disabled = not bool(offer.get("success", false))
		var price := int(offer.get("price", PRODUCTS[item][1]))
		button.text = (
			"%s%s  $%d\n%s"
			% [
				_shortcut(item),
				_weapon_titles.get(item, PRODUCTS[item][0]),
				price,
				"点击购买" if not button.disabled else String(offer.get("reason", "不可购买"))
			]
		)

func _shortcut(item: String) -> String:
	var index := PRODUCTS.keys().find(item) + 1
	return ("[%d] " % index) if index <= 9 else ("[0] " if index == 10 else "")


func show_result(message: String) -> void:
	_result.text = message
