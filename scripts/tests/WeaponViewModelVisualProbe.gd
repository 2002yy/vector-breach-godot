extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "foundry-reforged"

func _ready() -> void:
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	for _frame in range(4):
		await get_tree().process_frame
	var target_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if target_index < 0:
		push_error("Weapon view-model probe could not find Foundry Reforged")
		get_tree().quit(1)
		return
	main.call("_on_map_selected", target_index)
	main.call("_on_start_pressed")
	for _frame in range(10):
		await get_tree().physics_frame
	GameState.player_money = 4000
	main.call("_purchase_item", "rifle")
	main.set_process(false)
	var view_model: Node3D = main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	view_model.call("update_motion", 5.8, true, false)
	for _frame in range(6):
		await get_tree().process_frame
	view_model.call("play_shot")
	var recoil_path := await _capture("weapon-viewmodel-recoil-preview")
	view_model.call("play_reload_started")
	for _frame in range(8):
		await get_tree().process_frame
	var reload_path := await _capture("weapon-viewmodel-reload-preview")
	view_model.call("play_reload_finished")
	view_model.call("play_landing", 1.0)
	var landing_path := await _capture("weapon-viewmodel-landing-preview")
	var snapshot := view_model.call("get_debug_snapshot") as Dictionary
	var contract_ok := (
		float(snapshot.get("movement_speed", 0.0)) > 5.0
		and float(snapshot.get("landing_offset", 0.0)) > 0.0
		and not bool(snapshot.get("reload_active", true))
	)
	print("WEAPON_VIEWMODEL_VISUAL_PROBE=" + JSON.stringify({
		"recoil": recoil_path,
		"reload": reload_path,
		"landing": landing_path,
		"snapshot": snapshot,
		"contract_ok": contract_ok,
	}))
	get_tree().quit(0 if contract_ok and not recoil_path.is_empty() and not reload_path.is_empty() and not landing_path.is_empty() else 1)

func _capture(file_stem: String) -> String:
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://%s.png" % file_stem)
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	return output_path if save_error == OK else ""
