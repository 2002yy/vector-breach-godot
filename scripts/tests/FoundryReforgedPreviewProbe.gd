extends Node3D

const GRAYBOX_LEVEL_SCENE = preload("res://scenes/level/GrayboxLevel.tscn")

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.1, 0.1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.68, 0.72)
	environment.ambient_light_energy = 0.72
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var level: Node3D = GRAYBOX_LEVEL_SCENE.instantiate()
	level.set("level_id", "foundry-reforged")
	add_child(level)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 104.0
	camera.position = Vector3(0.0, 82.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output_path := ProjectSettings.globalize_path("user://foundry-reforged-preview.png")
	var save_error := image.save_png(output_path)
	print("FOUNDRY_REFORGED_PREVIEW=" + JSON.stringify({
		"image": output_path,
		"saveError": save_error,
		"geometryGroups": level.get_node("GeometryRoot").get_child_count()
	}))
	get_tree().quit(0 if save_error == OK else 1)
