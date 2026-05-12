extends CanvasLayer

@onready var health_label: Label = $Panel/Margin/VBox/Health
@onready var weapon_label: Label = $Panel/Margin/VBox/Weapon
@onready var ammo_label: Label = $Panel/Margin/VBox/Ammo
@onready var state_label: Label = $Panel/Margin/VBox/MenuState
@onready var crosshair_top: ColorRect = $Crosshair/Top
@onready var crosshair_bottom: ColorRect = $Crosshair/Bottom
@onready var crosshair_left: ColorRect = $Crosshair/Left
@onready var crosshair_right: ColorRect = $Crosshair/Right

@export var crosshair_gap_base: float = 7.0
@export var crosshair_gap_per_degree: float = 4.0

func update_display(snapshot: Dictionary) -> void:
	health_label.text = "\u751f\u547d\u503c\uff1a%d" % int(snapshot.get("health", 100))
	var weapon_status: String = String(snapshot.get("weapon_status_text", ""))
	var weapon_slot: int = int(snapshot.get("weapon_slot", 0)) + 1
	var weapon_text: String = "%d-%s" % [weapon_slot, String(snapshot.get("weapon_name", "\u6b65\u67aa"))]
	if not weapon_status.is_empty():
		weapon_text += " [%s]" % weapon_status
	weapon_label.text = "\u5f53\u524d\u6b66\u5668\uff1a%s" % weapon_text
	ammo_label.text = "\u5f39\u836f\uff1a%d / %d" % [
		int(snapshot.get("ammo_in_mag", 30)),
		int(snapshot.get("ammo_reserve", 90))
	]
	var menu_label: String = "\u5df2\u6253\u5f00" if bool(snapshot.get("menu_open", true)) else "\u5df2\u5173\u95ed"
	state_label.text = "\u72b6\u6001\uff1a%s | \u83dc\u5355\uff1a%s | \u547d\u4e2d\uff1a%d | \u51fb\u5012\uff1a%d" % [
		String(snapshot.get("round_label", "\u70ed\u8eab/\u83dc\u5355")),
		menu_label,
		int(snapshot.get("hit_count", 0)),
		int(snapshot.get("kill_count", 0))
	]
	_update_crosshair(float(snapshot.get("spread_degrees", 0.0)))

func _update_crosshair(spread_degrees: float) -> void:
	var gap: float = crosshair_gap_base + spread_degrees * crosshair_gap_per_degree
	crosshair_top.position = Vector2(-1.0, -gap - crosshair_top.size.y)
	crosshair_bottom.position = Vector2(-1.0, gap)
	crosshair_left.position = Vector2(-gap - crosshair_left.size.x, -1.0)
	crosshair_right.position = Vector2(gap, -1.0)
