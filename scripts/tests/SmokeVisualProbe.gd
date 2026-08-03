extends Node3D

const GRENADE_SCRIPT = preload("res://scripts/combat/GrenadeProjectile.gd")

func _ready() -> void:
	_add_environment()
	_add_floor()
	var grenade := RigidBody3D.new()
	grenade.name = "SmokeGrenadePreview"
	grenade.set_script(GRENADE_SCRIPT)
	grenade.set("grenade_type", "smoke_grenade")
	grenade.position = Vector3.ZERO
	add_child(grenade)
	grenade.call("_detonate")
	var camera := Camera3D.new()
	camera.position = Vector3(7.6, 3.2, 8.6)
	camera.fov = 43.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.3, 0.0), Vector3.UP)
	for _frame in range(85):
		await get_tree().physics_frame
	var puff_count := 0
	var first_alpha := -1.0
	for child in grenade.get_children():
		if child is MeshInstance3D and child.name.begins_with("SmokePuff"):
			puff_count += 1
			if first_alpha < 0.0:
				var material := (child as MeshInstance3D).material_override as StandardMaterial3D
				first_alpha = material.albedo_color.a if material != null else -1.0
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path("user://smoke-volume-preview.png")
	var save_error := get_viewport().get_texture().get_image().save_png(output_path)
	var smoke_contract_ok := (
		grenade.is_in_group("smoke_volumes")
		and float(grenade.get("smoke_remaining")) > 15.0
		and puff_count == 7
		and first_alpha > 0.5
	)
	print("SMOKE_VISUAL_PREVIEW=" + JSON.stringify({"image": output_path, "saved": save_error == OK, "puffs": puff_count, "alpha": first_alpha, "contract_ok": smoke_contract_ok}))
	get_tree().quit(0 if save_error == OK and smoke_contract_ok else 1)

func _add_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.065, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.46, 0.51, 0.56)
	environment.ambient_light_energy = 0.58
	world_environment.environment = environment
	add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_color = Color(0.78, 0.84, 0.9)
	key_light.light_energy = 1.2
	add_child(key_light)
	var rim_light := OmniLight3D.new()
	rim_light.position = Vector3(-2.7, 2.4, -2.0)
	rim_light.light_color = Color(0.9, 0.53, 0.28)
	rim_light.light_energy = 2.2
	rim_light.omni_range = 9.0
	add_child(rim_light)

func _add_floor() -> void:
	var floor := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(18.0, 18.0)
	floor.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.13, 0.14)
	material.metallic = 0.3
	material.roughness = 0.68
	floor.material_override = material
	add_child(floor)
