extends CanvasLayer

const HEALTH_NORMAL_COLOR := Color(0.88, 0.82, 0.54, 1.0)
const HEALTH_WARNING_COLOR := Color(1.0, 0.38, 0.3, 1.0)
const AMMO_NORMAL_COLOR := Color(0.88, 0.82, 0.54, 1.0)
const AMMO_WARNING_COLOR := Color(1.0, 0.38, 0.3, 1.0)

@onready var hud_root: Control = $HudRoot
@onready var health_value: Label = $HudRoot/BottomLeft/Margin/Row/HealthText/Value
@onready var weapon_label: Label = $HudRoot/BottomRight/Margin/Row/WeaponBlock/Weapon
@onready var weapon_status_label: Label = $HudRoot/BottomRight/Margin/Row/WeaponBlock/Status
@onready var ammo_magazine: Label = $HudRoot/BottomRight/Margin/Row/AmmoMagazine
@onready var ammo_reserve: Label = $HudRoot/BottomRight/Margin/Row/AmmoReserve
@onready var round_state_label: Label = $HudRoot/TopCenter/Margin/Stack/RoundState
@onready var level_name_label: Label = $HudRoot/TopCenter/Margin/Stack/LevelName
@onready var stats_label: Label = $HudRoot/TopRight/Margin/Stats
@onready var crosshair_top: ColorRect = $HudRoot/Crosshair/Top
@onready var crosshair_bottom: ColorRect = $HudRoot/Crosshair/Bottom
@onready var crosshair_left: ColorRect = $HudRoot/Crosshair/Left
@onready var crosshair_right: ColorRect = $HudRoot/Crosshair/Right

@export var crosshair_gap_base: float = 7.0
@export var crosshair_gap_per_degree: float = 4.0

func update_display(snapshot: Dictionary) -> void:
	var game_started := bool(snapshot.get("game_started", false))
	var menu_open := bool(snapshot.get("menu_open", true))
	hud_root.visible = game_started and not menu_open

	var health := int(snapshot.get("health", 100))
	health_value.text = str(health)
	health_value.add_theme_color_override(
		"font_color",
		HEALTH_WARNING_COLOR if health <= 25 else HEALTH_NORMAL_COLOR
	)

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

	round_state_label.text = String(snapshot.get("round_state", "Warmup")).to_upper()
	level_name_label.text = String(snapshot.get("level_name", "VECTOR BREACH")).to_upper()
	stats_label.text = "HITS %d    KILLS %d" % [
		int(snapshot.get("hit_count", 0)),
		int(snapshot.get("kill_count", 0))
	]
	_update_crosshair(float(snapshot.get("spread_degrees", 0.0)))

func _update_crosshair(spread_degrees: float) -> void:
	var gap := crosshair_gap_base + spread_degrees * crosshair_gap_per_degree
	crosshair_top.position = Vector2(-crosshair_top.size.x * 0.5, -gap - crosshair_top.size.y)
	crosshair_bottom.position = Vector2(-crosshair_bottom.size.x * 0.5, gap)
	crosshair_left.position = Vector2(-gap - crosshair_left.size.x, -crosshair_left.size.y * 0.5)
	crosshair_right.position = Vector2(gap, -crosshair_right.size.y * 0.5)
