extends Node

signal equipment_changed(kind: String)
signal equipment_used(kind: String)
signal melee_resolved(result: Dictionary)

const GrenadeProjectile = preload("res://scripts/combat/GrenadeProjectile.gd")
const MeleeRules = preload("res://scripts/combat/MeleeRules.gd")

var equipped: String = "firearm"
var grenade_order := ["he_grenade", "flash_grenade", "smoke_grenade", "fire_grenade"]
var grenade_counts := {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0, "fire_grenade": 0}
var grenade_index: int = 0
var use_cooldown: float = 0.0
var _pending_kind := ""
var _contact_seconds := 0.0
var _pending_player: WeakRef
var _switch_seconds := 0.0

func reset_loadout() -> void:
	cancel_use()
	equipped = "firearm"
	grenade_counts = {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0, "fire_grenade": 0}
	grenade_index = 0
	use_cooldown = 0.0
	equipment_changed.emit(equipped)

func tick(delta: float) -> void:
	use_cooldown = maxf(0.0, use_cooldown - delta)
	if _switch_seconds > 0.0:
		_switch_seconds = maxf(0.0, _switch_seconds - delta)
		if _switch_seconds == 0.0:
			if not select_next_grenade():
				select_knife()
	if not _pending_kind.is_empty():
		_contact_seconds -= delta
		if _contact_seconds <= 0.0:
			var owner: CharacterBody3D = _pending_player.get_ref() if _pending_player != null else null
			var kind := _pending_kind
			_pending_kind = ""
			if is_instance_valid(owner) and not bool(owner.get("is_dead")):
				if kind in ["knife", "knife_heavy"] and equipped == "knife":
					_knife_attack(owner, kind == "knife_heavy")
				elif equipped == kind:
					_throw_grenade(owner)

func cancel_use(cancel_selection: bool = true) -> void:
	_pending_kind = ""
	_pending_player = null
	if cancel_selection:
		_switch_seconds = 0.0

func select_firearm() -> void:
	cancel_use()
	equipped = "firearm"
	equipment_changed.emit(equipped)

func select_c4() -> void:
	cancel_use()
	equipped = "c4"
	GameState.sync_weapon_state("C4 炸药", 1, 0, "按住 E 安装（爆点内）", 0.0, 0.0, 4)
	equipment_changed.emit(equipped)

func purchase_grenade(kind: String) -> bool:
	if not kind in grenade_order:
		return false
	var total := 0
	for count in grenade_counts.values():
		total += int(count)
	if total >= 4:
		return false
	var limit := 2 if kind == "flash_grenade" else 1
	if int(grenade_counts.get(kind, 0)) >= limit:
		return false
	grenade_counts[kind] = int(grenade_counts.get(kind, 0)) + 1
	return true

func select_knife() -> void:
	cancel_use()
	equipped = "knife"
	GameState.sync_weapon_state("战术刀", 0, 0, "左键挥砍 · 右键重刺", 0.0, 0.0, 2)
	equipment_changed.emit(equipped)

func select_next_grenade() -> bool:
	for offset in range(grenade_order.size()):
		var candidate_index := (grenade_index + offset) % grenade_order.size()
		var candidate := String(grenade_order[candidate_index])
		if int(grenade_counts.get(candidate, 0)) > 0:
			cancel_use()
			grenade_index = (candidate_index + 1) % grenade_order.size()
			equipped = candidate
			_sync_hud()
			equipment_changed.emit(equipped)
			return true
	return false

func use_primary(player: CharacterBody3D) -> Dictionary:
	if use_cooldown > 0.0:
		return {}
	if equipped == "knife":
		return _queue_use(player, "knife", 0.12, 0.45)
	if equipped in grenade_order:
		if int(grenade_counts.get(equipped, 0)) > 0:
			return _queue_use(player, equipped, 0.30, 0.75)
	return {}

func use_secondary(player: CharacterBody3D) -> Dictionary:
	if equipped != "knife" or use_cooldown > 0.0:
		return {}
	return _queue_use(player, "knife_heavy", 0.22, 0.95)

func _queue_use(player: CharacterBody3D, kind: String, contact: float, cooldown: float) -> Dictionary:
	_pending_kind = kind
	_pending_player = weakref(player)
	_contact_seconds = contact
	use_cooldown = cooldown
	equipment_used.emit(kind)
	return {"queued": true, "type": kind}

func _knife_attack(player: CharacterBody3D, heavy: bool = false) -> Dictionary:
	var camera := player.call("get_camera_node") as Camera3D
	var reach := 1.85 if heavy else 2.15
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position, camera.global_position - camera.global_transform.basis.z * reach
	)
	query.exclude = [player.get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Variant = hit.get("collider", null)
	if not hit.is_empty() and collider != null and collider.has_method("apply_hitscan_damage"):
		var backstab := MeleeRules.is_backstab(player, collider)
		var result := CombatEvents.apply_damage(
			collider,
			"apply_hitscan_damage",
			[
				MeleeRules.damage(65 if heavy else 40, player, collider),
				hit.get("position", Vector3.ZERO),
				1.0,
				false,
				GameState.player_team,
				camera.global_position
			],
			CombatEvents.actor_source(player, "knife", "melee")
		)
		result["backstab"] = backstab and bool(result.get("hit", false))
		if bool(result.get("hit", false)):
			GameState.register_hit(
				bool(result.get("killed", false)), "knife", String(result.get("target_team", ""))
			)
			melee_resolved.emit(result)
		return result
	return {"hit": false}


func _throw_grenade(player: CharacterBody3D) -> Dictionary:
	var count := int(grenade_counts.get(equipped, 0))
	if count <= 0:
		return {}
	var camera := player.call("get_camera_node") as Camera3D
	var projectile := GrenadeProjectile.new()
	get_tree().current_scene.add_child(projectile)
	projectile.configure(equipped, player, camera.global_position - camera.global_transform.basis.z * 0.45, -camera.global_transform.basis.z * 13.0 + Vector3.UP * 2.2)
	grenade_counts[equipped] = count - 1
	var thrown_type := equipped
	_switch_seconds = 0.35
	_sync_hud()
	return {"thrown": true, "type": thrown_type}

func _sync_hud() -> void:
	var names := {
		"he_grenade": "高爆手雷", "flash_grenade": "闪光弹", "smoke_grenade": "烟雾弹", "fire_grenade": "燃烧弹"
	}
	GameState.sync_weapon_state(
		String(names.get(equipped, equipped)),
		int(grenade_counts.get(equipped, 0)),
		0,
		"",
		0.0,
		0.0,
		3
	)
