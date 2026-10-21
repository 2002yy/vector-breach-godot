extends MeshInstance3D

var _source: MeshInstance3D


func _ready() -> void:
	_source = get_parent() as MeshInstance3D
	process_priority = 1
	set_process(_source != null and mesh is ArrayMesh and mesh.get_blend_shape_count() > 0)
	_sync()


func _process(_delta: float) -> void:
	_sync()


func _sync() -> void:
	if not is_instance_valid(_source) or not mesh is ArrayMesh:
		return
	for index in range(mesh.get_blend_shape_count()):
		set_blend_shape_value(index, _source.get_blend_shape_value(index))
