extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "gatehouse"

func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Node3D
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var map_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if map_index < 0:
		push_error("Tactical bomb playtest probe could not find Gatehouse")
		get_tree().quit(1)
		return
	main.call("_on_team_selected", "CT")
	main.call("_on_map_selected", map_index)
	main.call("_on_start_pressed")
	for _frame in range(6):
		await get_tree().physics_frame

	var player := main.get_node("Player") as CharacterBody3D
	var sandbox := main.get_node("CombatSandbox") as Node3D
	var c4 := main.get_node("C4Device") as Node3D
	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 1.05, -44.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var economy_modes: Array = []
	for child in sandbox.get_children():
		if child is CharacterBody3D:
			var ai := ((child as CharacterBody3D).call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
			economy_modes.append(String(ai.get("economy_mode", "")))
	for child in sandbox.get_children():
		if child.has_method("set_ai_combat_enabled"):
			child.call("set_ai_combat_enabled", false)

	var carrier: CharacterBody3D
	for child in sandbox.get_children():
		if child is CharacterBody3D and String((child as CharacterBody3D).get("team")) == "T":
			var objective := ((child as CharacterBody3D).call("get_combat_snapshot") as Dictionary).get("objective", {}) as Dictionary
			if bool(objective.get("carrier", false)):
				carrier = child as CharacterBody3D
				break
	if carrier == null:
		push_error("Tactical bomb playtest probe found no T bomb carrier")
		get_tree().quit(1)
		return
	carrier.global_position = Vector3(-13.0, 1.15, -36.0)
	carrier.velocity = Vector3.ZERO
	carrier.reset_physics_interpolation()
	RoundManager.set_live()

	var planted := false
	var plant_frames := 0
	for _frame in range(420):
		await get_tree().physics_frame
		plant_frames += 1
		if String(c4.get("device_state")) == "planted":
			planted = true
			break
	var smoke_thrown := false
	for projectile_variant in get_tree().get_nodes_in_group("grenade_projectiles"):
		if String(projectile_variant.get("grenade_type")) == "smoke_grenade":
			smoke_thrown = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var planted_image := ProjectSettings.globalize_path("user://tactical-bomb-planted.png")
	var planted_error := get_viewport().get_texture().get_image().save_png(planted_image)

	var ct_bot: CharacterBody3D
	for child in sandbox.get_children():
		if child is CharacterBody3D and String((child as CharacterBody3D).get("team")) == "CT":
			ct_bot = child as CharacterBody3D
			break
	if ct_bot != null:
		ct_bot.global_position = Vector3(c4.global_position.x, 1.15, c4.global_position.z + 2.0)
		ct_bot.velocity = Vector3.ZERO
		ct_bot.reset_physics_interpolation()

	var defused := false
	var defuse_frames := 0
	for _frame in range(600):
		await get_tree().physics_frame
		defuse_frames += 1
		if String(RoundManager.get_state_name()) == "Round End" and String(RoundManager.round_winner) == "CT":
			defused = true
			break
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var defused_image := ProjectSettings.globalize_path("user://tactical-bomb-defused.png")
	var defused_error := get_viewport().get_texture().get_image().save_png(defused_image)
	var succeeded := planted and defused and planted_error == OK and defused_error == OK
	print("TACTICAL_BOMB_PLAYTEST=" + JSON.stringify({
		"level": TARGET_LEVEL_ID,
		"carrier": carrier.get("display_name"),
		"planted": planted,
		"defused": defused,
		"roundWinner": RoundManager.round_winner,
		"plantFrames": plant_frames,
		"defuseFrames": defuse_frames,
		"economyModes": economy_modes,
		"smokeThrown": smoke_thrown,
		"plantedImage": planted_image,
		"defusedImage": defused_image,
	}))
	get_tree().quit(0 if succeeded else 1)
