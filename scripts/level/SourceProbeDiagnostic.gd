extends RefCounted

const DISPLAY = preload("res://scripts/level/source_probe_diagnostic.gdshader")
const MAX_PROBES := 128
const SOURCE_UNIT := 0.0254
const BUFFER_NAMES := ["origin_yaw", "min", "size", "inv_edge", "atlas_size", "atlas_offset"]
var source_to_game := Transform3D.IDENTITY
var _texture: ImageTexture3D
var _buffers: Dictionary = {}
var _dimensions := Vector3i.ZERO
var _count := 0
var _ready := false
var _bindings: Array = []
var _bound_materials: Array[WeakRef] = []


static func alignment_from_visual(root: Node) -> Transform3D:
	var matches := root.find_children("OfficialSourceAlignment", "Node3D", true, false)
	if matches.size() != 1:
		return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	# VRF raw Source inches -> glTF metres in (source_y,source_z,source_x).
	var raw := Basis(
		Vector3(0, 0, SOURCE_UNIT), Vector3(SOURCE_UNIT, 0, 0), Vector3(0, SOURCE_UNIT, 0)
	)
	return matches[0].global_transform * Transform3D(raw, Vector3.ZERO)


static func valid_alignment(value: Transform3D) -> bool:
	if not value.is_finite() or value.basis.determinant() <= 0:
		return false
	var normalized := value.basis.scaled(Vector3.ONE / SOURCE_UNIT)
	return (normalized.transposed() * normalized).is_equal_approx(Basis.IDENTITY)


# Validation exits intentionally preserve the first failed input boundary.
# gdlint: disable=max-returns
func configure(
	path: String, level: Dictionary, alignment: Transform3D, diagnostic: bool = false
) -> bool:
	detach()
	for reference in _bound_materials:
		var old_material := reference.get_ref() as ShaderMaterial
		if old_material != null:
			old_material.set_shader_parameter("source_probe_count", 0)
			old_material.set_shader_parameter("source_probe_texture", null)
	_bound_materials.clear()
	_ready = false
	_texture = null
	_buffers.clear()
	_count = 0
	if not diagnostic or not valid_alignment(alignment) or not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if (
		not data is Dictionary
		or data.get("schema") != 1
		or data.get("contract") != "source-map-lighting-diagnostic-v1"
	):
		return false
	if (
		data.get("level") != level.get("id")
		or (
			data.get("source_trace", {}).get("vpkSha256")
			!= level.get("sourceTrace", {}).get("vpkSha256")
		)
	):
		return false
	if not data.get("probes") is Array or not data.get("child_lumps_not_instantiated", []) is Array:
		return false
	var rows: Array = data.probes.duplicate(true)
	if (
		rows.is_empty()
		or rows.size() > MAX_PROBES
		or not data.get("child_lumps_not_instantiated", []).is_empty()
	):
		return false
	var textures: Array = []
	for row in rows:
		if not _valid_probe(row):
			return false
		if row.texture not in textures:
			textures.append(row.texture)
	if textures.size() != 1:
		return false
	var entry: Dictionary = data.get("sources", {}).get(textures[0], {}).get("decoded", {})
	var dimensions: Variant = entry.get("dimensions")
	if (
		entry.get("layout") != "zyx-rgba-f32-le"
		or not dimensions is Array
		or dimensions.size() != 3
	):
		return false
	for component in dimensions:
		if (
			not (component is int or component is float)
			or not is_finite(float(component))
			or float(component) != floorf(float(component))
		):
			return false
	_dimensions = Vector3i(int(dimensions[0]), int(dimensions[1]), int(dimensions[2]))
	if _dimensions.x <= 0 or _dimensions.y <= 0 or _dimensions.z <= 0 or _dimensions.z % 6 != 0:
		return false
	if (
		maxi(_dimensions.x, maxi(_dimensions.y, _dimensions.z)) > 2048
		or _dimensions.x * _dimensions.y * _dimensions.z * 16 > 1073741824
	):
		return false
	var file: String = entry.get("file", "")
	if (
		file.is_empty()
		or file != file.get_file()
		or file.contains("\\")
		or file.contains(":")
		or file == ".."
	):
		return false
	var raw := FileAccess.get_file_as_bytes(path.get_base_dir().path_join(file))
	if raw.size() != _dimensions.x * _dimensions.y * _dimensions.z * 16:
		return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(raw)
	if hash.finish().hex_encode() != entry.get("sha256"):
		return false
	var layers: Array[Image] = []
	var stride := _dimensions.x * _dimensions.y * 16
	for z in range(_dimensions.z):
		layers.append(
			Image.create_from_data(
				_dimensions.x,
				_dimensions.y,
				false,
				Image.FORMAT_RGBAF,
				raw.slice(z * stride, (z + 1) * stride)
			)
		)
	var texture := ImageTexture3D.new()
	if (
		texture.create(
			Image.FORMAT_RGBAF, _dimensions.x, _dimensions.y, _dimensions.z, false, layers
		)
		!= OK
	):
		return false
	for name in BUFFER_NAMES:
		var buffer := PackedVector4Array()
		buffer.resize(MAX_PROBES)
		_buffers[name] = buffer
	for index in range(rows.size()):
		rows[index]["source_order"] = index
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a.source_order < b.source_order
				if a.priority == b.priority
				else a.priority > b.priority
			)
	)
	for row in rows:
		if not row.enabled:
			continue
		var size := _vector(row.bounds_size)
		var fade := _vector(row.edge_fade)
		var values := [
			_vector(row.origin),
			_vector(row.bounds_min),
			size,
			size / fade.max(Vector3.ONE * 0.02),
			_vector(row.atlas_size),
			_vector(row.atlas_offset)
		]
		var dims := Vector3(_dimensions.x, _dimensions.y, _dimensions.z / 6)
		if not (_vector(row.atlas_size) + _vector(row.atlas_offset)).is_equal_approx(
			(_vector(row.atlas_size) + _vector(row.atlas_offset)).clamp(Vector3.ZERO, dims)
		):
			return false
		for index in range(BUFFER_NAMES.size()):
			var v: Vector3 = values[index]
			_buffers[BUFFER_NAMES[index]][_count] = Vector4(
				v.x, v.y, v.z, deg_to_rad(float(row.yaw_degrees)) if index == 0 else 0.0
			)
		_count += 1
	_texture = texture
	source_to_game = alignment
	_ready = _count > 0
	return _ready


