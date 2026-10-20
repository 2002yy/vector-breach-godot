extends "res://scripts/tests/CharacterVisualProbe.gd"


func _capture(label: String) -> void:
	await super._capture(label)
	if label != "actors-idle":
		return
	var light := find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var camera := find_children("*", "Camera3D", true, false)[0] as Camera3D
	var light_rotation := light.rotation
	var camera_transform := camera.transform
	var views := {
		"front": Vector3(-0.35, 0, 0),
		"grazing": Vector3(-0.3, 1.2, 0),
		"back": Vector3(-0.4, PI, 0)
	}
	for name in views:
		light.rotation = views[name]
		for weight in [0.0, 1.0]:
			_set_weight(weight)
			await super._capture("lighting-%s-%d" % [name, int(weight)])
		for target in {"fbi": 0.55, "blackwolf": -2.75}:
			var x: float = {"fbi": 0.55, "blackwolf": -2.75}[target]
			camera.position = Vector3(x, 1.45, -2.2)
			camera.look_at(Vector3(x, 1.4, 0))
			for weight in [0.0, 1.0]:
				_set_weight(weight)
				await super._capture("close-%s-%s-%d" % [target, name, int(weight)])
		camera.transform = camera_transform
	light.rotation = light_rotation
	_set_weight(1.0)
	print("CHARACTER_MATERIAL_SWEEP_OK cases=18")


func _set_weight(weight: float) -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null and material.has_meta("source_character_shading_applied"):
				material.set_shader_parameter("feature_weight", weight)
