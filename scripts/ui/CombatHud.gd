extends CanvasLayer

const HEALTH_NORMAL_COLOR := Color(0.88, 0.82, 0.54, 1.0)
const HEALTH_WARNING_COLOR := Color(1.0, 0.38, 0.3, 1.0)
const AMMO_NORMAL_COLOR := Color(0.88, 0.82, 0.54, 1.0)
const AMMO_WARNING_COLOR := Color(1.0, 0.38, 0.3, 1.0)

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
@onready var kill_feed: VBoxContainer = $HudRoot/KillFeed
@onready var scoreboard: PanelContainer = $HudRoot/Scoreboard
@onready var scoreboard_friendly: Label = $HudRoot/Scoreboard/Margin/Stack/FriendlyRow
@onready var scoreboard_enemy: Label = $HudRoot/Scoreboard/Margin/Stack/EnemyRow
@onready var training_end: PanelContainer = $HudRoot/TrainingEnd
@onready var training_summary: Label = $HudRoot/TrainingEnd/Summary
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

@export var crosshair_gap_base: float = 7.0
@export var crosshair_gap_per_degree: float = 4.0
var _game_started: bool = false
var _menu_open: bool = true
var _dynamic_crosshair: bool = true
var _crosshair_size: float = 6.0

func _ready() -> void:
	buy_items.text = "[1] 步枪 $2700  [2] 手枪 $500\n[3] 防弹衣 $650  [4] 衣+盔 $1000\n[5] 拆弹钳 $400\n[6] HE $300  [7] 闪光 $200  [8] 烟雾 $300"
	apply_settings(UserSettings.get_snapshot())
	if not UserSettings.settings_changed.is_connected(apply_settings):
		UserSettings.settings_changed.connect(apply_settings)

func _process(_delta: float) -> void:
	scoreboard.visible = _game_started and not _menu_open and Input.is_action_pressed("show_scoreboard")

func update_display(snapshot: Dictionary) -> void:
	_game_started = bool(snapshot.get("game_started", false))
	_menu_open = bool(snapshot.get("menu_open", true))
	hud_root.visible = _game_started and not _menu_open

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
	ammo_magazine.text = str(magazine)
	ammo_reserve.text = str(int(snapshot.get("ammo_reserve", 90)))
	ammo_magazine.add_theme_color_override(
		"font_color",
		AMMO_WARNING_COLOR if magazine <= 5 else AMMO_NORMAL_COLOR
	)

	round_state_label.text = "CT %d    %s    %d T" % [
		int(snapshot.get("friendly_score", 0)),
		String(snapshot.get("round_time", "1:55")),
		int(snapshot.get("enemy_score", 0)),
	]
	level_name_label.text = "%d 存活                 %d 存活" % [
		int(snapshot.get("enemy_alive", 0)),
		int(snapshot.get("friendly_alive", 1)),
	]
	var bomb: Dictionary = snapshot.get("bomb", {}) as Dictionary
	objective_status.text = String(snapshot.get("round_label", ""))
	if bool(bomb.get("bomb_planted", false)):
		objective_status.text = "C4已安装 · %s区" % String(bomb.get("bomb_site", "A"))
	elif bool(bomb.get("bomb_carried", false)) and String(snapshot.get("player_team", "T")) == "T":
		objective_status.text += "  ·  E安装C4"
	var interaction_type := String(bomb.get("interaction_type", ""))
	objective_interaction.visible = hud_root.visible and not interaction_type.is_empty()
	if objective_interaction.visible:
		objective_interaction_label.text = "正在安装 C4" if interaction_type == "plant" else "正在拆除 C4"
		objective_interaction_progress.value = float(bomb.get("interaction_progress", 0.0)) * 100.0
	stats_label.text = "$%d" % int(snapshot.get("money", 800))
	scoreboard_friendly.text = "你                                %d          %d          $%d" % [
		int(snapshot.get("kill_count", 0)),
		int(snapshot.get("hit_count", 0)),
		int(snapshot.get("money", 800)),
	]
	scoreboard_enemy.text = "训练目标                          %d 存活" % int(snapshot.get("enemy_alive", 0))
	training_end.visible = bool(snapshot.get("training_complete", false)) and _game_started and not _menu_open
	var result_text := String(snapshot.get("round_result_text", ""))
	training_summary.text = "%s\n%d 次命中   %d 次击杀\n$%d" % [
		result_text if not result_text.is_empty() else "训练完成",
		int(snapshot.get("hit_count", 0)),
		int(snapshot.get("kill_count", 0)),
		int(snapshot.get("money", 800)),
	]
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
	get_tree().create_timer(4.5).timeout.connect(func() -> void:
		if is_instance_valid(entry):
			entry.queue_free()
	)

func set_buy_menu_visible(visible_state: bool) -> void:
	buy_menu.visible = visible_state and _game_started and not _menu_open
	if visible_state:
		buy_result.text = ""

func show_purchase_result(message: String) -> void:
	buy_result.text = message
