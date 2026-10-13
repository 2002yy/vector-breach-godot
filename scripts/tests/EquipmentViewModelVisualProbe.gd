extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")


func _ready() -> void:
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	for _frame in range(4):
		await get_tree().physics_frame
	main.call("_on_start_pressed")
	for _frame in range(10):
		await get_tree().physics_frame
	GameState.player_money = 4000
	for kind in ["he_grenade", "flash_grenade", "smoke_grenade"]:
		main.call("_purchase_item", kind)
	main.call("_on_player_ready")
	main.set_process(false)
	for bot in get_tree().get_nodes_in_group("combat_actors"):
		bot.set_process(false)
		bot.set_physics_process(false)
	var equipment: Node = main.get_node("TacticalEquipment")
	var view: Node = main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var results: Array = []
	var contract_ok := true
	for kind in ["knife", "he_grenade", "flash_grenade", "smoke_grenade", "c4"]:
		if kind == "knife":
			equipment.call("select_knife")
		elif kind == "c4":
			equipment.call("select_c4")
		else:
			equipment.call("select_next_grenade")
		for _frame in range(8):
			await get_tree().process_frame
		main.call("_update_ui", true)
		var state: Dictionary = view.call("get_debug_snapshot")
		var path := await _capture("equipment-%s" % kind)
		contract_ok = (
			contract_ok and state.get("visible_equipment") == [kind] and not path.is_empty()
		)
		results.append({"kind": kind, "view": state, "image": path})
	var player: CharacterBody3D = main.get_node("Player")
	var targets: Array = (main.call("_build_radar_snapshot") as Dictionary).get("targets", [])
	var target: Dictionary = targets[0]
	player.global_position.x = float(target.get("x", 0.0))
	player.global_position.z = float(target.get("z", 0.0))
	player.set_physics_process(false)
	var c4: Node3D = main.get_node("C4Device")
	var camera: Camera3D = player.call("get_camera_node")
	var origin := player.global_position - Vector3(0, 0.82, 1)
	c4.call("drop_at", origin)
	RoundManager.bomb_carried = false
	equipment.call("select_knife")
	camera.look_at(origin + Vector3.UP * 0.1)
	main.call("_update_ui", true)
	results.append({"kind": "pickup", "image": await _capture("equipment-c4-pickup")})
	main.call("_try_begin_objective_interaction")
	equipment.call("select_c4")
	Input.action_press("fire_primary")
	main.call("_update_objective_interaction", 1.0)
	main.call("_update_ui", true)
	results.append({"kind": "plant-progress", "image": await _capture("equipment-c4-progress")})
	main.call("_update_objective_interaction", 2.3)
	Input.action_release("fire_primary")
	GameState.player_team = "CT"
	equipment.call("select_knife")
	player.global_position.z += 1.0
	camera.look_at(c4.global_position + Vector3.UP * 0.12)
	main.call("_update_ui", true)
	results.append({"kind": "defuse", "image": await _capture("equipment-c4-defuse")})
	print(
		(
			"EQUIPMENT_VIEWMODEL_VISUAL_PROBE="
			+ JSON.stringify({"contract_ok": contract_ok, "captures": results})
		)
	)
	get_tree().quit(0 if contract_ok else 1)


func _capture(stem: String) -> String:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("user://%s.png" % stem)
	return path if get_viewport().get_texture().get_image().save_png(path) == OK else ""
