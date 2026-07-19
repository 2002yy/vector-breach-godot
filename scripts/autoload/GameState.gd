extends Node

signal hud_state_changed(snapshot: Dictionary)

var current_level_id: String = "depot"
var current_level_name: String = "\u4ed3\u5e93\u7ad9"
var player_spawn: Vector3 = Vector3.ZERO
var player_spawn_yaw_radians: float = 0.0

var player_health: int = 100
var player_armor: int = 0
var player_helmet: bool = false
var player_defuse_kit: bool = false
var player_money: int = 800
var current_weapon_name: String = "\u6b65\u67aa"
var current_weapon_slot: int = 0
var ammo_in_mag: int = 30
var ammo_reserve: int = 90
var weapon_status_text: String = ""
var hit_count: int = 0
var kill_count: int = 0
var current_spread_degrees: float = 0.0
var recoil_display_value: float = 0.0
var graphics_preset: String = "prototype"
var menu_open: bool = true
var game_started: bool = false
var friendly_score: int = 0
var enemy_score: int = 0
var friendly_alive: int = 1
var enemy_alive: int = 0
var initial_friendly_count: int = 1
var initial_target_count: int = 0
var training_complete: bool = false
var player_team: String = "T"
var round_result_text: String = ""
var loss_streak: int = 0
const MAX_MONEY := 16000
const LOSS_BONUSES := [1400, 1900, 2400, 2900, 3400]

func set_level(level_id: String, level_name: String = "") -> void:
	var changed := current_level_id != level_id
	current_level_id = level_id
	if not level_name.is_empty():
		changed = changed or current_level_name != level_name
		current_level_name = level_name
	if changed:
		_emit_hud_state_changed()

func reset_runtime_state() -> void:
	player_health = 100
	player_armor = 0
	player_helmet = false
	player_defuse_kit = false
	player_money = 800
	current_weapon_name = "\u6b65\u67aa"
	current_weapon_slot = 0
	ammo_in_mag = 30
	ammo_reserve = 90
	weapon_status_text = ""
	hit_count = 0
	kill_count = 0
	current_spread_degrees = 0.0
	recoil_display_value = 0.0
	friendly_score = 0
	enemy_score = 0
	friendly_alive = initial_friendly_count
	enemy_alive = initial_target_count
	training_complete = false
	round_result_text = ""
	loss_streak = 0
	_emit_hud_state_changed()

func prepare_next_round() -> void:
	if friendly_alive == 0:
		player_armor = 0
		player_helmet = false
		player_defuse_kit = false
	player_health = 100
	friendly_alive = initial_friendly_count
	enemy_alive = initial_target_count
	training_complete = false
	round_result_text = ""
	_emit_hud_state_changed()

func purchase(item_id: String) -> Dictionary:
	if not RoundManager.can_buy():
		return {"success": false, "reason": "只能在冻结期购买"}
	var prices := {"rifle": 2700, "pistol": 500, "armor": 650, "helmet": 350, "armor_helmet": 1000, "defuse_kit": 400, "he_grenade": 300, "flash_grenade": 200, "smoke_grenade": 300}
	if not prices.has(item_id):
		return {"success": false, "reason": "未知商品"}
	if item_id == "defuse_kit" and player_team != "CT":
		return {"success": false, "reason": "只有 CT 可以购买拆弹钳"}
	if item_id == "defuse_kit" and player_defuse_kit:
		return {"success": false, "reason": "已拥有拆弹钳"}
	if item_id == "armor" and player_armor >= 100:
		return {"success": false, "reason": "护甲已满"}
	if item_id == "armor_helmet" and player_armor >= 100 and player_helmet:
		return {"success": false, "reason": "护甲与头盔已齐全"}
	if item_id == "helmet" and player_helmet:
		return {"success": false, "reason": "已拥有头盔"}
	var price := int(prices[item_id])
	if item_id == "armor":
		price = ceili(float(100 - player_armor) * 6.5)
	elif item_id == "armor_helmet":
		price = ceili(float(100 - player_armor) * 6.5) + (0 if player_helmet else 350)
	if player_money < price:
		return {"success": false, "reason": "金钱不足"}
	player_money -= price
	if item_id in ["armor", "armor_helmet"]:
		player_armor = 100
	if item_id in ["helmet", "armor_helmet"]:
		player_helmet = true
	if item_id == "defuse_kit":
		player_defuse_kit = true
	_emit_hud_state_changed()
	return {"success": true, "price": price, "item_id": item_id}

func complete_round(winner: String, reason: String) -> void:
	if winner == "T":
		enemy_score += 1
	else:
		friendly_score += 1
	var player_won := winner == player_team
	if player_won:
		loss_streak = 0
		player_money = mini(MAX_MONEY, player_money + 3250)
	else:
		var loss_bonus := int(LOSS_BONUSES[mini(loss_streak, LOSS_BONUSES.size() - 1)])
		loss_streak = mini(loss_streak + 1, LOSS_BONUSES.size() - 1)
		if player_team == "T" and not RoundManager.bomb_site.is_empty():
			loss_bonus += 800
		player_money = mini(MAX_MONEY, player_money + loss_bonus)
	var reason_labels := {"ELIMINATION": "全员淘汰", "TIME": "时间耗尽", "BOMB EXPLODED": "C4爆炸", "BOMB DEFUSED": "C4已拆除"}
	round_result_text = "%s 获胜  ·  %s" % [winner, String(reason_labels.get(reason, reason))]
	training_complete = true
	_emit_hud_state_changed()

