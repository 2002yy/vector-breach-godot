extends Node3D

const SHIPPED_LEVEL_OPTIONS := [
	{
		"id": "test-collision-room",
		"name": "\u6d4b\u8bd5\u78b0\u649e\u623f",
		"preview": "res://assets/maps/yard-preview.png",
		"description": "\u7528\u4e8e\u6821\u51c6\u5e73\u5730\u3001\u697c\u68af\u3001\u5761\u9053\u548c\u53ef\u7a7f\u6865\u4e0b\u7a7a\u95f4\u7684\u79fb\u52a8\u6d4b\u8bd5\u623f\u3002",
		"route_profile": "\u5355\u4e00\u6821\u51c6\u6d4b\u8bd5\u7a7a\u95f4",
		"recommended_use": "\u73a9\u5bb6\u79fb\u52a8\u4e0e\u78b0\u649e\u8c03\u6821",
		"test_focus": "\u4f4e\u53f0\u9636\u3001\u8fde\u7eed\u697c\u68af\u3001\u5761\u9053\u624b\u611f\u3001\u5929\u6865\u4e0b\u7a7f"
	},
	{
		"id": "depot",
		"name": "Foundry Depot v2 \uff08\u51bb\u7ed3\uff09",
		"preview": "res://assets/maps/foundry-depot-preview.png",
		"description": "\u5df2\u51bb\u7ed3\u7684 Foundry Depot v2\uff1a\u4fdd\u7559\u73b0\u6709\u4e2d\u8def\u3001\u4fa7\u8def\u548c\u4e0a\u5c42\u538b\u5236\u7ed3\u6784\uff0c\u540e\u7eed\u8bbe\u8ba1\u4e0d\u518d\u8986\u76d6\u6b64\u7248\u3002",
		"route_profile": "\u4e2d\u8def\u3001\u4fa7\u7ffc\u8def\u3001\u4e0a\u5c42\u538b\u5236\u7ebf",
		"recommended_use": "\u65e7\u7248\u5bf9\u7167\u3001\u56de\u5f52\u9a8c\u8bc1\u4e0e\u4f5c\u54c1\u96c6\u5386\u53f2\u7559\u75d5",
		"test_focus": "\u51bb\u7ed3\u57fa\u7ebf\u3001Peek \u8282\u594f\u3001\u8def\u7ebf\u65f6\u5e8f\u3001\u67aa\u7ebf\u9a8c\u8bc1"
	},
	{
		"id": "gatehouse",
		"name": "\u95e8\u5385\u533a",
		"preview": "res://assets/maps/courtyard-preview.png",
		"description": "\u66f4\u7d27\u51d1\u7684\u8def\u7ebf\u56fe\uff0c\u9002\u5408\u8fd1\u8ddd\u79bb\u63a9\u4f53\u6218\u548c\u6e05\u89d2\u7ec3\u4e60\u3002",
		"route_profile": "\u66f4\u7d27\u7684\u63a9\u4f53\u5230\u63a9\u4f53\u63a8\u8fdb\u6d41",
		"recommended_use": "\u8fd1\u8ddd\u79bb\u5bf9\u67aa\u9a8c\u8bc1",
		"test_focus": "\u63a9\u4f53\u8fb9\u7f18\u884c\u4e3a\u3001\u77ed\u89d2\u5ea6\u8fdb\u70b9\u65f6\u673a"
	},
	{
		"id": "core-vault",
		"name": "\u6838\u5fc3\u5e93\u533a",
		"preview": "res://assets/maps/courtyard-preview.png",
		"description": "\u5185\u90e8\u66f4\u5bc6\u96c6\u7684\u6d4b\u8bd5\u573a\uff0c\u63a9\u4f53\u5c42\u6b21\u66f4\u591a\uff0c\u8fd1\u8ddd\u79bb\u538b\u529b\u66f4\u5f3a\u3002",
		"route_profile": "\u9ad8\u5bc6\u5ea6\u5ba4\u5185\u8def\u7ebf\u4e0e\u5206\u5c42\u63a9\u4f53",
		"recommended_use": "\u5bc6\u96c6\u51e0\u4f55\u538b\u529b\u6d4b\u8bd5",
		"test_focus": "\u53ef\u89c6\u6027\u3001\u63a9\u4f53\u8282\u594f\u3001\u8fd1\u8ddd\u79bb\u6218\u6597\u95f4\u8ddd"
	},
	{
		"id": "foundry-reforged",
		"name": "\u94f8\u9020\u5382\u00b7\u91cd\u6784",
		"preview": "res://assets/maps/foundry-reforged-preview.png",
		"description": "\u51bb\u7ed3 Depot v2 \u540e\u72ec\u7acb\u91cd\u5efa\u7684\u53cc\u76ee\u6807\u5bf9\u6297\u7070\u76d2\uff1b\u4e09\u6761\u5730\u9762\u4e3b\u8def\u56f4\u7ed5\u4e2d\u8def\u8f6c\u70b9\uff0c\u53ea\u5728 B \u533a\u4fdd\u7559\u4e00\u6bb5\u5c40\u90e8\u9ad8\u53f0\u9009\u62e9\u3002",
		"route_profile": "A \u957f\u8def\u3001\u4e2d\u8def\u8f6c\u70b9\u3001B \u7ef4\u4fee\u901a\u9053 + B \u533a\u5c40\u90e8\u9ad8\u53f0",
		"recommended_use": "\u53cc\u76ee\u6807\u8fdb\u653b\u9009\u62e9\u3001\u56de\u9632\u8f6c\u70b9\u4e0e\u4ea4\u706b\u8ddd\u79bb\u9a8c\u8bc1",
		"test_focus": "\u9996\u8f6e\u63a5\u89e6\u65f6\u5e8f\u3001\u4e09\u8def\u4e92\u901a\u3001\u76ee\u6807\u533a\u6e05\u70b9\u4e0e\u5c40\u90e8\u9ad8\u5dee"
	}
]

