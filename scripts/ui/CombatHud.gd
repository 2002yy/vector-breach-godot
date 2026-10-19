extends CanvasLayer

signal purchase_requested(item_id: String)
signal ready_requested
signal buy_closed
signal help_visibility_changed(opened: bool)

const PlayerGuide = preload("res://scripts/ui/PlayerGuide.gd")
const BuyPage = preload("res://scripts/ui/BuyPage.gd")
const HelpPanel = preload("res://scripts/ui/PlayerHelpPanel.gd")
const MenuStyle = preload("res://scripts/ui/TacticalMenuStyle.gd")

const HEALTH_NORMAL_COLOR := Color(0.88, 0.82, 0.54, 1.0)
const HEALTH_WARNING_COLOR := Color(1.0, 0.38, 0.3, 1.0)
const AMMO_NORMAL_COLOR := Color(0.88, 0.82, 0.54, 1.0)
const AMMO_WARNING_COLOR := Color(1.0, 0.38, 0.3, 1.0)

var _frame_rate_since_usec := Time.get_ticks_usec()
var _frame_rate_count := 0
var _spectator_panel: PanelContainer
var _spectator_text: Label
var _scope: Control

@onready var hud_root: Control = $HudRoot
@onready var health_value: Label = $HudRoot/BottomLeft/Margin/Row/HealthText/Value
@onready var armor_value: Label = $HudRoot/BottomLeft/Margin/Row/ArmorValue
@onready var weapon_label: Label = $HudRoot/BottomRight/Margin/Row/WeaponBlock/Weapon
@onready var weapon_status_label: Label = $HudRoot/BottomRight/Margin/Row/WeaponBlock/Status
@onready var ammo_magazine: Label = $HudRoot/BottomRight/Margin/Row/AmmoMagazine
@onready var ammo_reserve: Label = $HudRoot/BottomRight/Margin/Row/AmmoReserve
@onready var round_state_label: Label = $HudRoot/TopCenter/Margin/Stack/RoundState
@onready var level_name_label: Label = $HudRoot/TopCenter/Margin/Stack/LevelName
@onready var objective_status: Label = $HudRoot/TopCenter/Margin/Stack/ObjectiveStatus
@onready var stats_label: Label = $HudRoot/TopRight/Margin/Stats
@onready var frame_rate_label: Label = $HudRoot/FrameRate
@onready var kill_feed: VBoxContainer = $HudRoot/KillFeed
@onready var scoreboard: PanelContainer = $HudRoot/Scoreboard
@onready var scoreboard_friendly: Label = $HudRoot/Scoreboard/Margin/Stack/FriendlyRow
@onready var scoreboard_enemy: Label = $HudRoot/Scoreboard/Margin/Stack/EnemyRow
@onready var training_end: PanelContainer = $HudRoot/TrainingEnd
@onready var training_result: Label = $HudRoot/TrainingEnd/Margin/Stack/Result
@onready var training_shots: Label = $HudRoot/TrainingEnd/Margin/Stack/Shots
@onready var training_accuracy: Label = $HudRoot/TrainingEnd/Margin/Stack/Accuracy
@onready var training_grenade: Label = $HudRoot/TrainingEnd/Margin/Stack/Grenade
@onready var buy_menu: PanelContainer = $HudRoot/BuyMenu
@onready var buy_result: Label = $HudRoot/BuyMenu/Margin/Stack/Result
@onready var buy_items: Label = $HudRoot/BuyMenu/Margin/Stack/Items
@onready var objective_interaction: PanelContainer = $HudRoot/ObjectiveInteraction
@onready var objective_interaction_label: Label = $HudRoot/ObjectiveInteraction/Margin/Stack/Label
@onready var objective_interaction_progress: ProgressBar = $HudRoot/ObjectiveInteraction/Margin/Stack/Progress
@onready var radar_display: Control = $HudRoot/Radar
@onready var crosshair_top: ColorRect = $HudRoot/Crosshair/Top
@onready var crosshair_bottom: ColorRect = $HudRoot/Crosshair/Bottom
@onready var crosshair_left: ColorRect = $HudRoot/Crosshair/Left
@onready var crosshair_right: ColorRect = $HudRoot/Crosshair/Right
@onready var flash_overlay: ColorRect = $HudRoot/FlashOverlay
@onready var telemetry_panel: PanelContainer = $HudRoot/TrainingTelemetry
@onready var telemetry_label: Label = $HudRoot/TrainingTelemetry/Margin/Label

