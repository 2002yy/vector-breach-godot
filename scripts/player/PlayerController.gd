extends CharacterBody3D

@export var walk_speed: float = 5.2
@export var sprint_speed: float = 6.2
@export var jump_velocity: float = 3.5
@export var mouse_sensitivity: float = 0.0022
@export var acceleration: float = 30.0
@export var deceleration: float = 24.0
@export var standing_height: float = 0.9
@export var max_step_height: float = 0.42
@export var floor_probe_distance: float = 0.9
@export var step_probe_distance: float = 0.55

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var controls_enabled: bool = false
var mouse_capture_enabled: bool = false
var _spawn_applied: bool = false

func _ready() -> void:
	floor_snap_length = 0.3
	max_slides = 8
	set_mouse_capture_enabled(false)
	_apply_spawn()

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventMouseButton and event.pressed and mouse_capture_enabled and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if not _spawn_applied and GameState.player_spawn != Vector3.ZERO:
		_apply_spawn()

	if not controls_enabled:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	var was_on_floor: bool = is_on_floor()
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir: Vector3 = get_world_move_direction(input_vector)

	var speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target_velocity: Vector3 = move_dir * speed
	var blend: float = acceleration if move_dir != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, blend * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, blend * delta)

	var step_motion: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta
	move_and_slide()

	if was_on_floor and step_motion.length() > 0.001:
		_try_step_up(step_motion)

	if not is_on_floor() and velocity.y <= 0.0:
		_snap_to_floor()

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not controls_enabled:
		velocity.x = 0.0
		velocity.z = 0.0

func set_mouse_capture_enabled(enabled: bool) -> void:
	mouse_capture_enabled = enabled
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func reset_to_spawn() -> void:
	_apply_spawn()

func get_camera_node() -> Camera3D:
	return camera

func get_world_move_direction(input_vector: Vector2) -> Vector3:
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var world_direction: Vector3 = global_transform.basis * local_direction
	world_direction.y = 0.0
	return world_direction.normalized()

func apply_recoil_kick(pitch_radians: float, yaw_radians: float) -> void:
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x - pitch_radians,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)
	rotate_y(-yaw_radians)

func get_debug_snapshot(menu_open: bool) -> Dictionary:
	return {
		"speed": Vector2(velocity.x, velocity.z).length(),
		"grounded": is_on_floor(),
		"position": global_position,
		"mode": "\u83dc\u5355" if menu_open else "\u6e38\u620f\u4e2d",
		"window": "\u5168\u5c4f" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "\u7a97\u53e3",
		"mouse": "\u9501\u5b9a" if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else "\u81ea\u7531"
	}

func _apply_spawn() -> void:
	if GameState.player_spawn == Vector3.ZERO:
		return
	global_position = GameState.player_spawn
	velocity = Vector3.ZERO
	_spawn_applied = true
	reset_physics_interpolation()

func _try_step_up(step_motion: Vector3) -> void:
	var direction: Vector3 = step_motion.normalized()
	var from: Vector3 = global_position + direction * step_probe_distance + Vector3.UP * max_step_height
	var to: Vector3 = from + Vector3.DOWN * (max_step_height + floor_probe_distance)
	var hit: Dictionary = _raycast(from, to)
	if hit.is_empty():
		return
	if not _is_walkable_normal(hit.normal):
		return

	var floor_y: float = float(hit.position.y)
	var current_floor_y: float = global_position.y - standing_height
	var height_delta: float = floor_y - current_floor_y
	if height_delta <= 0.05 or height_delta > max_step_height:
		return

	global_position.y += height_delta + 0.02
	apply_floor_snap()

func _snap_to_floor() -> void:
	var from: Vector3 = global_position + Vector3.UP * 0.1
	var to: Vector3 = from + Vector3.DOWN * (standing_height + floor_probe_distance)
	var hit: Dictionary = _raycast(from, to)
	if hit.is_empty():
		return
	if not _is_walkable_normal(hit.normal):
		return

	var target_y: float = float(hit.position.y) + standing_height
	if global_position.y >= target_y and global_position.y - target_y <= 0.45:
		global_position.y = target_y
		if velocity.y < 0.0:
			velocity.y = 0.0

func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func _is_walkable_normal(normal: Vector3) -> bool:
	return normal.dot(Vector3.UP) >= cos(floor_max_angle)
