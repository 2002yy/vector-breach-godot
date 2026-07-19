extends CanvasLayer

signal start_pressed
signal resume_pressed
signal map_selected(index: int)
signal settings_changed(snapshot: Dictionary)
signal team_selected(team: String)

@onready var title_label: Label = $MenuPanel/Margin/VBox/Title
@onready var preview_rect: TextureRect = $MenuPanel/Margin/VBox/Preview
@onready var description_label: RichTextLabel = $MenuPanel/Margin/VBox/Description
@onready var map_select: OptionButton = $MenuPanel/Margin/VBox/Controls/MapRow/MapSelect
@onready var team_select: OptionButton = $MenuPanel/Margin/VBox/Controls/TeamRow/TeamSelect
@onready var start_button: Button = $MenuPanel/Margin/VBox/Buttons/StartButton
@onready var resume_button: Button = $MenuPanel/Margin/VBox/Buttons/ResumeButton
@onready var hint_label: Label = $MenuPanel/Margin/VBox/Hints
@onready var sensitivity_slider: HSlider = $MenuPanel/Margin/VBox/Settings/SensitivityRow/Sensitivity
@onready var sensitivity_value: Label = $MenuPanel/Margin/VBox/Settings/SensitivityRow/Value
@onready var volume_slider: HSlider = $MenuPanel/Margin/VBox/Settings/VolumeRow/Volume
@onready var volume_value: Label = $MenuPanel/Margin/VBox/Settings/VolumeRow/Value
@onready var crosshair_gap_slider: HSlider = $MenuPanel/Margin/VBox/Settings/CrosshairGapRow/Gap
@onready var crosshair_size_slider: HSlider = $MenuPanel/Margin/VBox/Settings/CrosshairSizeRow/Size
@onready var dynamic_crosshair_toggle: CheckButton = $MenuPanel/Margin/VBox/Settings/DynamicCrosshair
@onready var radar_range_slider: HSlider = $MenuPanel/Margin/VBox/Settings/RadarRangeRow/Range
@onready var radar_range_value: Label = $MenuPanel/Margin/VBox/Settings/RadarRangeRow/Value
@onready var radar_rotates_toggle: CheckButton = $MenuPanel/Margin/VBox/Settings/RadarRotates

func _ready() -> void:
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	resume_button.pressed.connect(func() -> void: resume_pressed.emit())
	map_select.item_selected.connect(func(index: int) -> void: map_selected.emit(index))
	team_select.item_selected.connect(func(index: int) -> void: team_selected.emit("T" if index == 0 else "CT"))
	team_select.select(0 if GameState.player_team == "T" else 1)
	_load_settings_controls(UserSettings.get_snapshot())
	for slider in [sensitivity_slider, volume_slider, crosshair_gap_slider, crosshair_size_slider, radar_range_slider]:
		slider.value_changed.connect(_on_setting_control_changed)
	dynamic_crosshair_toggle.toggled.connect(func(_enabled: bool) -> void: _emit_settings())
	radar_rotates_toggle.toggled.connect(func(_enabled: bool) -> void: _emit_settings())

func set_map_options(options: Array, selected_index: int) -> void:
	map_select.clear()
	for option in options:
		map_select.add_item(String(option["name"]))
	map_select.select(selected_index)

func set_map_details(option: Dictionary, can_resume: bool) -> void:
	title_label.text = "矢量突袭"
	var description_template := (
		"[color=#dbc774][font_size=14]当前地图[/font_size][/color]\n"
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
	hint_label.text = "WASD \u79fb\u52a8  \u00b7  SHIFT \u9759\u6b65  \u00b7  TAB \u8ba1\u5206\u677f  \u00b7  ESC \u83dc\u5355"
	var preview_path: String = String(option["preview"])
	if ResourceLoader.exists(preview_path):
		preview_rect.texture = load(preview_path)
	else:
		preview_rect.texture = null
	resume_button.visible = can_resume

func set_menu_visible(visible_state: bool) -> void:
	visible = visible_state

func _load_settings_controls(snapshot: Dictionary) -> void:
	sensitivity_slider.set_value_no_signal(float(snapshot.get("mouse_sensitivity_multiplier", 1.0)))
	volume_slider.set_value_no_signal(float(snapshot.get("master_volume", 0.8)) * 100.0)
	crosshair_gap_slider.set_value_no_signal(float(snapshot.get("crosshair_gap", 7.0)))
	crosshair_size_slider.set_value_no_signal(float(snapshot.get("crosshair_size", 6.0)))
	dynamic_crosshair_toggle.set_pressed_no_signal(bool(snapshot.get("dynamic_crosshair", true)))
	radar_range_slider.set_value_no_signal(float(snapshot.get("radar_range", 24.0)))
	radar_rotates_toggle.set_pressed_no_signal(bool(snapshot.get("radar_rotates", true)))
	_update_setting_labels()

func _on_setting_control_changed(_value: float) -> void:
	_emit_settings()

func _emit_settings() -> void:
	var snapshot := {
		"mouse_sensitivity_multiplier": sensitivity_slider.value,
		"master_volume": volume_slider.value / 100.0,
		"crosshair_gap": crosshair_gap_slider.value,
		"crosshair_size": crosshair_size_slider.value,
		"dynamic_crosshair": dynamic_crosshair_toggle.button_pressed,
		"radar_range": radar_range_slider.value,
		"radar_rotates": radar_rotates_toggle.button_pressed,
	}
	_update_setting_labels()
	settings_changed.emit(snapshot)

func _update_setting_labels() -> void:
	sensitivity_value.text = "%.2f 倍" % sensitivity_slider.value
	volume_value.text = "%d%%" % int(volume_slider.value)
	radar_range_value.text = "%d 米" % int(radar_range_slider.value)
