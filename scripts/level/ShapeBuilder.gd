extends RefCounted

const PASS_UNDER_DECK_HEIGHT := 0.28
const BASE_FLOOR_HEIGHT := 0.2
const BOUNDARY_WALL_THICKNESS := 1.0
const BOUNDARY_WALL_HEIGHT := 6.0
const DEFAULT_RAMP_SEGMENTS := 6

static var _material_cache: Dictionary = {}

static func build_into(parent: Node3D, level_data: Dictionary, build_options: Dictionary = {}) -> void:
	var options: Dictionary = _normalize_build_options(build_options)
	_clear_children(parent)
	if bool(options.get("arena_floor_enabled", true)):
		parent.add_child(_make_arena_floor(level_data))
	if bool(options.get("arena_bounds_enabled", true)):
		parent.add_child(_make_arena_bounds(level_data))
	_build_group(parent, level_data.get("walls", []), "wall", options)
	_build_group(parent, level_data.get("covers", []), "cover", options)
	_build_group(parent, level_data.get("floors", []), "floor", options)
	_build_group(parent, level_data.get("stairs", []), "stair", options)
	_build_group(parent, level_data.get("ramps", []), "ramp", options)
	_build_group(parent, level_data.get("catwalks", []), "catwalk", options)

static func _normalize_build_options(build_options: Dictionary) -> Dictionary:
	return {
		"graphics_preset": String(build_options.get("graphics_preset", "prototype")),
		"arena_floor_enabled": bool(build_options.get("arena_floor_enabled", true)),
		"arena_bounds_enabled": bool(build_options.get("arena_bounds_enabled", true)),
		"ramp_segments": int(build_options.get("ramp_segments", DEFAULT_RAMP_SEGMENTS)),
		"catwalk_support_visuals": bool(build_options.get("catwalk_support_visuals", true))
	}

static func _clear_children(parent: Node3D) -> void:
	for child in parent.get_children():
		child.queue_free()

static func _build_group(parent: Node3D, entries: Array, role: String, options: Dictionary) -> void:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if role == "ramp":
			parent.add_child(_make_ramp_node(entry, options))
		else:
			parent.add_child(_make_shape_node(entry, role, options))

static func _make_arena_floor(level_data: Dictionary) -> Node3D:
	var arena_size := float(level_data.get("arenaSize", 56.0))
	return _make_box_node(
		"arena_floor",
		Vector3(0.0, -BASE_FLOOR_HEIGHT * 0.5, 0.0),
		Vector3(arena_size * 2.0, BASE_FLOOR_HEIGHT, arena_size * 2.0),
		_get_cached_color_material(Color(0.19, 0.19, 0.19), 0.9, "arena_floor")
	)

