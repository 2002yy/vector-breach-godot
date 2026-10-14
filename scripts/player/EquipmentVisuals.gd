extends RefCounted


# Original procedural presentation meshes; never gameplay collision authority.
static func build(kind: String, held: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = kind.to_pascal_case() + "Model"
	var steel := _material(Color(0.48, 0.55, 0.6), 0.8)
	var rubber := _material(Color(0.035, 0.042, 0.05))
	if kind == "knife":
		_box(root, Vector3(0, -0.06, 0), Vector3(0.043, 0.14, 0.036), rubber)
		for index in range(5):
			_box(root, Vector3(0, -0.015 - index * 0.023, 0), Vector3(0.048, 0.008, 0.041), steel)
		_box(root, Vector3.ZERO, Vector3(0.11, 0.012, 0.046), steel)
		var blade := SurfaceTool.new()
		blade.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points := [
			Vector3(-0.028, 0.015, 0),
			Vector3(0.028, 0.015, 0),
			Vector3(0.023, 0.18, 0),
			Vector3(-0.018, 0.245, 0)
		]
		for side in [-1.0, 1.0]:
			for index in [0, 1, 2, 0, 2, 3] if side > 0 else [2, 1, 0, 3, 2, 0]:
				blade.add_vertex(points[index] + Vector3(0, 0, side * 0.004))
		for index in range(4):
			var next := (index + 1) % 4
			for point in [
				points[index] + Vector3(0, 0, -0.004),
				points[next] + Vector3(0, 0, -0.004),
				points[next] + Vector3(0, 0, 0.004),
				points[index] + Vector3(0, 0, -0.004),
				points[next] + Vector3(0, 0, 0.004),
				points[index] + Vector3(0, 0, 0.004)
			]:
				blade.add_vertex(point)
		blade.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = blade.commit()
		mesh.material_override = steel
		root.add_child(mesh)
	else:
		var color := (
			Color(0.21, 0.29, 0.12)
			if kind == "he_grenade"
			else (Color(0.65, 0.69, 0.73) if kind == "flash_grenade" else Color(0.24, 0.32, 0.28))
		)
		var band := (
			Color(0.95, 0.55, 0.08)
			if kind == "he_grenade"
			else (Color(0.12, 0.55, 0.92) if kind == "flash_grenade" else Color(0.83, 0.85, 0.8))
		)
		var height := 0.14 if kind == "he_grenade" else 0.19
		_cylinder(root, Vector3.ZERO, 0.052, height, _material(color, 0.35))
		for y in [-height * 0.36, height * 0.36]:
			_cylinder(root, Vector3(0, y, 0), 0.054, 0.018, _material(band))
		_cylinder(root, Vector3(0, height * 0.5 + 0.014, 0), 0.031, 0.028, steel)
		_box(root, Vector3(0.044, 0.025, 0), Vector3(0.018, height + 0.035, 0.026), steel)
		root.get_child(root.get_child_count() - 1).name = "SafetyLever"
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.012
		torus.outer_radius = 0.019
		torus.rings = 12
		torus.ring_segments = 8
		ring.mesh = torus
		ring.name = "SafetyRing"
		ring.material_override = steel
		ring.position = Vector3(-0.034, height * 0.5 + 0.017, 0)
		ring.rotation.x = PI * 0.5
		root.add_child(ring)
	if held:
		_box(root, Vector3(0, -0.1, 0.034), Vector3(0.075, 0.065, 0.07), rubber)
		_box(
			root,
			Vector3(0, -0.18, 0.05),
			Vector3(0.08, 0.12, 0.075),
			_material(Color(0.12, 0.16, 0.18))
		)
	return root


static func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.42 if metallic > 0 else 0.75
	return material


static func _box(root: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_part(root, at, mesh, material)


static func _cylinder(
	root: Node3D, at: Vector3, radius: float, height: float, material: Material
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	_part(root, at, mesh, material)


static func _part(root: Node3D, at: Vector3, mesh: Mesh, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	root.add_child(part)
