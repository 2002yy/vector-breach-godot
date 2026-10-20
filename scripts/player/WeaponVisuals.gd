extends RefCounted

const Official = preload("res://scripts/player/OfficialEquipment.gd")


static func build(kind: String, team: String) -> Node3D:
	var native := Official.build(kind, team)
	if native != null:
		return native
	var root := Node3D.new()
	root.set_meta("prototype_weapon", kind)
	var length := 0.85 if kind == "sniper" else (0.68 if kind == "shotgun" else 0.42)
	var receiver := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.065, 0.08, length * 0.55)
	receiver.mesh = box
	receiver.position.z = -length * 0.22
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("30372d")
	material.metallic = 0.75
	material.roughness = 0.45
	receiver.material_override = material
	root.add_child(receiver)
	var barrel := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.015
	tube.bottom_radius = 0.015
	tube.height = length * 0.55
	barrel.mesh = tube
	barrel.rotation.x = PI * 0.5
	barrel.position.z = -length * 0.72
	barrel.material_override = material
	root.add_child(barrel)
	if kind == "sniper":
		var scope := MeshInstance3D.new()
		scope.mesh = tube
		scope.scale = Vector3(1.5, 0.6, 1.5)
		scope.rotation.x = PI * 0.5
		scope.position = Vector3(0, 0.085, -0.25)
		scope.material_override = material
		root.add_child(scope)
	return root
