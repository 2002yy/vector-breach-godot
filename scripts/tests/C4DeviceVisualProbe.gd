extends Node

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "gatehouse"

func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Node3D
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame

	var target_index := int(main.call("find_level_option_index", TARGET_LEVEL_ID))
	if target_index < 0:
		_fail("C4 visual probe could not find Gatehouse")
		return
	main.call("_on_map_selected", target_index)
	main.call("_on_start_pressed")
	for _frame in range(12):
		await get_tree().physics_frame

	var player := main.get_node("Player") as CharacterBody3D
	var c4 := main.get_node("C4Device") as Node3D
	var weapon_view_model := main.get_node_or_null("Player/CameraPivot/Camera3D/WeaponViewModel") as Node3D
	if player == null or c4 == null:
		_fail("C4 visual probe could not resolve gameplay player/C4 nodes")
		return

	player.call("set_controls_enabled", false)
	player.set_physics_process(false)
	if weapon_view_model != null:
		weapon_view_model.visible = false

	var forward := -player.global_transform.basis.z.normalized()
	var anchor := player.global_position - Vector3.UP * 0.82 + forward * 1.45
	var camera_position := player.global_position

	RoundManager.start_round()
	RoundManager.set_live()
	c4.call("drop_at", anchor)
	var dropped := await _capture_view(player, "dropped", camera_position, anchor + Vector3.UP * 0.09)

	RoundManager.start_round()
	RoundManager.set_live()
	c4.call("plant_at", anchor, "A")
	if not RoundManager.plant_bomb("A"):
		_fail("C4 visual probe could not enter real BOMB_PLANTED state")
		return
	c4.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var planted_light := (c4.get_node("MeshRoot/StatusLight") as OmniLight3D).light_energy
	var planted := await _capture_view(player, "planted", camera_position, anchor + Vector3.UP * 0.09)

	RoundManager.time_remaining = 4.0
	c4.set("_beep_timer", 0.0)
	await get_tree().process_frame
	var urgent_light := (c4.get_node("MeshRoot/StatusLight") as OmniLight3D).light_energy
	var urgent_pitch := (c4.get_node("BeepPlayer") as AudioStreamPlayer3D).pitch_scale
	var urgent := await _capture_view(player, "urgent", camera_position, anchor + Vector3.UP * 0.09)

	var images := {
		"dropped": dropped,
		"planted": planted,
		"urgent": urgent,
	}
	var images_saved := true
	for image_variant in images.values():
		images_saved = images_saved and not String(image_variant).is_empty()
	var snapshot := {
		"level": TARGET_LEVEL_ID,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
		"images": images,
		"c4_state": String(c4.get("device_state")),
		"site": String(c4.get("site_label")),
		"planted_light_energy": planted_light,
		"urgent_light_energy": urgent_light,
		"urgent_pitch_scale": urgent_pitch,
		"time_remaining": RoundManager.time_remaining,
	}
	print("C4_VISUAL_PROBE=" + JSON.stringify(snapshot))
	get_tree().quit(0 if images_saved else 1)

func _capture_view(
	player: CharacterBody3D,
	label: String,
	position: Vector3,
	target: Vector3
) -> String:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.look_at(target, Vector3.UP)
	var camera_pivot := player.get_node("CameraPivot") as Node3D
	camera_pivot.rotation.x = 0.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://step16-c4-%s.png" % label)
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	return output_path if save_error == OK else ""

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
