extends RefCounted

const TextureSource = preload("res://scripts/level/SourceReflectionTexture.gd")
const Probe = preload("res://scripts/level/SourceProbeDiagnostic.gd")
const FIELDS := ["origin_yaw", "minimum", "size", "inverse_edge"]
var source := TextureSource.new()
var game_to_source := Transform3D.IDENTITY
var buffers: Dictionary = {}
var count := 0
var _bindings: Array[WeakRef] = []


func clear() -> void:
	for reference in _bindings:
		var material := reference.get_ref() as ShaderMaterial
		if material != null:
			material.set_shader_parameter("reflection_count", 0)
			material.set_shader_parameter("native_reflection", null)
	_bindings.clear()
	count = 0
	buffers.clear()
	source.release()
	source = TextureSource.new()


# gdlint: disable=max-returns
static func records(data: Dictionary, level: Dictionary, alignment: Transform3D) -> Array:
	var trace: Variant = level.get("sourceTrace")
	if not trace is Dictionary or not trace.get("vpkSha256") is String:
		return []
	var cubes: Variant = data.get("cubes")
	if not (cubes is int or cubes is float) or not is_finite(cubes):
		return []
	if cubes != int(cubes) or cubes < 1 or cubes > 128:
		return []
	if (
		not Probe.valid_alignment(alignment)
		or data.get("level") != level.get("id")
		or not data.get("source_trace") is Dictionary
		or data.source_trace.get("vpkSha256") != trace.vpkSha256
		or trace.vpkSha256.length() != 64
		or not trace.vpkSha256.is_valid_hex_number(false)
		or not data.get("probes") is Array
		or data.probes.is_empty()
		or data.probes.size() > 128
		or data.probes.size() != int(cubes)
	):
		return []
	var rows: Array = data.probes.duplicate(true)
	var seen := []
	for index in range(rows.size()):
		var row: Variant = rows[index]
		if not Probe._valid_probe(row) or not row.get("native") is Dictionary:
			return []
		if not row.get("sample_supported") is bool:
			return []
		var cube: Variant = row.get("cube_index")
		if (
			not (cube is float or cube is int)
			or not is_finite(cube)
			or cube != int(cube)
			or cube < 0
			or cube >= cubes
			or cube in seen
			or row.native.get("classname") != "env_combined_light_probe_volume"
		):
			return []
		seen.append(cube)
		row["source_order"] = index
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a.cube_index < b.cube_index if a.priority == b.priority else a.priority > b.priority
			)
	)
	return rows


func configure(
	path: String, level: Dictionary, alignment: Transform3D, diagnostic := false
) -> bool:
	clear()
	if not diagnostic or not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("file") != "blocks/reflection.bc6h":
		return false
	var rows := records(data, level, alignment)
	if rows.is_empty():
		return false
	var payload := FileAccess.get_file_as_bytes(path.get_base_dir().path_join(data.file))
	if TextureSource._sha(payload) != data.get("sha256"):
		return false
	# Keep the upload owner local across await: clear/reconfigure must invalidate it.
	var uploading := source
	if not await uploading.create(data, payload) or source != uploading:
		return false
	game_to_source = alignment.affine_inverse()
	for field in FIELDS:
		var values := PackedVector4Array()
		values.resize(128)
		buffers[field] = values
	for row in rows:
		if not row.enabled:
			continue
		var origin := Probe._vector(row.origin)
		var minimum := Probe._vector(row.bounds_min)
		var size := Probe._vector(row.bounds_size)
		# VRF uses a grown containment box and per-axis edge distances in Source units.
		var inverse := Vector3.ONE / (Probe._vector(row.edge_fade) + Vector3.ONE * 0.02)
		buffers.origin_yaw[count] = Vector4(
			origin.x, origin.y, origin.z, deg_to_rad(row.yaw_degrees)
		)
		buffers.minimum[count] = Vector4(
			minimum.x - 0.02, minimum.y - 0.02, minimum.z - 0.02, row.cube_index
		)
		buffers.size[count] = Vector4(size.x + 0.04, size.y + 0.04, size.z + 0.04, 0)
		buffers.inverse_edge[count] = Vector4(inverse.x, inverse.y, inverse.z, 0)
		count += 1
	return count > 0


func bind(material: ShaderMaterial) -> bool:
	if count == 0 or source.texture == null:
		return false
	material.set_shader_parameter("game_to_source", game_to_source)
	material.set_shader_parameter("native_reflection", source.texture)
	material.set_shader_parameter("reflection_count", count)
	for field in FIELDS:
		material.set_shader_parameter("reflection_" + field, buffers[field])
	_bindings.append(weakref(material))
	return true
