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
	_build_group(parent, level_data.get("overheads", []), "overhead", options)
	_build_ladders(parent, level_data.get("ladders", []))
	_build_water_volumes(parent, level_data.get("waterVolumes", []))

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
		elif role == "overhead":
			parent.add_child(_make_overhead_node(entry))
		elif role == "catwalk" and bool(entry.get("passUnder", false)):
			parent.add_child(_make_catwalk_node(entry, options))
		elif role == "stair" and int(entry.get("steps", 1)) > 1:
			parent.add_child(_make_stair_node(entry))
		else:
			parent.add_child(_make_shape_node(entry, role, options))

static func _make_arena_floor(level_data: Dictionary) -> Node3D:
	var arena_size := float(level_data.get("arenaSize", 56.0))
	var arena_size_x := float(level_data.get("arenaSizeX", arena_size))
	var arena_size_z := float(level_data.get("arenaSizeZ", arena_size))
	return _make_box_node(
		"arena_floor",
		Vector3(0.0, -BASE_FLOOR_HEIGHT * 0.5, 0.0),
		Vector3(arena_size_x * 2.0, BASE_FLOOR_HEIGHT, arena_size_z * 2.0),
		_get_cached_color_material(Color(0.19, 0.19, 0.19), 0.9, "arena_floor")
	)

