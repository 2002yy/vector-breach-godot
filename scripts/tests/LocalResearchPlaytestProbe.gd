extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const LEVEL_IDS := ["dustline-depths", "dustline-depths-original-local"]


func _ready() -> void:
	var results: Array = []
	var all_passed := true
	for level_id in LEVEL_IDS:
		GameState.reset_runtime_state()
		RoundManager.set_warmup()
		var main := MAIN_SCENE.instantiate() as Node3D
		add_child(main)
		await get_tree().physics_frame
		var map_index := int(main.call("find_level_option_index", level_id))
		if map_index < 0:
			push_error("Local research map unavailable: " + level_id)
			get_tree().quit(1)
			return
		main.call("_on_map_selected", map_index)
		await get_tree().process_frame
		var menu_image := await _capture(level_id + "-play-menu")
		await main.call("_on_start_pressed")
		var sandbox := main.get_node("CombatSandbox")
		var match_count_ok := (
			sandbox.get_child_count() == 9
			and GameState.friendly_alive == 5
			and GameState.enemy_alive == 5
		)
		var freeze_ok := (
			RoundManager.time_remaining > 55.0
			and RoundManager.state == RoundManager.RoundState.FREEZE
		)
		var buy_image := await _capture(level_id + "-buy-opening")
		GameState.player_money = 4000
		main.call("_purchase_item", "rifle")
		main.call("_on_player_ready")
		var ready_ok := (
			RoundManager.state == RoundManager.RoundState.LIVE
			and not bool(main.get("_buy_menu_open"))
		)
		for actor in sandbox.get_children():
			actor.get_node("TacticalBotBrain").set("enabled", false)
		var player := main.get_node("Player") as CharacterBody3D
		player.call("set_mouse_capture_enabled", false)
		for _frame in range(20):
			await get_tree().physics_frame
		var start_position := player.global_position
		var spawn_on_floor := player.is_on_floor()
		var spawn_image := await _capture(level_id + "-play-spawn")
		Input.action_press("move_forward")
		for _frame in range(30):
			await get_tree().physics_frame
		Input.action_release("move_forward")
		var moved_distance := (
			Vector2(player.global_position.x, player.global_position.z)
			. distance_to(Vector2(start_position.x, start_position.z))
		)
		var weapon := main.get_node("WeaponSystem")
		var rifle_owned := bool(weapon.call("is_slot_owned", 0))
		var pistol_owned := bool(weapon.call("is_slot_owned", 1))
		var targets := main.get_node("CombatSandbox").get_children()
		var damaged_target := false
		if not targets.is_empty():
			var target := targets[0] as CharacterBody3D
			for candidate in targets:
				if String(candidate.get("team")) != GameState.player_team:
					target = candidate as CharacterBody3D
					break
			target.global_position = player.global_position - player.global_transform.basis.z * 3.0
			player.velocity = Vector3.ZERO
			player.set_physics_process(false)
			var camera := player.call("get_camera_node") as Camera3D
			camera.look_at(target.global_position + Vector3.UP * 0.18, Vector3.UP)
			var health_before := int(target.get("current_health"))
			for _frame in range(12):
				await get_tree().physics_frame
			weapon.call("try_fire", player)
			damaged_target = int(target.get("current_health")) < health_before
		var ammo_after := int(
			(weapon.call("get_runtime_snapshot") as Dictionary).get("ammo_in_mag", 30)
		)
		weapon.call("switch_to_slot", 1)
		for _frame in range(25):
			await get_tree().physics_frame
		var pistol_selected := (
			int((weapon.call("get_runtime_snapshot") as Dictionary).get("weapon_slot", -1)) == 1
		)
		var objectives: Array = (
			(main.get_node("Level").get("_current_level_data") as Dictionary).get("objectives", [])
		)
		var bomb_loop_ok := false
		if not objectives.is_empty():
			var site: Dictionary = objectives[0]
			player.global_position = Vector3(float(site["x"]), float(site["y"]), float(site["z"]))
			Input.action_press("interact")
			main.call("_update_objective_interaction", 3.3)
			Input.action_release("interact")
			var planted := RoundManager.state == RoundManager.RoundState.BOMB_PLANTED
			GameState.player_team = "CT"
			GameState.player_defuse_kit = true
			Input.action_press("interact")
			main.call("_update_objective_interaction", 5.1)
			Input.action_release("interact")
			bomb_loop_ok = planted and RoundManager.round_reason == "BOMB DEFUSED"
		var passed := (
			match_count_ok
			and freeze_ok
			and ready_ok
			and bomb_loop_ok
			and spawn_on_floor
			and moved_distance > 0.2
			and rifle_owned
			and pistol_owned
			and damaged_target
			and ammo_after == 29
			and pistol_selected
		)
		all_passed = all_passed and passed
		results.append(
			{
				"level": level_id,
				"passed": passed,
				"menu": menu_image,
				"spawn": spawn_image,
				"spawn_on_floor": spawn_on_floor,
				"moved_meters": moved_distance,
				"rifle_owned": rifle_owned,
				"pistol_owned": pistol_owned,
				"rifle_ammo_after_shot": ammo_after,
				"target_damaged": damaged_target,
				"pistol_selected": pistol_selected,
				"target_count": targets.size(),
				"mode": "controlled_5v5_bomb_match",
				"roster_ok": match_count_ok,
				"freeze_ok": freeze_ok,
				"ready_ok": ready_ok,
				"buy_opening": buy_image,
				"bomb_loop_ok": bomb_loop_ok
			}
		)
		main.queue_free()
		for _frame in range(3):
			await get_tree().physics_frame
	print("LOCAL_RESEARCH_PLAYTEST=" + JSON.stringify(results))
	get_tree().quit(0 if all_passed else 1)


func _capture(stem: String) -> String:
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("user://%s.png" % stem)
	return output if get_viewport().get_texture().get_image().save_png(output) == OK else ""
