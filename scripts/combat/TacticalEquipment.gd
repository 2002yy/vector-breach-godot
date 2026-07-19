extends Node

const GrenadeProjectile = preload("res://scripts/combat/GrenadeProjectile.gd")

var equipped: String = "firearm"
var grenade_order := ["he_grenade", "flash_grenade", "smoke_grenade"]
var grenade_counts := {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0}
var grenade_index: int = 0
var use_cooldown: float = 0.0

func reset_loadout() -> void:
	equipped = "firearm"
	grenade_counts = {"he_grenade": 0, "flash_grenade": 0, "smoke_grenade": 0}
	grenade_index = 0
	use_cooldown = 0.0

func tick(delta: float) -> void:
	use_cooldown = maxf(0.0, use_cooldown - delta)

func select_firearm() -> void:
	equipped = "firearm"

func purchase_grenade(kind: String) -> bool:
	if not kind in grenade_order:
		return false
	var limit := 2 if kind == "flash_grenade" else 1
	if int(grenade_counts.get(kind, 0)) >= limit:
		return false
	grenade_counts[kind] = int(grenade_counts.get(kind, 0)) + 1
	return true

func select_knife() -> void:
	equipped = "knife"
	GameState.sync_weapon_state("战术刀", 0, 0, "", 0.0, 0.0, 2)

func select_next_grenade() -> bool:
	for offset in range(grenade_order.size()):
		var candidate_index := (grenade_index + offset) % grenade_order.size()
		var candidate := String(grenade_order[candidate_index])
		if int(grenade_counts.get(candidate, 0)) > 0:
			grenade_index = (candidate_index + 1) % grenade_order.size()
			equipped = candidate
			_sync_hud()
			return true
	return false

func use_primary(player: CharacterBody3D) -> Dictionary:
	if use_cooldown > 0.0:
		return {}
	if equipped == "knife":
		use_cooldown = 0.45
		return _knife_attack(player)
	if equipped in grenade_order:
		return _throw_grenade(player)
	return {}

func _knife_attack(player: CharacterBody3D) -> Dictionary:
	var camera := player.call("get_camera_node") as Camera3D
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_transform.basis.z * 2.15)
	query.exclude = [player.get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Variant = hit.get("collider", null)
	if not hit.is_empty() and collider != null and collider.has_method("apply_hitscan_damage"):
		var result := collider.call("apply_hitscan_damage", 40, hit.get("position", Vector3.ZERO), 1.0, false) as Dictionary
		if bool(result.get("hit", false)):
			GameState.register_hit(bool(result.get("killed", false)), "knife", String(result.get("target_team", "")))
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
	use_cooldown = 0.75
	var thrown_type := equipped
	if not select_next_grenade():
		select_knife()
	return {"thrown": true, "type": thrown_type}

func _sync_hud() -> void:
	var names := {"he_grenade": "高爆手雷", "flash_grenade": "闪光弹", "smoke_grenade": "烟雾弹"}
	GameState.sync_weapon_state(String(names.get(equipped, equipped)), int(grenade_counts.get(equipped, 0)), 0, "", 0.0, 0.0, 3)