const LOCAL_DUSTLINE_LEVEL_PATH := "res://data/levels/dustline-depths.json"
const LOCAL_DUSTLINE_VISUAL_PATH := "res://assets/models/dustline/dustline_depths.glb"
const LOCAL_DUSTLINE_OPTION := {
	"id": "dustline-depths",
	"name": "\u6c99\u7ebf\u6df1\u5c42\uff08\u672c\u673a\u53c2\u8003\uff09",
	"preview": "res://assets/maps/dustline-depths-preview.png",
	"description": "\u672c\u673a\u53c2\u8003\u8bd5\u73a9\uff1a\u9501\u5b9a de_dust2 \u5730\u9762\u62d3\u6251\uff0c\u4ec5\u5728 B \u533a\u589e\u52a0\u4e00\u6761 Skywalk\u3002\u6d3e\u751f\u78b0\u649e\u4e0e\u53c2\u8003\u8d44\u6e90\u4e0d\u8fdb\u5165 Git\u3002",
	"route_profile": "\u53c2\u8003\u5730\u9762\u4e09\u8def\u7ebf + B \u533a\u5355\u6761\u53ef\u9009\u9ad8\u53f0",
	"recommended_use": "\u6bd4\u4f8b\u3001\u906e\u6321\u3001\u8def\u7ebf\u4e0e\u4ea4\u706b\u8ddd\u79bb\u5bf9\u7167",
	"test_focus": "\u5173\u952e\u95e8\u6d1e\u3001\u5761\u5ea6\u3001\u63a9\u4f53\u5c3a\u5ea6\u4e0e Skywalk \u5dee\u5f02\u5c42"
}

const LOCAL_REFERENCE_LEVEL_PATH := "res://data/levels/dustline-depths-original-local.json"
const LOCAL_REFERENCE_VISUAL_PATH := "res://assets/local_reference/dustline/de_dust2_original.glb"
const LOCAL_REFERENCE_OPTION := {
	"id": "dustline-depths-original-local",
	"name": "Dustline \u539f\u59cb\u6750\u8d28\uff08\u672c\u673a\uff09",
	"preview": "res://assets/maps/dustline-depths-preview.png",
	"description": "\u4ec5\u672c\u673a\u8bd5\u73a9\uff1a\u539f\u59cb Dust2 \u5b8c\u6574\u89c6\u89c9 + Dustline \u5df2\u5ba1\u8ba1\u78b0\u649e + B \u533a Skywalk\uff1bValve \u8d44\u6e90\u4e0d\u4f1a\u8fdb\u5165 Git\u3002",
	"route_profile": "\u539f\u59cb\u5730\u9762\u5c42\u89c6\u89c9 + \u5355\u6761 B \u533a\u53ef\u9009\u9ad8\u53f0",
	"recommended_use": "\u5bf9\u9f50\u539f\u59cb\u6750\u8d28\u3001\u6bd4\u4f8b\u3001\u906e\u6321\u548c\u8def\u7ebf\u8fa8\u8bc6\u5ea6",
	"test_focus": "\u89c6\u89c9/\u78b0\u649e\u5bf9\u9f50\u3001\u6750\u8d28\u5bfc\u5165\u3001Skywalk \u5dee\u5f02\u5c42"
}

