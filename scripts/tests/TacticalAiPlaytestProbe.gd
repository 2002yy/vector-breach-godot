extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "foundry-reforged"

func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Node3D
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var map_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if map_index < 0:
		push_error("Tactical AI playtest probe could not find Foundry Reforged")
		get_tree().quit(1)
		return
	main.call("_on_map_selected", map_index)
	main.call("_on_start_pressed")
	for _frame in range(6):
		await get_tree().physics_frame

	var player := main.get_node("Player") as CharacterBody3D
	var sandbox := main.get_node("CombatSandbox") as Node3D
	var bot: CharacterBody3D
	for candidate in sandbox.get_children():
		if candidate is CharacterBody3D:
			var ai := ((candidate as CharacterBody3D).call("get_combat_snapshot") as Dictionary).get("ai", {}) as Dictionary
			if bool(ai.get("enabled", false)):
				bot = candidate as CharacterBody3D
				break
	if bot == null:
		push_error("Tactical AI playtest probe found no enabled bot")
		get_tree().quit(1)
		return

	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	player.global_position = Vector3(-40.0, 1.05, 0.0)
	player.velocity = Vector3.ZERO
	bot.global_position = Vector3(-40.0, 1.15, 6.0)
	bot.rotation.y = 0.0
	bot.velocity = Vector3.ZERO
	player.look_at(bot.global_position + Vector3.UP * 0.2, Vector3.UP)
	player.get_node("CameraPivot").rotation.x = 0.0
	player.reset_physics_interpolation()
	bot.reset_physics_interpolation()
	for _frame in range(3):
		await get_tree().physics_frame
	RoundManager.set_live()

	for _frame in range(150):
		await get_tree().physics_frame
		if GameState.player_health < 100:
			break
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://tactical-ai-foundry-engagement.png")
	var image_error := get_viewport().get_texture().get_image().save_png(output_path)
	var snapshot := bot.call("get_combat_snapshot") as Dictionary
	var ai := snapshot.get("ai", {}) as Dictionary
	var succeeded := (
		image_error == OK
		and int(ai.get("shots", 0)) > 0
		and GameState.player_health < 100
		and String(ai.get("state", "")) in ["ACQUIRE", "ENGAGE"]
	)
	print("TACTICAL_AI_PLAYTEST=" + JSON.stringify({
		"level": TARGET_LEVEL_ID,
		"bot": snapshot.get("name", ""),
		"state": ai.get("state", ""),
		"shots": ai.get("shots", 0),
		"playerHealth": GameState.player_health,
		"image": output_path,
	}))
	get_tree().quit(0 if succeeded else 1)
