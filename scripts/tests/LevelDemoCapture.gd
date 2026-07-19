extends Node

const MAIN_SCENE = preload("res://scenes/Main.tscn")
const TARGET_LEVEL_ID := "foundry-reforged"
const DEMO_DURATION := 7.5

var _main: Node3D
var _player: CharacterBody3D
var _camera_pivot: Node3D
var _weapon_system: Node
var _elapsed: float = 0.0
var _next_shot_time: float = 1.25
var _poster_saved: bool = false
var _waypoints := [
	Vector3(-37.0, 1.05, 35.0),
	Vector3(-30.0, 1.05, 22.0),
	Vector3(-22.0, 1.05, 8.0),
	Vector3(-16.0, 1.05, -11.0),
	Vector3(-10.0, 1.05, -24.0),
]

func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var level_index := int(_main.call("find_level_option_index", TARGET_LEVEL_ID))
	if level_index < 0:
		push_error("Demo capture could not find Foundry Reforged")
		get_tree().quit(1)
		return
	_main.call("_on_map_selected", level_index)
	_main.call("_on_start_pressed")
	await get_tree().physics_frame
	_player = _main.get_node("Player") as CharacterBody3D
	_camera_pivot = _player.get_node("CameraPivot") as Node3D
	_weapon_system = _main.get_node("WeaponSystem")
	_player.call("set_controls_enabled", false)
	_player.set_physics_process(false)
	_player.global_position = _waypoints[0]
	_point_camera_along_route(0.0)

func _process(delta: float) -> void:
	if _player == null:
		return
	_elapsed += delta
	var route_progress := clampf((_elapsed - 0.35) / (DEMO_DURATION - 0.8), 0.0, 1.0)
	_player.global_position = _sample_route(route_progress)
	_point_camera_along_route(route_progress)
	_weapon_system.call("tick", delta, false, false, _player)
	if _elapsed >= _next_shot_time and _elapsed < 6.7:
		_weapon_system.call("try_fire", _player)
		_next_shot_time += 0.55
	if not _poster_saved and _elapsed >= 3.6:
		_poster_saved = true
		await RenderingServer.frame_post_draw
		var poster_path := ProjectSettings.globalize_path("res://assets/demo/vector-breach-foundry-demo.png")
		var result := get_viewport().get_texture().get_image().save_png(poster_path)
		print("DEMO_POSTER=%s result=%s" % [poster_path, error_string(result)])
	if _elapsed >= DEMO_DURATION:
		print("LEVEL_DEMO_CAPTURE_OK duration=%.1f" % _elapsed)
		get_tree().quit()

func _sample_route(progress: float) -> Vector3:
	var scaled := progress * float(_waypoints.size() - 1)
	var index := mini(int(floor(scaled)), _waypoints.size() - 2)
	return _waypoints[index].lerp(_waypoints[index + 1], scaled - float(index))

func _point_camera_along_route(progress: float) -> void:
	var look_progress := minf(1.0, progress + 0.055)
	var target := _sample_route(look_progress)
	if target.distance_squared_to(_player.global_position) < 0.01:
		target = _player.global_position + Vector3.FORWARD
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_camera_pivot.rotation.x = deg_to_rad(-2.0 + sin(_elapsed * 0.8) * 1.2)
