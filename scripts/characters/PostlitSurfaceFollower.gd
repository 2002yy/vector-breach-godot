extends MeshInstance3D

const LIVE_PROPERTIES := [
	&"layers",
	&"transparency",
	&"custom_aabb",
	&"extra_cull_margin",
	&"lod_bias",
	&"visibility_range_begin",
	&"visibility_range_end",
	&"visibility_range_begin_margin",
	&"visibility_range_end_margin",
	&"visibility_range_fade_mode"
]
var _source: MeshInstance3D


func _ready() -> void:
	_source = get_parent() as MeshInstance3D
	process_priority = 1
	set_process(_source != null)
	_sync()


func _process(_delta: float) -> void:
	_sync()


func _sync() -> void:
	if not is_instance_valid(_source) or not mesh is ArrayMesh:
		return
	# Geometry visibility/fade settings do not inherit from a mesh parent.
	# Keep auxiliary draws aligned even on meshes without blend shapes.
	for property in LIVE_PROPERTIES:
		var value: Variant = _source.get(property)
		if get(property) != value:
			set(property, value)
	if material_override is ShaderMaterial:
		material_override.set_shader_parameter("source_draw_enabled", _source.transparency < 1.0)
	for index in range(mesh.get_blend_shape_count()):
		set_blend_shape_value(index, _source.get_blend_shape_value(index))
