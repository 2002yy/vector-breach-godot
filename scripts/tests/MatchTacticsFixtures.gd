extends RefCounted


static func role_purchases(host: Node) -> void:
	var fixture: Dictionary = await host.call("_make_fixture")
	for row in [["CT", 2, 6000, 30000, "sniper"], ["T", 1, 2000, 10000, "smg"]]:
		var actor: CharacterBody3D = host.call(
			"_make_actor",
			fixture.world,
			"预算测试",
			row[0],
			Vector3(15, 1, 15),
			{"aiMoney": row[2], "aiPrimaryWeapon": "pistol"}
		)
		actor.set_physics_process(false)
		actor.set_meta("squad_role_index", row[1])
		var brain := actor.get_node("TacticalBotBrain")
		brain.set("team_money", row[3])
		brain.set("_economy_team_size", 5)
		RoundManager.start_round()
		brain.call("_tick_freeze_purchase")
		var snapshot: Dictionary = brain.call("get_snapshot")
		host.call(
			"_assert_equal", snapshot.weapon_id, row[4], "role and squad budget select weapon"
		)
		host.call("_assert_true", snapshot.money >= 0, "purchase never overspends")
		var spent := 0
		for purchase in snapshot.purchases:
			spent += int(purchase.price)
		host.call("_assert_equal", spent + snapshot.money, row[2], "receipt reconciles budget")
		brain.call("_tick_freeze_purchase")
		host.call("_assert_equal", brain.get("ai_money"), snapshot.money, "purchase is idempotent")
		brain.call("_switch_to_weapon", "knife")
		host.call(
			"_assert_equal",
			brain.call("get_weapon_pickup_record", true).weapon_id,
			row[4],
			"holding knife still preserves primary at round end"
		)
	var trader: CharacterBody3D = host.call(
		"_make_actor", fixture.world, "换枪测试", "T", Vector3(-15, 1, 15), {"aiPrimaryWeapon": "smg"}
	)
	trader.set_physics_process(false)
	var pickup := preload("res://scripts/combat/WorldWeaponPickup.gd").new()
	fixture.world.add_child(pickup)
	pickup.configure(
		{"weapon_id": "rifle", "slot_index": 0, "ammo_in_mag": 10, "ammo_reserve": 20},
		trader.global_position
	)
	var trader_brain := trader.get_node("TacticalBotBrain")
	host.call(
		"_assert_true",
		trader_brain.call("_try_pickup_weapon_nearby"),
		"bot upgrades a real primary"
	)
	host.call(
		"_assert_equal",
		trader_brain.call("get_weapon_pickup_record").ammo_in_mag,
		10,
		"AI replacement preserves incoming ammo"
	)
	for drop in host.get_tree().get_nodes_in_group("weapon_pickups"):
		if drop.get("weapon_record").get("weapon_id") == "smg":
			host.call(
				"_assert_true",
				drop.get_parent() == host.get_tree().current_scene,
				"replaced weapon stays outside the actor roster container"
			)
	for id in ["rifle", "pistol"]:
		trader_brain.get("_weapon_ammo")[id] = 0
		trader_brain.get("_weapon_reserve")[id] = 0
	trader_brain.set("ammo_in_mag", 0)
	trader_brain.call("_update_weapon_selection", 20.0)
	host.call(
		"_assert_equal",
		trader_brain.call("get_snapshot").weapon_id,
		"knife",
		"no-ammo loadout cannot enter an endless zero-reserve reload"
	)
	trader_brain.set("ai_money", 5000)
	trader_brain.set("team_money", 20000)
	trader_brain.call("_tick_freeze_purchase")
	host.call(
		"_assert_equal",
		trader_brain.call("get_weapon_pickup_record", true).ammo_in_mag,
		30,
		"freeze budget can replace an exhausted primary with a usable gun"
	)
	await host.call("_cleanup_fixture", fixture)