# gdlint: enable=max-returns
func bind(material: ShaderMaterial) -> bool:
	if not _ready:
		material.set_shader_parameter("source_probe_count", 0)
		material.set_shader_parameter("source_probe_texture", null)
		return false
	material.set_shader_parameter("source_probe_texture", _texture)
	material.set_shader_parameter("source_probe_dimensions", Vector3(_dimensions))
	material.set_shader_parameter("source_probe_count", _count)
	material.set_shader_parameter("game_to_source", source_to_game.affine_inverse())
	for name in BUFFER_NAMES:
		material.set_shader_parameter("source_probe_" + name, _buffers[name])
	_bound_materials.append(weakref(material))
	return true


func attach(root: Node, direction: int = 0) -> int:
	if not _ready or direction not in [0, 1]:
		return 0
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface)
			if original == null or original.next_pass != null:
				continue
			var copy := original.duplicate() as Material
			var display := ShaderMaterial.new()
			display.shader = DISPLAY
			if original is ShaderMaterial:
				for mode in ["cull_disabled", "cull_front"]:
					if original.shader.code.contains(mode):
						var variant := DISPLAY.duplicate() as Shader
						variant.code = variant.code.replace("cull_back", mode)
						display.shader = variant
			display.set_shader_parameter("diagnostic_direction", direction)
			bind(display)
			copy.next_pass = display
			_bindings.append(
				{
					"mesh": mesh,
					"surface": surface,
					"previous": mesh.get_surface_override_material(surface),
					"copy": copy
				}
			)
			mesh.set_surface_override_material(surface, copy)
			count += 1
	return count


func detach() -> void:
	for entry in _bindings:
		if (
			is_instance_valid(entry.mesh)
			and entry.mesh.get_surface_override_material(entry.surface) == entry.copy
		):
			entry.mesh.set_surface_override_material(entry.surface, entry.previous)
	_bindings.clear()


static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


static func _valid_probe(row: Variant) -> bool:
	if not row is Dictionary or not row.get("sample_supported", false):
		return false
	if not row.get("enabled") is bool or not row.get("texture") is String:
		return false
	for key in ["priority", "yaw_degrees"]:
		var scalar: Variant = row.get(key)
		if not (scalar is float or scalar is int) or not is_finite(float(scalar)):
			return false
	for name in ["origin", "bounds_min", "bounds_size", "edge_fade", "atlas_size", "atlas_offset"]:
		var value: Variant = row.get(name)
		if not value is Array or value.size() != 3:
			return false
		for component in value:
			if not (component is float or component is int) or not is_finite(float(component)):
				return false
		if name in ["bounds_size", "atlas_size"]:
			if minf(value[0], minf(value[1], value[2])) <= 0:
				return false
		if name in ["edge_fade", "atlas_offset"] and minf(value[0], minf(value[1], value[2])) < 0:
			return false
	return is_finite(float(row.get("yaw_degrees", NAN)))
