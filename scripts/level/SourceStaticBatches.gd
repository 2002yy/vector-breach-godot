extends RefCounted

# Optional Source2Viewer visuals only. Keep original resources and independent
# physics; group nearby compatible opaque surfaces to reduce CPU draw submission.
static func apply(root: Node3D, manifest_path: String) -> Dictionary:
	if root.has_meta("source_static_batches"):
		return root.get_meta("source_static_batches")
	if not FileAccess.file_exists(manifest_path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or data.get("schema") != 1 or data.get("exporter") != "Source2Viewer-CLI 20.1":
		return {}
	var raw_cell: Variant = data.get("static_batch_cell_m", 0.0)
	if not (raw_cell is int or raw_cell is float):
		return {}
	var cell := float(raw_cell)
	if cell not in [8.0, 16.0]:
		return {}
	var result := _batch(root, cell)
	root.set_meta("source_static_batches", result)
	return result


static func _batch(root: Node3D, cell_size: float) -> Dictionary:
	var start := Time.get_ticks_msec()
	var groups: Dictionary = {}
	var inverse := root.global_transform.affine_inverse()
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var node := candidate as MeshInstance3D
		if not node.is_visible_in_tree() or not node.mesh is ArrayMesh or node.get_child_count() != 0:
			continue
		var mesh := node.mesh as ArrayMesh
		if mesh.get_surface_count() != 1 or mesh.get_blend_shape_count() != 0 or node.skin != null:
			continue
		if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES or node.material_overlay != null:
			continue
		if node.transparency != 0.0 or node.visibility_range_begin != 0.0 or node.visibility_range_end != 0.0:
			continue
		var excluded := Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS
		if mesh.surface_get_format(0) & excluded or not _supported_custom_channels(mesh.surface_get_format(0)):
			continue
		var material := node.get_active_material(0) as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.grow or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or material.uv1_triplanar or material.uv2_triplanar:
			continue
		if material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
			continue
		var transform := inverse * node.global_transform
		if transform.basis.determinant() <= 0:
			continue
		var scale := transform.basis.get_scale()
		if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z):
			continue
		var normalized := transform.basis.orthonormalized()
		if not transform.basis.is_equal_approx(normalized.scaled(Vector3.ONE * scale.x)):
			continue
		var box: AABB = transform * mesh.get_aabb()
		if box.size.length() > cell_size * 2.0:
			continue
		var cell := Vector3i((box.get_center() / cell_size).floor())
		var key := "%s/%s/%s/%s/%s/%s/%s/%s" % [material.get_instance_id(), cell, node.cast_shadow, node.layers, mesh.surface_get_format(0), node.gi_mode, node.ignore_occlusion_culling, node.extra_cull_margin]
		if not groups.has(key):
			groups[key] = []
		groups[key].append({"node": node, "transform": transform})
	var result := {"groups": 0, "source_instances": 0, "build_ms": 0, "cell_size": cell_size}
	for entries in groups.values():
		if entries.size() < 2:
			continue
		var first: MeshInstance3D = entries[0].node
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(first.get_active_material(0))
		for entry in entries:
			tool.append_from(entry.node.mesh, 0, entry.transform)
		var merged := tool.commit()
		if merged == null:
			continue
		var batch := MeshInstance3D.new()
		batch.name = "StaticBatch" + str(result.groups)
		batch.mesh = merged
		batch.cast_shadow = first.cast_shadow
		batch.layers = first.layers
		batch.gi_mode = first.gi_mode
		batch.ignore_occlusion_culling = first.ignore_occlusion_culling
		batch.extra_cull_margin = first.extra_cull_margin
		root.add_child(batch)
		for entry in entries:
			entry.node.hide()
		result.groups += 1
		result.source_instances += entries.size()
	result.build_ms = Time.get_ticks_msec() - start
	return result


static func _supported_custom_channels(format: int) -> bool:
	# SurfaceTool preserves float custom attributes; its mesh extraction explicitly
	# does not support byte/half channels. Never silently discard those attributes.
	var shifts := [Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT]
	for channel in range(4):
		if format & (Mesh.ARRAY_FORMAT_CUSTOM0 << channel):
			var kind: int = (format >> shifts[channel]) & Mesh.ARRAY_FORMAT_CUSTOM_MASK
			if kind < Mesh.ARRAY_CUSTOM_R_FLOAT:
				return false
	return true