@export var crosshair_gap_base: float = 7.0
@export var crosshair_gap_per_degree: float = 4.0
var _game_started: bool = false
var _menu_open: bool = true
var _dynamic_crosshair: bool = true
var _crosshair_size: float = 6.0
var _telemetry_visible := false
var _player_help: PanelContainer
var _help_text: RichTextLabel
var _controls_hint: Label

var _objective_hint: Label

func _ready() -> void:
	_scope = preload("res://scripts/ui/ScopeOverlay.gd").new()
	_scope.name = "ScopeOverlay"
	hud_root.add_child(_scope)
	hud_root.move_child(_scope, 0)
	_scope.hide()
	_spectator_panel = PanelContainer.new()
	_spectator_panel.name = "SpectatorPanel"
	_spectator_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_spectator_panel.offset_left = -430
	_spectator_panel.offset_right = 430
	_spectator_panel.offset_top = -218
	_spectator_panel.offset_bottom = -115
	_spectator_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectator_text = Label.new()
	_spectator_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_text.add_theme_font_size_override("font_size", 19)
	_spectator_panel.add_child(_spectator_text)
	hud_root.add_child(_spectator_panel)
	_spectator_panel.hide()
	_objective_hint = Label.new()
	_objective_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_objective_hint.position = Vector2(-380, -245)
	_objective_hint.size = Vector2(760, 42)
	_objective_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_hint.add_theme_font_size_override("font_size", 24)
	_objective_hint.add_theme_color_override("font_color", Color(1, 0.83, 0.38))
	_objective_hint.add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.025))
	_objective_hint.add_theme_constant_override("outline_size", 6)
	hud_root.add_child(_objective_hint)
	buy_menu.set_script(BuyPage)
	buy_menu.call("build")
	buy_menu.connect("purchase_requested", func(item: String) -> void: purchase_requested.emit(item))
	buy_menu.connect("ready_requested", func() -> void: ready_requested.emit())
	buy_menu.connect("closed", func() -> void: buy_closed.emit())
	buy_items.text = "[1] 步枪 $2700  [2] 手枪 $500\n[3] 防弹衣 $650  [4] 衣+盔 $1000\n[5] 拆弹钳 $400\n[6] 高爆手雷 $300  [7] 闪光 $200  [8] 烟雾 $300"
	_controls_hint = Label.new()
	_controls_hint.name = "ControlsHint"
	_controls_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_controls_hint.offset_left = -400
	_controls_hint.offset_right = 400
	_controls_hint.offset_top = -78
	_controls_hint.offset_bottom = -30
	_controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_hint.add_theme_font_size_override("font_size", 17)
	_controls_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_controls_hint.add_theme_constant_override("outline_size", 4)
	hud_root.add_child(_controls_hint)
	_player_help = HelpPanel.new()
	_player_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_player_help.offset_left = -320
	_player_help.offset_top = -330
	_player_help.offset_right = 320
	_player_help.offset_bottom = 330
	_help_text = _player_help.get("body")
	_player_help.connect("closed", func() -> void: help_visibility_changed.emit(false))
	hud_root.add_child(_player_help)
	_player_help.visible = false
	scoreboard.add_theme_stylebox_override("panel", MenuStyle.box(Color("131a1e")))
	apply_settings(UserSettings.get_snapshot())
	if not UserSettings.settings_changed.is_connected(apply_settings):
		UserSettings.settings_changed.connect(apply_settings)

func _process(_delta: float) -> void:
	_frame_rate_count += 1
	var now := Time.get_ticks_usec()
	var elapsed := now - _frame_rate_since_usec
	if elapsed >= 250000:
		frame_rate_label.text = "%d FPS · %.1f ms" % [
			roundi(_frame_rate_count * 1000000.0 / elapsed),
			elapsed / (1000.0 * _frame_rate_count)
		]
		_frame_rate_since_usec = now
		_frame_rate_count = 0
	scoreboard.visible = _game_started and not _menu_open and Input.is_action_pressed("show_scoreboard")
	telemetry_panel.visible = _telemetry_visible and _game_started and not _menu_open

func toggle_training_telemetry() -> void:
	_telemetry_visible = not _telemetry_visible

