extends SceneTree
## Diagnostic source UI panels, not original-map or FPS acceptance.


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or RenderingServer.get_rendering_device() == null:
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 700)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.025, 0.03, 0.035)
	background.size = Vector2(1280, 700)
	viewport.add_child(background)
	var script = load("res://scripts/ui/RadarDisplay.gd")
	for row in 2:
		for column in 4:
			var yaw := column * PI * 0.5
			var label := Label.new()
			label.text = ("NORTH " if row == 0 else "ROTATE ") + str(column * 90)
			label.position = Vector2(35 + column * 315, 18 + row * 340)
			viewport.add_child(label)
			var radar = script.new()
			radar.position = Vector2(25 + column * 315, 48 + row * 340)
			radar.size = Vector2(280, 280)
			viewport.add_child(radar)
			(
				radar
				. set_snapshot(
					{
						"level_id": "",
						"bounds": Vector2(24, 24),
						"range_meters": 24,
						"player_position": Vector2.ZERO,
						"player_yaw": 0.0 if row == 0 else yaw,
						"view_yaw": yaw,
						"player_height": 0.0,
						"local_team": "CT",
						"players": [{"team": "CT", "alive": true, "x": -8, "z": 0, "yaw": yaw}],
						"targets": [{"label": "A", "x": 0, "z": -12}],
						"features": [],
					}
				)
			)
	for frame in 8:
		await process_frame
		RenderingServer.force_draw(false)
	var result := viewport.get_texture().get_image().save_png(args[0])
	viewport.free()
	print("RADAR_HEADING_VULKAN result=", result)
	quit(0 if result == OK else 1)
