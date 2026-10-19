extends CanvasLayer

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const LocalClassicMaps = preload("res://scripts/level/LocalClassicMaps.gd")
const HelpPanel = preload("res://scripts/ui/PlayerHelpPanel.gd")
var _appearance_choices: Dictionary = {}

const PlayerGuide = preload("res://scripts/ui/PlayerGuide.gd")

signal start_pressed
signal resume_pressed
signal return_to_maps_pressed
signal map_selected(index: int)
signal settings_changed(snapshot: Dictionary)
signal team_selected(team: String)

@onready var title_label: Label = $MenuPanel/Margin/VBox/Title
@onready var preview_rect: TextureRect = $MenuPanel/Margin/VBox/Preview
@onready var description_label: RichTextLabel = $MenuPanel/Margin/VBox/Description
@onready var map_select: OptionButton = $MenuPanel/Margin/VBox/Controls/MapRow/MapSelect
@onready var team_select: OptionButton = $MenuPanel/Margin/VBox/Controls/TeamRow/TeamSelect
@onready var g2_hint: Label = $MenuPanel/Margin/VBox/Controls/G2Hint
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

var _map_options: Array = []
var _selected_map_index: int = 2
var _show_archive: bool = false
var _help_label: RichTextLabel
var _settings_panel: PanelContainer
var _return_to_maps_button: Button

func _ready() -> void:
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	resume_button.pressed.connect(func() -> void: resume_pressed.emit())
	map_select.item_selected.connect(func(index: int) -> void:
		_selected_map_index = map_select.get_item_id(index)
		map_selected.emit(_selected_map_index)
	)
	var archive_toggle := CheckButton.new()
	archive_toggle.name = "ArchiveToggle"
	archive_toggle.text = "开发测试地图"
	$MenuPanel/Margin/VBox/Controls.add_child(archive_toggle)
	archive_toggle.toggled.connect(func(enabled: bool) -> void:
		_show_archive = enabled
		for index in range(_map_options.size()):
			if _is_test_map(String(_map_options[index]["id"])) == enabled:
				_selected_map_index = index
				break
		_refresh_map_options()
		map_selected.emit(_selected_map_index)
	)
	_create_help_panel()
	_create_settings_panel()
	_return_to_maps_button = Button.new()
	_return_to_maps_button.name = "ReturnToMaps"
	_return_to_maps_button.text = "结束当前对局，返回选图"
	_return_to_maps_button.custom_minimum_size.y = 42
	$MenuPanel/Margin/VBox.add_child(_return_to_maps_button)
	$MenuPanel/Margin/VBox.move_child(_return_to_maps_button, $MenuPanel/Margin/VBox/Buttons.get_index())
	_return_to_maps_button.pressed.connect(func() -> void: return_to_maps_pressed.emit())
	team_select.item_selected.connect(func(index: int) -> void: team_selected.emit("T" if index == 0 else "CT"))
	team_select.select(0 if GameState.player_team == "T" else 1)
	update_g2_hint()
	_load_settings_controls(UserSettings.get_snapshot())
	for slider in [sensitivity_slider, volume_slider, crosshair_gap_slider, crosshair_size_slider, radar_range_slider]:
		slider.value_changed.connect(_on_setting_control_changed)
	dynamic_crosshair_toggle.toggled.connect(func(_enabled: bool) -> void: _emit_settings())
	radar_rotates_toggle.toggled.connect(func(_enabled: bool) -> void: _emit_settings())

func set_map_options(options: Array, selected_index: int) -> void:
	_map_options = options
	_selected_map_index = selected_index
	_refresh_map_options()
	update_g2_hint()

func _refresh_map_options() -> void:
	map_select.clear()
	for index in range(_map_options.size()):
		var option: Dictionary = _map_options[index]
		var level_id := String(option["id"])
		var classic_research := LocalClassicMaps.is_classic(level_id)
		if _is_test_map(level_id) != _show_archive:
			continue
		var category := "比赛" if level_id == "gatehouse" else ("练习" if level_id in ["foundry-reforged", "training-range"] else ("经典研究" if classic_research else "开发测试"))
		map_select.add_item("【%s】%s" % [category, String(option["name"])], index)
		if index == _selected_map_index:
			map_select.select(map_select.item_count - 1)