func _weapon_name(weapon_id: String) -> String:
	return String({"rifle": "步枪", "pistol": "手枪", "knife": "战术刀",
		"sniper": "狙击枪", "smg": "冲锋枪", "shotgun": "霰弹枪"}.get(weapon_id, weapon_id))

func toggle_player_help() -> void:
	if buy_menu.visible and buy_menu.has_method("toggle_help"):
		buy_menu.call("toggle_help")
		return
	_player_help.visible = not _player_help.visible
	help_visibility_changed.emit(_player_help.visible)

func is_help_open() -> bool:
	return is_instance_valid(_player_help) and _player_help.visible

func dismiss_help() -> bool:
	if not is_help_open():
		return false
	_player_help.hide()
	help_visibility_changed.emit(false)
	return true

func show_training_panel(enabled: bool) -> void:
	var panel := get_node_or_null("HudRoot/TrainingModeHint") as Label
	if panel == null:
		panel = Label.new()
		panel.name = "TrainingModeHint"
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		panel.position = Vector2(-310, 118)
		panel.add_theme_font_size_override("font_size", 18)
		panel.add_theme_color_override("font_color", Color("e3c992"))
		panel.add_theme_color_override("font_shadow_color", Color.BLACK)
		panel.add_theme_constant_override("shadow_offset_x", 2)
		panel.add_theme_constant_override("shadow_offset_y", 2)
		panel.text = "独立训练 · 无限备弹 / 自动补雷\nF2 换主武器　F5 重置　F6 补给　F7 返回选图"
		hud_root.add_child(panel)
	panel.visible = enabled
	_telemetry_visible = enabled
	telemetry_label.visible = enabled

func reset_transients() -> void:
	for child in kill_feed.get_children():
		kill_feed.remove_child(child)
		child.queue_free()
	buy_menu.visible = false
	objective_interaction.visible = false
	scoreboard.visible = false
	_telemetry_visible = false
	_player_help.visible = false

func update_training_telemetry(snapshot: Dictionary) -> void:
	telemetry_label.text = "压枪训练 [F4]\n%d 发  ·  %d 中  ·  爆头 %d\n第 %d 发 · 弹着 %s\n命中率 %.1f%% · 投掷：%s" % [
		int(snapshot.get("shots", 0)), int(snapshot.get("hits", 0)), int(snapshot.get("headshots", 0)),
		int(snapshot.get("last_spray_index", -1)) + 1, String(snapshot.get("impact_text", "无命中")),
		float(snapshot.get("accuracy", 0.0)), String(snapshot.get("grenade_text", "暂无投掷记录"))
	]