func set_training_target_count(count: int) -> void:
	initial_target_count = maxi(0, count)
	enemy_alive = initial_target_count
	training_complete = initial_target_count == 0
	_emit_hud_state_changed()

func set_combatant_counts(friendly_extra: int, enemy_count: int) -> void:
	initial_friendly_count = 1 + maxi(0, friendly_extra)
	initial_target_count = maxi(0, enemy_count)
	friendly_alive = initial_friendly_count
	enemy_alive = initial_target_count
	training_complete = initial_target_count == 0
	_emit_hud_state_changed()

func notify_player_vitals_changed() -> void:
	_emit_hud_state_changed()

func set_graphics_preset(preset: String) -> void:
	graphics_preset = preset.to_lower()

func set_menu_state(opened: bool) -> void:
	if menu_open == opened:
		return
	menu_open = opened
	_emit_hud_state_changed()

func set_game_started(started: bool) -> void:
	if game_started == started:
		return
	game_started = started
	_emit_hud_state_changed()

func get_shape_build_options() -> Dictionary:
	match graphics_preset:
		"low":
			return {
				"graphics_preset": "low",
				"arena_bounds_enabled": true,
				"arena_floor_enabled": true,
				"ramp_segments": 3,
				"catwalk_support_visuals": false
			}
		"medium":
			return {
				"graphics_preset": "medium",
				"arena_bounds_enabled": true,
				"arena_floor_enabled": true,
				"ramp_segments": 4,
				"catwalk_support_visuals": true
			}
		_:
			return {
				"graphics_preset": "prototype",
				"arena_bounds_enabled": true,
				"arena_floor_enabled": true,
				"ramp_segments": 6,
				"catwalk_support_visuals": true
			}

func get_graphics_preset_label() -> String:
	match graphics_preset:
		"low":
			return "\u4f4e"
		"medium":
			return "\u4e2d"
		_:
			return "\u539f\u578b"

func get_hud_snapshot() -> Dictionary:
	return {
		"health": player_health,
		"armor": player_armor,
		"helmet": player_helmet,
		"defuse_kit": player_defuse_kit,
		"money": player_money,
		"weapon_name": current_weapon_name,
		"weapon_slot": current_weapon_slot,
		"ammo_in_mag": ammo_in_mag,
		"ammo_reserve": ammo_reserve,
		"weapon_status_text": weapon_status_text,
		"hit_count": hit_count,
		"kill_count": kill_count,
		"spread_degrees": current_spread_degrees,
		"recoil_display_value": recoil_display_value,
		"level_name": current_level_name,
		"game_started": game_started,
		"menu_open": menu_open,
		"round_state": RoundManager.get_state_name(),
		"round_label": RoundManager.get_state_label(),
		"round_time": RoundManager.get_time_label(),
		"friendly_score": friendly_score,
		"enemy_score": enemy_score,
		"friendly_alive": friendly_alive,
		"enemy_alive": enemy_alive,
		"training_complete": training_complete,
		"player_team": player_team,
		"round_result_text": round_result_text,
		"bomb": RoundManager.get_objective_snapshot(),
	}

func sync_weapon_state(weapon_name: String, next_ammo_in_mag: int, next_ammo_reserve: int, status_text: String = "", spread_degrees: float = 0.0, recoil_value: float = 0.0, slot_index: int = 0) -> void:
	var changed := (
		current_weapon_name != weapon_name
		or current_weapon_slot != slot_index
		or ammo_in_mag != next_ammo_in_mag
		or ammo_reserve != next_ammo_reserve
		or weapon_status_text != status_text
		or not is_equal_approx(current_spread_degrees, spread_degrees)
		or not is_equal_approx(recoil_display_value, recoil_value)
	)
	current_weapon_name = weapon_name
	current_weapon_slot = slot_index
	ammo_in_mag = next_ammo_in_mag
	ammo_reserve = next_ammo_reserve
	weapon_status_text = status_text
	current_spread_degrees = spread_degrees
	recoil_display_value = recoil_value
	if changed:
		_emit_hud_state_changed()

func register_hit(killed: bool, weapon_id: String = "rifle", target_team: String = "") -> void:
	hit_count += 1
	if killed:
		if not target_team.is_empty() and target_team == player_team:
			friendly_alive = maxi(0, friendly_alive - 1)
		else:
			kill_count += 1
			var rewards := {"rifle": 300, "pistol": 300, "knife": 1500, "he_grenade": 300}
			player_money = mini(MAX_MONEY, player_money + int(rewards.get(weapon_id, 300)))
			enemy_alive = maxi(0, enemy_alive - 1)
	_emit_hud_state_changed()

func reward_objective_action(action: String) -> void:
	var reward := 300 if action == "plant" else 0
	player_money = mini(MAX_MONEY, player_money + reward)
	_emit_hud_state_changed()

func _emit_hud_state_changed() -> void:
	hud_state_changed.emit(get_hud_snapshot())