func _is_test_map(level_id: String) -> bool:
	return level_id in ["depot", "core-vault", "test-collision-room"]

func _create_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_settings_panel.offset_left = -610
	_settings_panel.offset_right = -32
	_settings_panel.offset_top = 70
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_settings_panel.add_child(margin)
	$MenuPanel/Margin/VBox/Settings.reparent(margin)
	for appearance_team in ["CT", "T"]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "防守方外观" if appearance_team == "CT" else "进攻方外观"
		label.custom_minimum_size.x = 160
		row.add_child(label)
		var choice := OptionButton.new()
		choice.name = appearance_team + "Appearance"
		for id in Appearance.PROFILES[appearance_team]:
			choice.add_item(Appearance.NAMES[id] + ("" if Appearance.available(id) else "（本机未安装）"))
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(choice)
		margin.get_child(0).add_child(row)
		_appearance_choices[appearance_team] = choice
		choice.item_selected.connect(func(_index: int) -> void: _emit_settings())
	var appearance_hint := Label.new()
	appearance_hint.text = "所选外观用于你的第一人称袖子和手套。\n同队 AI 轮换三套角色外观。"
	appearance_hint.add_theme_font_size_override("font_size", 16)
	margin.get_child(0).add_child(appearance_hint)
	var close_button := Button.new()
	close_button.text = "完成设置"
	margin.get_child(0).add_child(close_button)
	close_button.pressed.connect(func() -> void: _toggle_settings(false))
	add_child(_settings_panel)
	_settings_panel.hide()
	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "游戏设置"
	settings_button.custom_minimum_size.y = 42
	$MenuPanel/Margin/VBox.add_child(settings_button)
	$MenuPanel/Margin/VBox.move_child(settings_button, $MenuPanel/Margin/VBox/Buttons.get_index())
	settings_button.pressed.connect(func() -> void: _toggle_settings(not _settings_panel.visible))

func _toggle_settings(enabled: bool) -> void:
	_settings_panel.visible = enabled
	$PlayerHelp.hide()

func toggle_player_help() -> void:
	if _settings_panel.visible:
		_toggle_settings(false)
	$PlayerHelp.visible = not $PlayerHelp.visible

func _create_help_panel() -> void:
	var panel := HelpPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_bottom = 1.0
	panel.offset_left = -660
	panel.offset_right = -32
	panel.offset_top = 42
	panel.offset_bottom = -32
	_help_label = panel.body
	add_child(panel)
	var help_button := Button.new()
	help_button.name = "HelpButton"
	help_button.text = "操作与回合说明 [F1]"
	help_button.custom_minimum_size.y = 42
	$MenuPanel/Margin/VBox.add_child(help_button)
	$MenuPanel/Margin/VBox.move_child(help_button, $MenuPanel/Margin/VBox/Buttons.get_index())
	help_button.pressed.connect(toggle_player_help)
	panel.closed.connect(func() -> void: help_button.grab_focus())

func dismiss_overlay() -> bool:
	if $PlayerHelp.visible:
		$PlayerHelp.hide()
		return true
	if _settings_panel.visible:
		_toggle_settings(false)
		return true
	return false

func update_g2_hint() -> void:
	var next_match := GameState.match_serial + 1
	var recommended_side := "T" if next_match % 2 == 1 else "CT"
	g2_hint.text = "第 %d 场 · 建议选择%s" % [next_match, "进攻方" if recommended_side == "T" else "防守方"]
	team_select.select(0 if recommended_side == "T" else 1)