func update_display(snapshot: Dictionary) -> void:
	_game_started = bool(snapshot.get("game_started", false))
	_menu_open = bool(snapshot.get("menu_open", true))
	hud_root.visible = _game_started and not _menu_open
	_scope.visible = bool(snapshot.get("scoped", false)) and not buy_menu.visible
	$HudRoot/Crosshair.visible = (
		not _scope.visible and not bool(snapshot.get("spectator", {}).get("active", false))
	)
	var watching: Dictionary = snapshot.get("spectator", {})
	_spectator_panel.visible = bool(watching.get("active", false))
	$HudRoot/BottomLeft.visible = not _spectator_panel.visible
	$HudRoot/BottomRight.visible = not _spectator_panel.visible
	if _spectator_panel.visible:
		if bool(watching.get("has_target", false)):
			var mode := "队友眼位" if bool(watching.get("first_person", false)) else "第三人称"
			_spectator_text.text = (
				"你已阵亡 · 正在观战 %s · %s\n生命 %d  护甲 %d · %s · 弹药 %d / %d%s\n"
				+ "左键 / ] 下一位 · 右键 / [ 上一位 · 空格 切换视角 · Esc 暂停"
			) % [
				watching.name, mode, watching.health, watching.armor,
				_weapon_name(String(watching.weapon)), watching.ammo, watching.reserve,
				" · 携带 C4" if bool(watching.c4) else "",
			]
		else:
			_spectator_text.text = "你已阵亡 · 已无存活队友\n等待炸弹或回合结算 · Esc 暂停"

	_objective_hint.text = String(snapshot.get("objective_hint", ""))
	_objective_hint.visible = not _objective_hint.text.is_empty() and not buy_menu.visible
	_controls_hint.visible = not buy_menu.visible
	if _spectator_panel.visible:
		_controls_hint.visible = false
	var health := int(snapshot.get("health", 100))
	health_value.text = str(health)
	health_value.add_theme_color_override(
		"font_color",
		HEALTH_WARNING_COLOR if health <= 25 else HEALTH_NORMAL_COLOR
	)
	armor_value.text = str(int(snapshot.get("armor", 100)))

	var weapon_slot := int(snapshot.get("weapon_slot", 0)) + 1
	weapon_label.text = "[%d] %s" % [
		weapon_slot,
		String(snapshot.get("weapon_name", "\u6b65\u67aa"))
	]
	var weapon_status := String(snapshot.get("weapon_status_text", ""))
	weapon_status_label.text = weapon_status
	weapon_status_label.visible = not weapon_status.is_empty()

	var magazine := int(snapshot.get("ammo_in_mag", 30))
	ammo_magazine.text = "—" if weapon_slot in [3, 5] else str(magazine)
	ammo_reserve.visible = weapon_slot in [1, 2]
	$HudRoot/BottomRight/Margin/Row/AmmoSlash.visible = ammo_reserve.visible
	ammo_reserve.text = str(int(snapshot.get("ammo_reserve", 90)))
	ammo_magazine.add_theme_color_override(
		"font_color",
		(
			AMMO_WARNING_COLOR
			if magazine <= maxi(1, int(snapshot.get("magazine_capacity", 30)) / 6)
			else AMMO_NORMAL_COLOR
		)
	)

	round_state_label.text = "防守 %d    %s    %d 进攻" % [
		int(snapshot.get("ct_score", snapshot.get("friendly_score", 0))),
		String(snapshot.get("round_time", "1:55")),
		int(snapshot.get("t_score", snapshot.get("enemy_score", 0))),
	]
	level_name_label.text = "%d 存活                 %d 存活" % [
		int(snapshot.get("enemy_alive", 0)),
		int(snapshot.get("friendly_alive", 1)),
	]
	var bomb: Dictionary = snapshot.get("bomb", {}) as Dictionary
	objective_status.text = String(snapshot.get("round_label", ""))
	if bool(bomb.get("bomb_planted", false)):
		objective_status.text = "C4已安装 · %s区" % String(bomb.get("bomb_site", "A"))
	elif RoundManager.state == RoundManager.RoundState.LIVE and bool(bomb.get("bomb_carried", false)) and String(snapshot.get("player_team", "T")) == "T":
		objective_status.text += "  ·  携带 C4"
	var interaction_type := String(bomb.get("interaction_type", ""))
	objective_interaction.visible = hud_root.visible and not interaction_type.is_empty()
	if objective_interaction.visible:
		objective_interaction_label.text = "正在安装 C4" if interaction_type == "plant" else "正在拆除 C4"
		objective_interaction_progress.value = float(bomb.get("interaction_progress", 0.0)) * 100.0
	stats_label.text = "$%d" % int(snapshot.get("money", 800))
	var scoreboard_rows: Dictionary = snapshot.get("scoreboard_rows", {}) as Dictionary
	var friendly_rows: Array = scoreboard_rows.get("friendly", []) as Array
	var enemy_rows: Array = scoreboard_rows.get("enemy", []) as Array
	scoreboard_friendly.text = "\n".join(friendly_rows) if not friendly_rows.is_empty() else "你  %d/0  命中%d  $%d  %s  存活" % [int(snapshot.get("kill_count", 0)), int(snapshot.get("hit_count", 0)), int(snapshot.get("money", 800)), String(snapshot.get("weapon_name", "步枪"))]
	var competitive := GameState.is_competitive_level()
	_player_help.call("set_context", GameState.current_level_id)
	_controls_hint.text = "F1 操作帮助"
	if competitive and RoundManager.can_buy():
		_controls_hint.text += "\n手枪开局；步枪 $2700。出生区按 B 购买，当前 $%d" % int(snapshot.get("money", 800))
	scoreboard_enemy.text = "\n".join(enemy_rows) if not enemy_rows.is_empty() else "暂无敌方单位"
	training_end.visible = bool(snapshot.get("training_complete", false)) and _game_started and not _menu_open
	var training := GameState.current_level_id == "training-range"
	stats_label.visible = not training
	if training:
		round_state_label.text = "独立训练场 · 不限时"
		level_name_label.text = "射击 / 压枪 / 投掷"
		objective_status.text = "靶子击倒后自动重生"
		training_end.visible = false
		_controls_hint.text = "1 主武器 · 2 手枪 · 3 刀 · 4 投掷物 · F1 帮助"
	var result_text := String(snapshot.get("round_result_text", ""))
	var debrief: Dictionary = snapshot.get("training_debrief", {}) as Dictionary
	training_result.text = result_text if not result_text.is_empty() else "回合训练完成"
	training_shots.text = "射击  %d 发       命中  %d 发       爆头  %d" % [
		int(debrief.get("shots", 0)), int(debrief.get("hits", 0)), int(debrief.get("headshots", 0))
	]
	training_accuracy.text = "命中率  %.1f%%" % float(debrief.get("accuracy", 0.0))
	training_grenade.text = "最近投掷  %s" % String(debrief.get("grenade_text", "暂无投掷记录"))
	_update_crosshair(float(snapshot.get("spread_degrees", 0.0)))
	var flash_intensity := float(snapshot.get("flash_intensity", 0.0))
	flash_overlay.visible = flash_intensity > 0.01
	flash_overlay.color = Color(1.0, 1.0, 0.96, flash_intensity)
	update_radar(snapshot.get("radar", {}) as Dictionary)