@onready var level: Node3D = $Level
@onready var player: CharacterBody3D = $Player
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var start_menu: CanvasLayer = $StartMenu
@onready var combat_hud: CanvasLayer = $CombatHud
@onready var status_panel: CanvasLayer = $StatusPanel
@onready var hit_feedback_layer: CanvasLayer = $HitFeedbackLayer
@onready var weapon_system: Node = $WeaponSystem
@onready var weapon_view_model: Node3D = $Player/CameraPivot/Camera3D/WeaponViewModel
@onready var combat_sandbox: Node3D = $CombatSandbox
@onready var shot_debug_line: Node3D = $ShotDebugLine

var selected_level_index: int = 1
var level_options: Array = []
var game_started: bool = false
var menu_open: bool = true
var _ui_update_timer: float = 0.0
var _default_environment_state: Dictionary = {}
const UI_UPDATE_INTERVAL: float = 0.18

func _ready() -> void:
	_isolate_environment_resource()
	_capture_default_environment()
	GameState.set_graphics_preset("prototype")
	level_options = SHIPPED_LEVEL_OPTIONS.duplicate(true)
	if _has_local_level(LOCAL_DUSTLINE_LEVEL_PATH, LOCAL_DUSTLINE_VISUAL_PATH):
		level_options.append(LOCAL_DUSTLINE_OPTION.duplicate(true))
	if _has_local_level(LOCAL_REFERENCE_LEVEL_PATH, LOCAL_REFERENCE_VISUAL_PATH):
		level_options.append(LOCAL_REFERENCE_OPTION.duplicate(true))
	if level.has_signal("level_loaded"):
		level.connect("level_loaded", _on_level_loaded)
	if weapon_system.has_signal("shot_resolved"):
		weapon_system.connect("shot_resolved", _on_shot_resolved)
	if weapon_system.has_signal("weapon_switched"):
		weapon_system.connect("weapon_switched", _on_weapon_switched)
	if not GameState.hud_state_changed.is_connected(_on_hud_state_changed):
		GameState.hud_state_changed.connect(_on_hud_state_changed)
	start_menu.call("set_map_options", level_options, selected_level_index)
	start_menu.connect("start_pressed", _on_start_pressed)
	start_menu.connect("resume_pressed", _on_resume_pressed)
	start_menu.connect("map_selected", _on_map_selected)
	_apply_selected_map()
	_open_menu(true)
	_update_ui(true)

func _isolate_environment_resource() -> void:
	if world_environment.environment != null:
		world_environment.environment = world_environment.environment.duplicate(true) as Environment