func set_map_details(option: Dictionary, can_resume: bool) -> void:
	_show_archive = _is_test_map(String(option["id"]))
	$MenuPanel/Margin/VBox/Controls/ArchiveToggle.set_pressed_no_signal(_show_archive)
	for index in range(_map_options.size()):
		if String(_map_options[index]["id"]) == String(option["id"]):
			_selected_map_index = index
			break
	_refresh_map_options()
	title_label.text = "矢量突袭"
	var is_research := LocalClassicMaps.is_classic(String(option["id"]))
	var is_match := String(option["id"]) == "gatehouse" or is_research
	description_label.text = "[font_size=24][b]%s[/b][/font_size]\n\n%s" % [String(option["name"]), String(option["recommended_use"])]
	$MenuPanel/Margin/VBox/Subtitle.hide()
	$MenuPanel/Margin/VBox/Controls/TeamRow.visible = is_match
	g2_hint.hide()
	start_button.text = "重新开始比赛" if can_resume and is_match else ("重新开始练习" if can_resume else ("开始 3 对 3 比赛" if is_match else "开始练习"))
	if is_research and not can_resume:
		start_button.text = "开始 5 对 5 爆破"
		description_label.text = "[font_size=24][b]%s[/b][/font_size]\n\n你 + 四名 AI 队友，对五名敌人。\n手枪 + $800 开局；购买后点就绪即可开战。" % String(option["name"])
	hint_label.text = "F1 操作帮助 · Esc 暂停菜单"
	_help_label.text = "操作指南\n\n" + PlayerGuide.CONTROLS + "\n\n" + (PlayerGuide.MATCH_RULES if is_match else PlayerGuide.PRACTICE_RULES)
	if is_research:
		_help_label.text = "操作指南\n\n" + PlayerGuide.CONTROLS + "\n\n" + PlayerGuide.RESEARCH_RULES
	var preview_path: String = String(option["preview"])
	# These legacy maps shared an unrelated courtyard thumbnail. Show the
	# actual loaded world behind the menu instead of a misleading reference.
	preview_rect.visible = false
	if not preview_path.is_empty() and ResourceLoader.exists(preview_path):
		preview_rect.texture = load(preview_path)
	else:
		preview_rect.texture = null
	resume_button.visible = can_resume
	_return_to_maps_button.visible = can_resume
	map_select.disabled = can_resume
	$MenuPanel/Margin/VBox/Controls/ArchiveToggle.disabled = can_resume
	map_select.tooltip_text = "先结束当前对局，再选择新地图" if can_resume else ""

func set_match_summary(snapshot: Dictionary, record_path: String) -> void:
	title_label.text = "比赛结算"
	var result_labels := {"player_win": "玩家小队获胜", "opponent_win": "对手小队获胜", "draw": "平局"}
	description_label.text = (
		"[color=#dbc774][font_size=14]%s %dV%d[/font_size][/color]\n"
		+ "[font_size=25][b]%s[/b][/font_size]\n\n"
		+ "玩家小队 %d  :  %d 对手小队\n"
		+ "常规 %d 回合 · 加时 %d 回合\n\n"
		+ "[color=#aaa98f]记录[/color]  %s"
	) % [
		String(snapshot.get("level_name", snapshot.get("level_id", "竞技比赛"))),
		int(snapshot.get("team_size", 3)), int(snapshot.get("team_size", 3)),
		String(result_labels.get(String(snapshot.get("result", "")), "比赛结束")),
		int(snapshot.get("player_score", 0)), int(snapshot.get("opponent_score", 0)),
		int(snapshot.get("regulation_rounds", 0)), int(snapshot.get("overtime_rounds", 0)),
		record_path,
	]
	start_button.text = "开始新比赛"
	resume_button.visible = false
	update_g2_hint()

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
	for appearance_team in ["CT", "T"]:
		var key := "ct_appearance" if appearance_team == "CT" else "t_appearance"
		var choices: Array = Appearance.PROFILES[appearance_team]
		_appearance_choices[appearance_team].select(maxi(0, choices.find(snapshot.get(key, choices[0]))))
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
		"ct_appearance": Appearance.profile_for("CT", _appearance_choices["CT"].selected),
		"t_appearance": Appearance.profile_for("T", _appearance_choices["T"].selected),
	}
	_update_setting_labels()
	settings_changed.emit(snapshot)

func _update_setting_labels() -> void:
	sensitivity_value.text = "%.2f 倍" % sensitivity_slider.value
	volume_value.text = "%d%%" % int(volume_slider.value)
	radar_range_value.text = "%d 米" % int(radar_range_slider.value)
