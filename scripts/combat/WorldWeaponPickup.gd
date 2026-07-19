extends Node3D

var weapon_record: Dictionary = {}

func configure(record: Dictionary, world_position: Vector3) -> void:
	weapon_record = record.duplicate(true)
	global_position = world_position
	add_to_group("weapon_pickups")
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.72, 0.09, 0.18)
	mesh.mesh = box
	mesh.rotation.y = 0.35
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.17, 0.19, 0.17)
	material.metallic = 0.55
	mesh.material_override = material
	add_child(mesh)

func can_pick_up(player_position: Vector3) -> bool:
	return global_position.distance_to(player_position) <= 1.8