func _process(delta: float) -> void:
	if game_started and not menu_open:
		var fire_pressed: bool = Input.is_action_just_pressed("fire_primary")
		var fire_held: bool = Input.is_action_pressed("fire_primary")
		if weapon_system.has_method("tick"):
			weapon_system.call("tick", delta, fire_pressed, fire_held, player)

	_ui_update_timer += delta
	if _ui_update_timer >= UI_UPDATE_INTERVAL:
		_ui_update_timer = 0.0
		_update_ui(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen_toggle"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		if game_started:
			if menu_open:
				_resume_game()
			else:
				_open_menu(false)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		status_panel.visible = not status_panel.visible
		_update_ui(true)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("reload_weapon"):
		if _can_accept_combat_input() and weapon_system.has_method("request_reload"):
			weapon_system.call("request_reload")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_1"):
		if _can_accept_combat_input() and weapon_system.has_method("switch_to_slot"):
			weapon_system.call("switch_to_slot", 0)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_2"):
		if _can_accept_combat_input() and weapon_system.has_method("switch_to_slot"):
			weapon_system.call("switch_to_slot", 1)
		get_viewport().set_input_as_handled()
		return

func _apply_selected_map() -> void:
	var option: Dictionary = level_options[selected_level_index]
	start_menu.call("set_map_details", option, game_started)
	GameState.set_level(String(option["id"]), String(option["name"]))
	_update_ui(true)

func _on_map_selected(index: int) -> void:
	selected_level_index = clampi(index, 0, level_options.size() - 1)
	_apply_selected_map()

func _on_start_pressed() -> void:
	var option: Dictionary = level_options[selected_level_index]
	level.call("load_level", option["id"])
	if player.has_method("reset_to_spawn"):
		player.call("reset_to_spawn")
	GameState.reset_runtime_state()
	game_started = true
	GameState.set_game_started(true)
	if weapon_system.has_method("configure_default_loadout"):
		weapon_system.call("configure_default_loadout")
	if weapon_view_model.has_method("set_weapon_slot"):
		weapon_view_model.call("set_weapon_slot", 0, false)
	_resume_game()

func _on_resume_pressed() -> void:
	_resume_game()

func _resume_game() -> void:
	menu_open = false
	GameState.set_menu_state(false)
	RoundManager.set_live()
	start_menu.call("set_menu_visible", false)
	if player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", true)
	if player.has_method("set_mouse_capture_enabled"):
		player.call("set_mouse_capture_enabled", true)
	weapon_view_model.visible = game_started
	_update_ui(true)

func _open_menu(initial_open: bool) -> void:
	menu_open = true
	GameState.set_menu_state(true)
	GameState.set_game_started(game_started)
	if initial_open:
		RoundManager.set_warmup()
	else:
		RoundManager.set_paused_menu()
	start_menu.call("set_menu_visible", true)
	start_menu.call("set_map_details", level_options[selected_level_index], game_started and not initial_open)
	if player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", false)
	if player.has_method("set_mouse_capture_enabled"):
		player.call("set_mouse_capture_enabled", false)
	weapon_view_model.visible = false
	_update_ui(true)

func _toggle_fullscreen() -> void:
	var current_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_ui(true)

func _on_level_loaded(level_data: Dictionary) -> void:
	_apply_level_environment(level_data)
	if combat_sandbox.has_method("load_for_level"):
		combat_sandbox.call("load_for_level", level_data)

func _capture_default_environment() -> void:
	var environment := world_environment.environment
	if environment == null:
		return
	_default_environment_state = {
		"sun_energy": sun.light_energy,
		"sun_color": sun.light_color,
		"sun_rotation": sun.rotation,
		"sun_shadow_enabled": sun.shadow_enabled,
		"ambient_light_energy": environment.ambient_light_energy,
		"ambient_light_color": environment.ambient_light_color,
		"sky": environment.sky,
		"sky_rotation": environment.sky_rotation,
		"fog_enabled": environment.fog_enabled,
		"fog_light_color": environment.fog_light_color,
		"fog_light_energy": environment.fog_light_energy,
		"fog_density": environment.fog_density,
		"fog_sky_affect": environment.fog_sky_affect,
		"tonemap_mode": environment.tonemap_mode,
		"tonemap_exposure": environment.tonemap_exposure,
		"ssao_enabled": environment.ssao_enabled,
		"ssao_radius": environment.ssao_radius,
		"ssao_intensity": environment.ssao_intensity
	}

func _apply_level_environment(level_data: Dictionary) -> void:
	var settings: Dictionary = level_data.get("environment", {}) as Dictionary
	_restore_default_environment()
	var environment := world_environment.environment
	if environment == null:
		return

	sun.light_energy = clampf(float(settings.get("sun_energy", sun.light_energy)), 0.0, 8.0)
	sun.light_color = _color_from_array(settings.get("sun_color"), sun.light_color)
	sun.shadow_enabled = bool(settings.get("sun_shadow_enabled", sun.shadow_enabled))
	if settings.has("sun_rotation_degrees"):
		sun.rotation_degrees = _vector3_from_array(
			settings.get("sun_rotation_degrees"),
			sun.rotation_degrees
		)

	environment.ambient_light_energy = clampf(
		float(settings.get("ambient_light_energy", environment.ambient_light_energy)),
		0.0,
		8.0
	)
	environment.ambient_light_color = _color_from_array(
		settings.get("ambient_light_color"),
		environment.ambient_light_color
	)

	var panorama_path := String(settings.get("sky_panorama", ""))
	if not panorama_path.is_empty() and ResourceLoader.exists(panorama_path):
		var panorama := load(panorama_path) as Texture2D
		if panorama != null:
			var sky_material := PanoramaSkyMaterial.new()
			sky_material.panorama = panorama
			sky_material.energy_multiplier = clampf(
				float(settings.get("sky_energy_multiplier", 1.0)),
				0.0,
				8.0
			)
			var sky := Sky.new()
			sky.sky_material = sky_material
			environment.sky = sky
	environment.sky_rotation.y = deg_to_rad(
		float(settings.get("sky_rotation_y_degrees", rad_to_deg(environment.sky_rotation.y)))
	)

	environment.fog_enabled = bool(settings.get("fog_enabled", environment.fog_enabled))
	environment.fog_light_color = _color_from_array(
		settings.get("fog_light_color"),
		environment.fog_light_color
	)
	environment.fog_light_energy = clampf(
		float(settings.get("fog_light_energy", environment.fog_light_energy)),
		0.0,
		8.0
	)
	environment.fog_density = clampf(
		float(settings.get("fog_density", environment.fog_density)),
		0.0,
		1.0
	)
	environment.fog_sky_affect = clampf(
		float(settings.get("fog_sky_affect", environment.fog_sky_affect)),
		0.0,
		1.0
	)

	match String(settings.get("tonemap", "")).to_lower():
		"aces":
			environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		"filmic":
			environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = clampf(
		float(settings.get("tonemap_exposure", environment.tonemap_exposure)),
		0.1,
		8.0
	)
	environment.ssao_enabled = bool(settings.get("ssao_enabled", environment.ssao_enabled))
	environment.ssao_radius = clampf(
		float(settings.get("ssao_radius", environment.ssao_radius)),
		0.01,
		16.0
	)
	environment.ssao_intensity = clampf(
		float(settings.get("ssao_intensity", environment.ssao_intensity)),
		0.0,
		8.0
	)

func _restore_default_environment() -> void:
	if _default_environment_state.is_empty() or world_environment.environment == null:
		return
	var environment := world_environment.environment
	sun.light_energy = float(_default_environment_state["sun_energy"])
	sun.light_color = _default_environment_state["sun_color"] as Color
	sun.rotation = _default_environment_state["sun_rotation"] as Vector3
	sun.shadow_enabled = bool(_default_environment_state["sun_shadow_enabled"])
	environment.ambient_light_energy = float(_default_environment_state["ambient_light_energy"])
	environment.ambient_light_color = _default_environment_state["ambient_light_color"] as Color
	environment.sky = _default_environment_state["sky"] as Sky
	environment.sky_rotation = _default_environment_state["sky_rotation"] as Vector3
	environment.fog_enabled = bool(_default_environment_state["fog_enabled"])
	environment.fog_light_color = _default_environment_state["fog_light_color"] as Color
	environment.fog_light_energy = float(_default_environment_state["fog_light_energy"])
	environment.fog_density = float(_default_environment_state["fog_density"])
	environment.fog_sky_affect = float(_default_environment_state["fog_sky_affect"])
	environment.tonemap_mode = int(_default_environment_state["tonemap_mode"]) as Environment.ToneMapper
	environment.tonemap_exposure = float(_default_environment_state["tonemap_exposure"])
	environment.ssao_enabled = bool(_default_environment_state["ssao_enabled"])
	environment.ssao_radius = float(_default_environment_state["ssao_radius"])
	environment.ssao_intensity = float(_default_environment_state["ssao_intensity"])

func _color_from_array(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		return Color(
			clampf(float(value[0]), 0.0, 1.0),
			clampf(float(value[1]), 0.0, 1.0),
			clampf(float(value[2]), 0.0, 1.0),
			clampf(float(value[3]), 0.0, 1.0) if value.size() >= 4 else 1.0
		)
	return fallback

func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

func _on_shot_resolved(result: Dictionary) -> void:
	if weapon_view_model.has_method("play_shot"):
		weapon_view_model.call("play_shot")
	if hit_feedback_layer.has_method("show_shot_feedback"):
		hit_feedback_layer.call("show_shot_feedback", result)
	if shot_debug_line.has_method("show_shot"):
		shot_debug_line.call("show_shot", result)

func _on_weapon_switched(_weapon_name: String, slot_index: int) -> void:
	if weapon_view_model.has_method("set_weapon_slot"):
		weapon_view_model.call("set_weapon_slot", slot_index)

func _on_hud_state_changed(snapshot: Dictionary) -> void:
	combat_hud.call("update_display", snapshot)

func _can_accept_combat_input() -> bool:
	return game_started and not menu_open

func find_level_option_index(target_level_id: String) -> int:
	for index in range(level_options.size()):
		var option: Dictionary = level_options[index] as Dictionary
		if String(option.get("id", "")) == target_level_id:
			return index
	return -1

func _has_local_level(level_path: String, visual_path: String) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return FileAccess.file_exists(level_path) \
		and ResourceLoader.exists(visual_path, "PackedScene")

func _update_ui(force: bool) -> void:
	if force:
		combat_hud.call("update_display", GameState.get_hud_snapshot())
	var snapshot: Dictionary = {}
	if player.has_method("get_debug_snapshot"):
		snapshot = player.call("get_debug_snapshot", menu_open)
	if force or status_panel.visible:
		status_panel.call("update_display", snapshot)