static func support_and_rotation(host: Node) -> void:
	var fixture: Dictionary = await host.call("_make_fixture")
	var defender: CharacterBody3D = host.call(
		"_make_actor", fixture.world, "支援", "CT", Vector3(15, 1, 15)
	)
	defender.set_physics_process(false)
	var brain := defender.get_node("TacticalBotBrain")
	brain.call("configure_objective", "defend_site", Vector3(15, 1, 0), "A")
	RoundManager.set_live()
	brain.call("notify_teammate_report", Vector3(-10, 1, 0), "CT")
	host.call(
		"_assert_equal", brain.call("get_snapshot").teammate_reports, 0, "reject friendly intel"
	)
	brain.call("notify_teammate_report", Vector3(-10, 1, 0), "T")
	host.call(
		"_assert_true", brain.call("_tick_team_support", 0.016), "report overrides passive hold"
	)
	brain.call("_tick_teammate_reports", 5.0)
	host.call(
		"_assert_true",
		not brain.call("_tick_team_support", 0.016),
		"expired report releases support"
	)
	var attacker: CharacterBody3D = host.call(
		"_make_actor", fixture.world, "转点", "T", Vector3(0, 1, 20)
	)
	attacker.set_physics_process(false)
	brain = attacker.get_node("TacticalBotBrain")
	brain.call("configure_objective", "plant", Vector3(0, 1, 0), "A", true)
	brain.set("alternate_site_target", Vector3(20, 1, 0))
	brain.set("alternate_site_label", "B")
	brain.call("notify_teammate_report", Vector3(0, 1, 1), "CT")
	RoundManager.bomb_carried = true
	brain.call("_tick_t_side_objective", 0.016)
	host.call(
		"_assert_equal", brain.get("plant_site_label"), "B", "pressure triggers carrier rotation"
	)
	RoundManager.state = RoundManager.RoundState.BOMB_PLANTED
	brain = defender.get_node("TacticalBotBrain")
	brain.set("has_defuse_kit", true)
	RoundManager.time_remaining = 4.0
	brain.call("_tick_ct_side_objective", 0.016)
	host.call(
		"_assert_true", brain.call("get_snapshot").saving_gun, "impossible defuse triggers save"
	)
	RoundManager.set_live()
	brain = attacker.get_node("TacticalBotBrain")
	brain.set("_rotated_site", false)
	brain.set("_route_progress", preload("res://scripts/ai/BotRouteProgress.gd").new())
	var progress: RefCounted = brain.get("_route_progress")
	progress.set("attempts", 3)
	brain.call("_reselect_blocked_route", attacker.global_position)
	host.call(
		"_assert_true",
		brain.call("get_snapshot").route_blocked,
		"third failed route attempt has explicit blocked outcome"
	)
	host.call(
		"_assert_equal",
		brain.get("plant_site_label"),
		"B",
		"blocked carrier reselects alternate site"
	)
	brain.call("_tick_blocked_navigation", 4.0)
	host.call(
		"_assert_true",
		not brain.call("get_snapshot").route_blocked,
		"blocked cooldown is finite and resumes evaluation"
	)
	var backup: CharacterBody3D = host.call(
		"_make_actor", fixture.world, "回收接替", "T", Vector3(10, 1, 20)
	)
	backup.set_physics_process(false)
	for candidate in [attacker, backup]:
		var candidate_brain: Node = candidate.get_node("TacticalBotBrain")
		candidate_brain.call("set_c4_device", fixture.c4)
		candidate_brain.call("configure_objective", "support", Vector3(20, 1, 0), "B", false)
	fixture.c4.call("drop_at", Vector3(0, 0, 22))
	for candidate in [attacker, backup]:
		candidate.get_node("TacticalBotBrain").call("_refresh_c4_knowledge")
	host.call(
		"_assert_true", brain.call("_is_c4_recoverer"), "nearest living recovery owner is stable"
	)
	brain.set("_route_blocked_seconds", 3.0)
	host.call(
		"_assert_true",
		backup.get_node("TacticalBotBrain").call("_is_c4_recoverer"),
		"blocked living recoverer hands C4 task to another teammate"
	)
	host.call(
		"_assert_true", not brain.call("_is_c4_recoverer"), "only one replacement owns C4 recovery"
	)
	await host.call("_cleanup_fixture", fixture)
