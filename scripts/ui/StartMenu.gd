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
	title_label.text = "Vector Breach Godot"
	description_label.text = (
		"[b]%s[/b]\n%s\n\n[b]\u8def\u7ebf\u7279\u70b9[/b]\uff1a%s\n[b]\u63a8\u8350\u7528\u9014[/b]\uff1a%s\n[b]\u6d4b\u8bd5\u91cd\u70b9[/b]\uff1a%s"
		% [
			String(option["name"]),
			String(option["description"]),
			String(option["route_profile"]),
			String(option["recommended_use"]),
			String(option["test_focus"])
		]
	)
	hint_label.text = "\u5f00\u59cb\uff1a\u70b9\u51fb\u5f00\u59cb | \u7ee7\u7eed\uff1aP | \u5168\u5c4f\uff1aF | \u91ca\u653e\u9f20\u6807/\u9000\u51fa\u5168\u5c4f\uff1aEsc"
	var preview_path: String = String(option["preview"])
	if ResourceLoader.exists(preview_path):
		preview_rect.texture = load(preview_path)
	else:
		preview_rect.texture = null
	resume_button.visible = can_resume

func set_menu_visible(visible_state: bool) -> void:
	visible = visible_state
