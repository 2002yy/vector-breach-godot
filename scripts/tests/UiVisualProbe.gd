extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "foundry-reforged"

func _ready() -> void:
	print("UI_PROBE_STAGE=instantiate_main")
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	print("UI_PROBE_STAGE=await_main_frames")
	for _frame in range(4):
		await get_tree().process_frame

	print("UI_PROBE_STAGE=select_map")
	var target_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if target_index < 0:
		push_error("UI visual probe could not find Foundry Reforged")
		get_tree().quit(1)
		return
	var map_select: OptionButton = main.get_node("StartMenu/MenuPanel/Margin/VBox/Controls/MapRow/MapSelect")
	map_select.select(target_index)
	main.call("_on_map_selected", target_index)
	await get_tree().process_frame
	print("UI_PROBE_STAGE=capture_menu")
	var menu_path := await _capture("ui-menu-reference")

	print("UI_PROBE_STAGE=start_combat")
	main.call("_on_start_pressed")
	for _frame in range(12):
		await get_tree().physics_frame
	main.set_process(false)
	GameState.player_health = 76
	GameState.sync_weapon_state("\u6b65\u67aa", 8, 52, "", 0.35, 0.22, 0)
	GameState.register_hit(false)
	GameState.register_hit(true)
	main.get_node("CombatHud").call("update_display", GameState.get_hud_snapshot())
	await get_tree().process_frame
	main.get_node("CombatHud").call("set_buy_menu_visible", true)
	print("UI_PROBE_STAGE=capture_buy_menu")
	var buy_menu_path := await _capture("ui-buy-menu-reference")
	main.get_node("CombatHud").call("set_buy_menu_visible", false)
	print("UI_PROBE_STAGE=capture_combat")
	var combat_path := await _capture("ui-combat-reference")
	Input.action_press("show_scoreboard")
	await get_tree().process_frame
	print("UI_PROBE_STAGE=capture_scoreboard")
	var scoreboard_path := await _capture("ui-scoreboard-reference")
	Input.action_release("show_scoreboard")

	print("UI_VISUAL_PROBE=" + JSON.stringify({
		"menu": menu_path,
		"buy_menu": buy_menu_path,
		"combat": combat_path,
		"scoreboard": scoreboard_path,
		"viewport": [get_viewport().size.x, get_viewport().size.y]
	}))
	get_tree().quit(0 if not menu_path.is_empty() and not buy_menu_path.is_empty() and not combat_path.is_empty() and not scoreboard_path.is_empty() else 1)

func _capture(file_stem: String) -> String:
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://%s.png" % file_stem)
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	return output_path if save_error == OK else ""
