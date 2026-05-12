extends Node3D

@export var debug_enabled: bool = true
@export var line_duration: float = 0.18
@export var line_width: float = 0.03
@export var marker_duration: float = 0.24
@export var marker_scale: float = 0.14
@export var hit_color: Color = Color(1.0, 0.3, 0.25, 1.0)
@export var kill_color: Color = Color(1.0, 0.82, 0.26, 1.0)
@export var world_hit_color: Color = Color(0.4, 0.78, 1.0, 1.0)
@export var miss_color: Color = Color(0.7, 0.7, 0.7, 0.9)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var marker_mesh_instance: MeshInstance3D = $MarkerMeshInstance3D

var _hide_timer: float = 0.0
var _marker_timer: float = 0.0
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _marker_material: StandardMaterial3D = StandardMaterial3D.new()

func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = _material
	mesh_instance.visible = false

	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.albedo_color = hit_color
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mesh_instance.material_override = _marker_material
	marker_mesh_instance.visible = false

func _process(delta: float) -> void:
	if _hide_timer > 0.0:
		_hide_timer = maxf(0.0, _hide_timer - delta)
		if _hide_timer == 0.0:
			mesh_instance.visible = false

	if _marker_timer > 0.0:
		_marker_timer = maxf(0.0, _marker_timer - delta)
		if _marker_timer == 0.0:
			marker_mesh_instance.visible = false

func show_shot(result: Dictionary) -> void:
	if not debug_enabled:
		return

	var from_world: Vector3 = result.get("from", Vector3.ZERO)
	var to_world: Vector3 = result.get("position", result.get("to", from_world)) as Vector3
	var shot_color: Color = _resolve_color(result)

	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_set_color(shot_color)
	immediate_mesh.surface_add_vertex(to_local(from_world))
	immediate_mesh.surface_add_vertex(to_local(to_world))
	immediate_mesh.surface_end()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.visible = true
	_hide_timer = line_duration
	_show_marker(result, to_world, shot_color)

func _resolve_color(result: Dictionary) -> Color:
	if not bool(result.get("hit", false)):
		return miss_color

	var damage_result: Dictionary = result.get("damage_result", {}) as Dictionary
	if not damage_result.is_empty() and bool(damage_result.get("hit", false)):
		if bool(damage_result.get("killed", false)):
			return kill_color
		return hit_color

	return world_hit_color

func _show_marker(result: Dictionary, hit_position: Vector3, marker_color_value: Color) -> void:
	if not bool(result.get("hit", false)):
		marker_mesh_instance.visible = false
		_marker_timer = 0.0
		return

	marker_mesh_instance.position = to_local(hit_position)
	marker_mesh_instance.scale = Vector3.ONE * marker_scale
	_marker_material.albedo_color = marker_color_value
	marker_mesh_instance.visible = true
	_marker_timer = marker_duration
