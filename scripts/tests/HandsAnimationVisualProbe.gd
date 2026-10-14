extends Node


func _ready() -> void:
	var main: Node3D = preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _frame in range(4):
		await get_tree().physics_frame
	await main.call("_on_start_pressed")
	GameState.player_money = 10000
	main.call("_purchase_item", "rifle")
	main.call("_purchase_item", "he_grenade")
	main.call("_on_player_ready")
	main.set_process(false)
	for bot in get_tree().get_nodes_in_group("combat_actors"):
		bot.set_physics_process(false)
	var player: CharacterBody3D = main.get_node("Player")
	player.set_physics_process(false)
	var view: Node = main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var equipment: Node = main.get_node("TacticalEquipment")
	var actions := [
		"equip",
		"idle",
		"move",
		"shot",
		"reload",
		"pistol_reload",
		"knife",
		"knife_heavy",
		"throw",
		"plant",
		"defuse"
	]
	var records: Array = []
	var ok := true
	for action in actions:
		view.call("update_motion", 5.8 if action == "move" else 0.0, true, false)
		if action in ["knife", "knife_heavy"]:
			equipment.call("select_knife")
			view.call("play_equipment_use", action)
		elif action == "throw":
			equipment.call("select_next_grenade")
			equipment.call("use_primary", player)
		elif action in ["plant", "defuse"]:
			if action == "plant":
				equipment.call("select_c4")
			else:
				equipment.call("select_knife")
			view.call("set_objective_action", action)
		else:
			main.get_node("WeaponSystem").call(
				"switch_to_slot", 1 if action == "pistol_reload" else 0
			)
			equipment.call("select_firearm")
			if action in ["reload", "pistol_reload"]:
				view.call("play_reload_started")
			elif action == "shot":
				view.call("play_shot")
			elif action != "equip":
				(view.get("hands") as Node).call("reset_pose")
		main.call("_update_ui", true)
		var frames := 80 if action == "reload" else (55 if action == "pistol_reload" else 40)
		for frame in range(frames):
			await get_tree().process_frame
			if action == "throw":
				equipment.call("tick", 1.0 / 30.0)
			if frame in [3, 7, 20]:
				await RenderingServer.frame_post_draw
				var path := ProjectSettings.globalize_path(
					"user://hands-%s-%02d.png" % [action, frame]
				)
				ok = get_viewport().get_texture().get_image().save_png(path) == OK and ok
				records.append(
					{
						"action": action,
						"frame": frame,
						"view": view.call("get_debug_snapshot"),
						"image": path
					}
				)
		view.call("play_reload_finished")
		view.call("set_objective_action", "")
	print(
		(
			"HANDS_ANIMATION_PROBE="
			+ JSON.stringify(
				{
					"ok": ok,
					"records": records,
					"scope":
					"controlled presentation and real grenade release, not natural AI playtest"
				}
			)
		)
	)
	get_tree().quit(0 if ok else 1)
