extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "core-vault"

func _ready() -> void:
	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var target_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if target_index < 0:
		push_error("Core Vault visual probe could not find its map option")
		get_tree().quit(1)
		return
	main.call("_on_map_selected", target_index)
	main.call("_on_start_pressed")
	for _frame in range(12):
		await get_tree().physics_frame

	var player: CharacterBody3D = main.get_node("Player")
	var level: Node3D = main.get_node("Level")
	var level_data: Dictionary = level.call("get_current_level_data")
	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	var images := {
		"spawn": await _capture_view(player, "spawn", Vector3(0.0, 1.05, 50.0), Vector3(0.0, 1.2, 27.0)),
		"north": await _capture_view(player, "north", Vector3(-16.0, 1.05, 35.0), Vector3(-16.0, 1.2, 14.0)),
		"core": await _capture_view(player, "core", Vector3(0.0, 1.05, 10.0), Vector3(0.0, 1.7, 0.0)),
		"core_flank": await _capture_view(player, "core-flank", Vector3(-10.0, 1.05, 8.0), Vector3(0.0, 1.7, 0.0)),
		"south": await _capture_view(player, "south", Vector3(0.0, 1.05, -22.0), Vector3(0.0, 1.2, -39.0)),
		"exit": await _capture_view(player, "exit", Vector3(0.0, 1.05, -39.0), Vector3(0.0, 1.2, -54.0)),
	}
	var images_saved := true
	for image_variant in images.values():
		images_saved = images_saved and not String(image_variant).is_empty()
	var visual_root: Node3D = level.get_node("VisualRoot")
	print("CORE_VAULT_VISUAL_PROBE=" + JSON.stringify({
		"level": String(level_data.get("id", "")),
		"revision": String(level_data.get("designRevision", "")),
		"playerOnFloor": player.is_on_floor(),
		"visualScenes": visual_root.get_child_count(),
		"images": images,
	}))
	get_tree().quit(0 if images_saved and visual_root.get_child_count() == 1 else 1)

func _capture_view(
	player: CharacterBody3D,
	label: String,
	position: Vector3,
	target: Vector3
) -> String:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.look_at(target, Vector3.UP)
	var camera_pivot: Node3D = player.get_node("CameraPivot")
	camera_pivot.rotation.x = 0.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://core-vault-%s-first-person.png" % label)
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	return output_path if save_error == OK else ""