static func _make_arena_bounds(level_data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ArenaBounds"
	var arena_size := float(level_data.get("arenaSize", 56.0))
	var span := arena_size * 2.0 + BOUNDARY_WALL_THICKNESS * 2.0
	var bounds_material := _get_cached_color_material(Color(0.24, 0.24, 0.24), 0.9, "arena_bounds")

	root.add_child(_make_box_node(
		"bound_north",
		Vector3(0.0, BOUNDARY_WALL_HEIGHT * 0.5, -arena_size - BOUNDARY_WALL_THICKNESS * 0.5),
		Vector3(span, BOUNDARY_WALL_HEIGHT, BOUNDARY_WALL_THICKNESS),
		bounds_material
	))
	root.add_child(_make_box_node(
		"bound_south",
		Vector3(0.0, BOUNDARY_WALL_HEIGHT * 0.5, arena_size + BOUNDARY_WALL_THICKNESS * 0.5),
		Vector3(span, BOUNDARY_WALL_HEIGHT, BOUNDARY_WALL_THICKNESS),
		bounds_material
	))
	root.add_child(_make_box_node(
		"bound_west",
		Vector3(-arena_size - BOUNDARY_WALL_THICKNESS * 0.5, BOUNDARY_WALL_HEIGHT * 0.5, 0.0),
		Vector3(BOUNDARY_WALL_THICKNESS, BOUNDARY_WALL_HEIGHT, span),
		bounds_material
	))
	root.add_child(_make_box_node(
		"bound_east",
		Vector3(arena_size + BOUNDARY_WALL_THICKNESS * 0.5, BOUNDARY_WALL_HEIGHT * 0.5, 0.0),
		Vector3(BOUNDARY_WALL_THICKNESS, BOUNDARY_WALL_HEIGHT, span),
		bounds_material
	))
	return root

static func _make_shape_node(entry: Dictionary, role: String, options: Dictionary) -> Node3D:
	var x := float(entry.get("x", 0.0))
	var z := float(entry.get("z", 0.0))
	var sx := float(entry.get("sx", 1.0))
	var sz := float(entry.get("sz", 1.0))
	var top_y := float(entry.get("h", 1.0))
	var pass_under := bool(entry.get("passUnder", false))
	var climbable := bool(entry.get("climbable", false))

	var height := top_y
	var center_y := top_y * 0.5
	if role == "catwalk" and pass_under:
		height = PASS_UNDER_DECK_HEIGHT
		center_y = top_y - PASS_UNDER_DECK_HEIGHT * 0.5
		if not bool(options.get("catwalk_support_visuals", true)):
			sx *= 0.92
			sz *= 0.92

	return _make_box_node(
		"%s_%s" % [role, str(entry.get("id", ""))],
		Vector3(x, center_y, z),
		Vector3(sx, height, sz),
		_get_role_material(role, pass_under, climbable)
	)

static func _make_ramp_node(entry: Dictionary, options: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "ramp_%s" % str(entry.get("id", ""))

	var x := float(entry.get("x", 0.0))
	var z := float(entry.get("z", 0.0))
	var sx := float(entry.get("sx", 1.0))
	var sz := float(entry.get("sz", 1.0))
	var top_y := float(entry.get("h", 1.0))
	var along_x := sx >= sz
	var total_run := sx if along_x else sz
	var cross_size := sz if along_x else sx
	var segment_count: int = maxi(1, int(options.get("ramp_segments", DEFAULT_RAMP_SEGMENTS)))
	var segment_run := total_run / float(segment_count)
	var ramp_material := _get_role_material("ramp", false, true)

	for index in range(segment_count):
		var progress: float = float(index + 1) / float(segment_count)
		var segment_height: float = max(0.08, top_y * progress)
		var offset: float = -total_run * 0.5 + segment_run * (float(index) + 0.5)
		var position: Vector3 = Vector3(x, segment_height * 0.5, z)
		var size: Vector3 = Vector3(sx, segment_height, sz)

		if along_x:
			position.x += offset
			size.x = segment_run
			size.z = cross_size
		else:
			position.z += offset
			size.x = cross_size
			size.z = segment_run

		node.add_child(_make_box_node(
			"ramp_segment_%d" % index,
			position,
			size,
			ramp_material
		))

	return node

static func _make_box_node(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	node.add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "Collision"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	node.add_child(body)

	return node

static func _get_role_material(role: String, pass_under: bool, climbable: bool) -> StandardMaterial3D:
	var cache_key := "%s|%s|%s" % [role, str(pass_under), str(climbable)]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D

	var material := StandardMaterial3D.new()
	match role:
		"wall":
			material.albedo_color = Color(0.62, 0.58, 0.52)
		"cover":
			material.albedo_color = Color(0.70, 0.52, 0.28)
		"floor":
			material.albedo_color = Color(0.52, 0.50, 0.44)
		"stair":
			material.albedo_color = Color(0.42, 0.58, 0.72)
		"ramp":
			material.albedo_color = Color(0.38, 0.66, 0.44)
		"catwalk":
			material.albedo_color = Color(0.82, 0.74, 0.34) if pass_under else Color(0.58, 0.58, 0.62)
		_:
			material.albedo_color = Color(0.75, 0.75, 0.75)
	material.roughness = 0.85 if climbable and role != "catwalk" else 0.9
	_material_cache[cache_key] = material
	return material

static func _get_cached_color_material(color: Color, roughness: float, cache_key: String) -> StandardMaterial3D:
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	_material_cache[cache_key] = material
	return material
