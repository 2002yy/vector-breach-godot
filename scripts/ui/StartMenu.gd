extends CanvasLayer

signal start_pressed
signal resume_pressed
signal map_selected(index: int)

@onready var title_label: Label = $MenuPanel/Margin/VBox/Title
@onready var preview_rect: TextureRect = $MenuPanel/Margin/VBox/Preview
@onready var description_label: RichTextLabel = $MenuPanel/Margin/VBox/Description
@onready var map_select: OptionButton = $MenuPanel/Margin/VBox/Controls/MapRow/MapSelect
@onready var start_button: Button = $MenuPanel/Margin/VBox/Buttons/StartButton
@onready var resume_button: Button = $MenuPanel/Margin/VBox/Buttons/ResumeButton
@onready var hint_label: Label = $MenuPanel/Margin/VBox/Hints

func _ready() -> void:
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	resume_button.pressed.connect(func() -> void: resume_pressed.emit())
	map_select.item_selected.connect(func(index: int) -> void: map_selected.emit(index))

func set_map_options(options: Array, selected_index: int) -> void:
	map_select.clear()
	for option in options:
		map_select.add_item(String(option["name"]))
	map_select.select(selected_index)

func set_map_details(option: Dictionary, can_resume: bool) -> void:
	title_label.text = "VECTOR BREACH"
	var description_template := (
		"[color=#dbc774][font_size=14]ACTIVE MAP[/font_size][/color]\n"
		+ "[font_size=23][b]%s[/b][/font_size]\n%s\n\n"
		+ "[color=#aaa98f]\u6838\u5fc3\u8def\u7ebf[/color]  %s\n"
		+ "[color=#aaa98f]\u8bad\u7ec3\u7528\u9014[/color]  %s"
	)
	description_label.text = description_template % [
		String(option["name"]),
		String(option["description"]),
		String(option["route_profile"]),
		String(option["recommended_use"])
	]
	start_button.text = "\u91cd\u65b0\u5f00\u59cb" if can_resume else "\u5f00\u59cb\u8bad\u7ec3"
	hint_label.text = "WASD \u79fb\u52a8  \u00b7  MOUSE \u7784\u51c6  \u00b7  1/2 \u5207\u67aa  \u00b7  ESC \u83dc\u5355"
	var preview_path: String = String(option["preview"])
	if ResourceLoader.exists(preview_path):
		preview_rect.texture = load(preview_path)
	else:
		preview_rect.texture = null
	resume_button.visible = can_resume

func set_menu_visible(visible_state: bool) -> void:
	visible = visible_state
