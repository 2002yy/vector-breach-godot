extends Node3D

const ACTOR_SCENE = preload("res://scenes/combat/TacticalActor.tscn")

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.055, 0.070, 0.090)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.56, 0.62, 0.72)
	settings.ambient_light_energy = 0.48
	environment.environment = settings
	add_child(environment)
	_add_light(Vector3(2.6, 3.7, 3.6), Color(0.82, 0.88, 1.0), 3.0)
	_add_light(Vector3(-3.0, 2.4, 2.2), Color(0.48, 0.56, 0.72), 1.1)
	_add_floor()
	_add_actor("CT preview", "CT", Vector3(-0.72, 0.96, 0.0), true)
	_add_actor("T preview", "T", Vector3(0.72, 0.96, 0.0), false)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.35, 4.6)
	camera.fov = 38.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	for _frame in range(3):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://tactical-actor-palette-preview.png")
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	print("TACTICAL_ACTOR_VISUAL_PREVIEW=" + JSON.stringify({"image": output_path, "saved": save_error == OK}))
	get_tree().quit(0 if save_error == OK else 1)

func _add_actor(label: String, team: String, position_value: Vector3, helmet: bool) -> void:
	var actor := ACTOR_SCENE.instantiate() as CharacterBody3D
	actor.position = position_value
	actor.rotation.y = PI
	add_child(actor)
	actor.call("configure_from_record", {
		"name": label, "team": team, "helmet": helmet, "aiEnabled": false,
	})

func _add_light(position_value: Vector3, color_value: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = position_value
	light.light_color = color_value
	light.light_energy = energy
	light.omni_range = 12.0
	add_child(light)

func _add_floor() -> void:
	var floor := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(20.0, 20.0)
	floor.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.11, 0.14)
	material.metallic = 0.15
	material.roughness = 0.72
	floor.material_override = material
	add_child(floor)