static func _make_arena_bounds(level_data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ArenaBounds"
	var arena_size := float(level_data.get("arenaSize", 56.0))
	var arena_size_x := float(level_data.get("arenaSizeX", arena_size))
	var arena_size_z := float(level_data.get("arenaSizeZ", arena_size))
	var boundary_height := float(level_data.get("boundaryHeight", BOUNDARY_WALL_HEIGHT))
	var span_x := arena_size_x * 2.0 + BOUNDARY_WALL_THICKNESS * 2.0
	var span_z := arena_size_z * 2.0 + BOUNDARY_WALL_THICKNESS * 2.0
	var bounds_material := _get_cached_color_material(Color(0.24, 0.24, 0.24), 0.9, "arena_bounds")

	root.add_child(_make_box_node(
		"bound_north",
		Vector3(0.0, boundary_height * 0.5, -arena_size_z - BOUNDARY_WALL_THICKNESS * 0.5),
		Vector3(span_x, boundary_height, BOUNDARY_WALL_THICKNESS),
		bounds_material
	))
	root.add_child(_make_box_node(
		"bound_south",
		Vector3(0.0, boundary_height * 0.5, arena_size_z + BOUNDARY_WALL_THICKNESS * 0.5),
		Vector3(span_x, boundary_height, BOUNDARY_WALL_THICKNESS),
		bounds_material
	))
	root.add_child(_make_box_node(
		"bound_west",
		Vector3(-arena_size_x - BOUNDARY_WALL_THICKNESS * 0.5, boundary_height * 0.5, 0.0),
		Vector3(BOUNDARY_WALL_THICKNESS, boundary_height, span_z),
		bounds_material
	))
	root.add_child(_make_box_node(
		"bound_east",
		Vector3(arena_size_x + BOUNDARY_WALL_THICKNESS * 0.5, boundary_height * 0.5, 0.0),
		Vector3(BOUNDARY_WALL_THICKNESS, boundary_height, span_z),
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

static func _make_overhead_node(entry: Dictionary) -> Node3D:
	var x := float(entry.get("x", 0.0))
	var z := float(entry.get("z", 0.0))
	var underside_y := float(entry.get("y", 3.25))
	var thickness := float(entry.get("thickness", 0.35))
	return _make_box_node(
		"overhead_%s" % str(entry.get("id", "")),
		Vector3(x, underside_y + thickness * 0.5, z),
		Vector3(float(entry.get("sx", 1.0)), thickness, float(entry.get("sz", 1.0))),
		_get_role_material("overhead", false, false)
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

static func _make_stair_node(entry: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "stair_%s" % str(entry.get("id", ""))

	var x := float(entry.get("x", 0.0))
	var z := float(entry.get("z", 0.0))
	var sx := float(entry.get("sx", 1.0))
	var sz := float(entry.get("sz", 1.0))
	var top_y := float(entry.get("h", 1.0))
	var direction := String(entry.get("direction", "x+"))
	var along_x := direction.begins_with("x")
	var positive := direction.ends_with("+")
	var total_run := sx if along_x else sz
	var cross_size := sz if along_x else sx
	var step_count: int = maxi(2, int(entry.get("steps", 2)))
	var step_run := total_run / float(step_count)
	var stair_material := _get_role_material("stair", false, true)

	for index in range(step_count):
		var offset: float = -total_run * 0.5 + step_run * (float(index) + 0.5)
		if not positive:
			offset = -offset
		var step_height: float = top_y * float(index + 1) / float(step_count)
		var position := Vector3(x, step_height * 0.5, z)
		var size := Vector3(sx, step_height, sz)
		if along_x:
			position.x += offset
			size.x = step_run
			size.z = cross_size
		else:
			position.z += offset
			size.x = cross_size
			size.z = step_run

		node.add_child(_make_box_node(
			"step_%02d" % index,
			position,
			size,
			stair_material
		))

	return node

static func _make_catwalk_node(entry: Dictionary, options: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "catwalk_%s" % str(entry.get("id", ""))

	var x := float(entry.get("x", 0.0))
	var z := float(entry.get("z", 0.0))
	var sx := float(entry.get("sx", 1.0))
	var sz := float(entry.get("sz", 1.0))
	var deck_height := float(entry.get("h", 1.0))
	var deck_material := _get_role_material("catwalk", true, true)
	node.add_child(_make_box_node(
		"deck",
		Vector3(x, deck_height - PASS_UNDER_DECK_HEIGHT * 0.5, z),
		Vector3(sx, PASS_UNDER_DECK_HEIGHT, sz),
		deck_material
	))

	if bool(options.get("catwalk_support_visuals", true)):
		var inset := 0.38
		var support_start := x - sx * 0.5 + inset
		var support_end := x + sx * 0.5 - inset
		var support_spans: int = maxi(1, ceili((support_end - support_start) / 8.0))
		var support_xs: Array[float] = []
		for support_index in range(support_spans + 1):
			support_xs.append(support_start + (support_end - support_start) * float(support_index) / float(support_spans))
		var support_zs := [z - sz * 0.5 + inset, z + sz * 0.5 - inset]
		for side_index in range(support_xs.size()):
			for post_index in range(support_zs.size()):
				node.add_child(_make_box_node(
					"support_%d_%d" % [side_index, post_index],
					Vector3(support_xs[side_index], deck_height * 0.5, support_zs[post_index]),
					Vector3(0.22, deck_height, 0.22),
					_get_role_material("wall", false, false)
				))
			node.add_child(_make_box_node(
				"support_beam_%d" % side_index,
				Vector3(support_xs[side_index], deck_height - 0.26, z),
				Vector3(0.24, 0.24, maxf(0.3, sz - inset * 1.2)),
				_get_role_material("cover", false, false)
			))

	if sx >= sz:
		_build_catwalk_rails(node, entry, x, z, sx, sz, deck_height)

	return node

static func _build_catwalk_rails(
	parent: Node3D,
	entry: Dictionary,
	x: float,
	z: float,
	sx: float,
	sz: float,
	deck_height: float
) -> void:
	var rail_material := _get_cached_color_material(Color(0.82, 0.62, 0.14), 0.55, "catwalk_rail")
	var rail_height := 1.05
	var post_width := 0.09
	var rail_length := sx * 0.94
	var start_x := x - rail_length * 0.5
	var end_x := x + rail_length * 0.5

	for side_index in range(2):
		var side_sign := -1.0 if side_index == 0 else 1.0
		var side_name := "z-" if side_sign < 0.0 else "z+"
		var rail_z := z + side_sign * (sz * 0.5 - 0.1)
		var spans: Array = [[start_x, end_x]]
		if String(entry.get("railOpening", "")) == side_name:
			var opening_width := float(entry.get("railOpeningWidth", 0.0))
			var opening_center := float(entry.get("railOpeningCenter", x))
			var opening_start: float = maxf(start_x, opening_center - opening_width * 0.5)
			var opening_end: float = minf(end_x, opening_center + opening_width * 0.5)
			spans = []
			if opening_start - start_x > 0.25:
				spans.append([start_x, opening_start])
			if end_x - opening_end > 0.25:
				spans.append([opening_end, end_x])

		var post_positions: Array[float] = []
		for span_variant in spans:
			var span: Array = span_variant as Array
			for endpoint_variant in span:
				var endpoint := float(endpoint_variant)
				var is_new := true
				for existing in post_positions:
					if absf(existing - endpoint) < 0.001:
						is_new = false
						break
				if is_new:
					post_positions.append(endpoint)

		for post_index in range(post_positions.size()):
			parent.add_child(_make_box_node(
				"rail_%s_post_%d" % [side_name, post_index],
				Vector3(post_positions[post_index], deck_height + rail_height * 0.5, rail_z),
				Vector3(post_width, rail_height, post_width),
				rail_material
			))
		for span_index in range(spans.size()):
			var span: Array = spans[span_index] as Array
			var span_start := float(span[0])
			var span_end := float(span[1])
			for bar_index in range(2):
				var bar_y := deck_height + (0.55 if bar_index == 0 else rail_height)
				parent.add_child(_make_box_node(
					"rail_%s_bar_%d_%d" % [side_name, span_index, bar_index],
					Vector3((span_start + span_end) * 0.5, bar_y, rail_z),
					Vector3(span_end - span_start, 0.075, 0.075),
					rail_material
				))

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
	body.set_meta("surface_type", _surface_type_from_name(node_name))
	body.set_meta("shape_size", size)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	node.add_child(body)

	return node

static func _build_ladders(parent: Node3D, entries: Array) -> void:
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var height := maxf(1.0, float(entry.get("h", 3.0)))
		var width := maxf(0.6, float(entry.get("sx", 1.2)))
		var depth := maxf(0.35, float(entry.get("sz", 0.65)))
		var bottom := float(entry.get("bottomY", 0.0))
		var position := Vector3(float(entry.get("x", 0.0)), bottom + height * 0.5, float(entry.get("z", 0.0)))
		var area := _make_environment_area("Ladder_%s" % String(entry.get("id", "volume")), position, Vector3(width, height, depth), "ladder")
		var normal_array := entry.get("normal", [0.0, 1.0]) as Array
		var exit_array := entry.get("exitDirection", normal_array) as Array
		var normal := Vector3(float(normal_array[0]), 0.0, float(normal_array[1])).normalized() if normal_array.size() >= 2 else Vector3.FORWARD
		var exit_direction := Vector3(float(exit_array[0]), 0.0, float(exit_array[1])).normalized() if exit_array.size() >= 2 else normal
		area.set_meta("ladder_normal", normal)
		area.set_meta("ladder_exit_direction", exit_direction)
		area.set_meta("ladder_bottom", bottom)
		area.set_meta("ladder_top", bottom + height)
		area.set_meta("ladder_center", position)
		_build_ladder_visual(area, width, height, depth)
		parent.add_child(area)

static func _build_water_volumes(parent: Node3D, entries: Array) -> void:
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var surface_y := float(entry.get("surfaceY", 0.7))
		var bottom_y := float(entry.get("bottomY", 0.0))
		var depth := maxf(0.1, surface_y - bottom_y)
		var size := Vector3(maxf(0.5, float(entry.get("sx", 4.0))), depth, maxf(0.5, float(entry.get("sz", 4.0))))
		var position := Vector3(float(entry.get("x", 0.0)), bottom_y + depth * 0.5, float(entry.get("z", 0.0)))
		var area := _make_environment_area("Water_%s" % String(entry.get("id", "volume")), position, size, "water")
		area.set_meta("water_surface_y", surface_y)
		area.set_meta("water_bottom_y", bottom_y)
		area.set_meta("water_depth", depth)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.12, 0.42, 0.55, 0.42)
		material.roughness = 0.18
		mesh.material_override = material
		area.add_child(mesh)
		parent.add_child(area)

static func _make_environment_area(node_name: String, position: Vector3, size: Vector3, environment_type: String) -> Area3D:
	var area := Area3D.new()
	area.name = node_name
	area.position = position
	area.collision_layer = 2
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = true
	area.set_meta("environment_type", environment_type)
	area.set_meta("shape_size", size)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	return area

static func _build_ladder_visual(area: Area3D, width: float, height: float, depth: float) -> void:
	var material := _get_cached_color_material(Color(0.82, 0.64, 0.16), 0.52, "semantic_ladder")
	for side in [-1.0, 1.0]:
		area.add_child(_make_visual_box(Vector3(side * width * 0.38, 0.0, 0.0), Vector3(0.09, height, maxf(0.08, depth * 0.18)), material))
	var rung_count := maxi(3, floori(height / 0.32))
	for index in range(rung_count):
		var y := -height * 0.5 + (float(index) + 0.5) * height / float(rung_count)
		area.add_child(_make_visual_box(Vector3(0.0, y, 0.0), Vector3(width * 0.82, 0.065, maxf(0.08, depth * 0.18)), material))

static func _make_visual_box(position: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	return mesh_instance

static func _surface_type_from_name(node_name: String) -> String:
	var lowered := node_name.to_lower()
	if lowered.contains("wood") or lowered.contains("crate") or lowered.contains("cover"):
		return "wood"
	if lowered.contains("glass") or lowered.contains("window"):
		return "glass"
	if lowered.contains("metal") or lowered.contains("rail") or lowered.contains("catwalk") or lowered.contains("stair"):
		return "metal"
	if lowered.contains("drywall") or lowered.contains("panel"):
		return "drywall"
	return "concrete"

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
		"overhead":
			material.albedo_color = Color(0.32, 0.34, 0.35)
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