func update_radar(snapshot: Dictionary) -> void:
	if radar_display.has_method("set_snapshot"):
		radar_display.call("set_snapshot", snapshot)

func _update_crosshair(spread_degrees: float) -> void:
	var gap := crosshair_gap_base + (spread_degrees * crosshair_gap_per_degree if _dynamic_crosshair else 0.0)
	crosshair_top.size.y = _crosshair_size
	crosshair_bottom.size.y = _crosshair_size
	crosshair_left.size.x = _crosshair_size
	crosshair_right.size.x = _crosshair_size
	crosshair_top.position = Vector2(-crosshair_top.size.x * 0.5, -gap - _crosshair_size)
	crosshair_bottom.position = Vector2(-crosshair_bottom.size.x * 0.5, gap)
	crosshair_left.position = Vector2(-gap - _crosshair_size, -crosshair_left.size.y * 0.5)
	crosshair_right.position = Vector2(gap, -crosshair_right.size.y * 0.5)

func apply_settings(snapshot: Dictionary) -> void:
	crosshair_gap_base = float(snapshot.get("crosshair_gap", 7.0))
	_crosshair_size = float(snapshot.get("crosshair_size", 6.0))
	_dynamic_crosshair = bool(snapshot.get("dynamic_crosshair", true))

func add_kill_feed(killer: String, victim: String, weapon: String) -> void:
	var entry := Label.new()
	entry.text = "%s   [%s]   %s" % [killer, weapon, victim]
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.add_theme_color_override("font_color", Color(0.94, 0.86, 0.62, 1.0))
	entry.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	entry.add_theme_constant_override("outline_size", 4)
	entry.add_theme_font_size_override("font_size", 17)
	kill_feed.add_child(entry)
	var entry_id := entry.get_instance_id()
	get_tree().create_timer(4.5).timeout.connect(func() -> void:
		var live_entry := instance_from_id(entry_id) as Label
		if is_instance_valid(live_entry):
			live_entry.queue_free()
	)

func show_radio_report(caller: String, message: String) -> void:
	for child in kill_feed.get_children():
		if child is Label and String((child as Label).text).contains("[无线电] %s" % caller):
			child.queue_free()
	var entry := Label.new()
	entry.text = "[无线电] %s：%s" % [caller, message]
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	entry.add_theme_color_override("font_color", Color(0.48, 0.75, 0.95, 1.0))
	entry.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	entry.add_theme_constant_override("outline_size", 4)
	entry.add_theme_font_size_override("font_size", 16)
	kill_feed.add_child(entry)
	var entry_id := entry.get_instance_id()
	get_tree().create_timer(3.2).timeout.connect(func() -> void:
		var live_entry := instance_from_id(entry_id) as Label
		if is_instance_valid(live_entry):
			live_entry.queue_free()
	)

func set_buy_menu_visible(visible_state: bool) -> void:
	buy_menu.visible = visible_state and _game_started and not _menu_open
	_controls_hint.visible = not buy_menu.visible
	_objective_hint.visible = not buy_menu.visible and not _objective_hint.text.is_empty()
	if visible_state:
		buy_result.text = ""

func show_purchase_result(message: String) -> void:
	buy_result.text = message
	buy_menu.call("show_result", message)

func update_buy_page(snapshot: Dictionary) -> void:
	buy_menu.call("update_page", snapshot)
