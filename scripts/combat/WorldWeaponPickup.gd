extends Node3D

var weapon_record: Dictionary = {}

func configure(record: Dictionary, world_position: Vector3) -> void:
	weapon_record = record.duplicate(true)
	global_position = world_position
	add_to_group("weapon_pickups")
	var id := String(weapon_record.get("weapon_id", "rifle"))
	var native := preload("res://scripts/player/OfficialEquipment.gd").build(id, GameState.player_team)
	if native == null and id in ["sniper", "smg", "shotgun"]:
		native = preload("res://scripts/player/WeaponVisuals.gd").build(id, GameState.player_team)
	if native != null:
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(native)
		holder.rotation.z = PI * 0.5
		var bounds := AABB()
		var found := false
		for mesh in native.find_children("*", "MeshInstance3D", true, false):
			var local: Transform3D = global_transform.affine_inverse() * mesh.global_transform
			var box: AABB = local * mesh.get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
		if found:
			holder.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		return
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
