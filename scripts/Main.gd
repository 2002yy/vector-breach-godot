extends Node3D

const LEVEL_OPTIONS := [
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
		"name": "\u4ed3\u5e93\u7ad9",
		"preview": "res://assets/maps/foundry-depot-preview.png",
		"description": "\u504f CS \u8282\u594f\u7684\u7070\u76d2\u5730\u56fe\uff0c\u5305\u542b\u4e2d\u8def\u3001\u4fa7\u8def\u548c\u4e0a\u5c42\u538b\u5236\u8def\u7ebf\u3002",
		"route_profile": "\u4e2d\u8def\u3001\u4fa7\u7ffc\u8def\u3001\u4e0a\u5c42\u538b\u5236\u7ebf",
		"recommended_use": "\u6e05\u70b9\u3001\u5f00\u5c40\u4ea4\u6218\u8282\u594f\u3001\u8f6c\u70b9\u65f6\u95f4\u6d4b\u8bd5",
		"test_focus": "Peek \u8282\u594f\u3001\u8def\u7ebf\u65f6\u5e8f\u3001\u67aa\u7ebf\u9a8c\u8bc1"
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
	}
]

@onready var level: Node3D = $Level
@onready var player: CharacterBody3D = $Player
@onready var start_menu: CanvasLayer = $StartMenu
@onready var combat_hud: CanvasLayer = $CombatHud
@onready var status_panel: CanvasLayer = $StatusPanel
@onready var hit_feedback_layer: CanvasLayer = $HitFeedbackLayer
@onready var weapon_system: Node = $WeaponSystem
@onready var weapon_view_model: Node3D = $Player/CameraPivot/Camera3D/WeaponViewModel
@onready var combat_sandbox: Node3D = $CombatSandbox
@onready var shot_debug_line: Node3D = $ShotDebugLine

var selected_level_index: int = 0
var game_started: bool = false
var menu_open: bool = true
var _ui_update_timer: float = 0.0
const UI_UPDATE_INTERVAL: float = 0.18

func _ready() -> void:
	GameState.set_graphics_preset("prototype")
	if level.has_signal("level_loaded"):
		level.connect("level_loaded", _on_level_loaded)
	if weapon_system.has_signal("shot_resolved"):
		weapon_system.connect("shot_resolved", _on_shot_resolved)
	if weapon_system.has_signal("weapon_switched"):
		weapon_system.connect("weapon_switched", _on_weapon_switched)
	if not GameState.hud_state_changed.is_connected(_on_hud_state_changed):
		GameState.hud_state_changed.connect(_on_hud_state_changed)
	start_menu.call("set_map_options", LEVEL_OPTIONS, selected_level_index)
	start_menu.connect("start_pressed", _on_start_pressed)
	start_menu.connect("resume_pressed", _on_resume_pressed)
	start_menu.connect("map_selected", _on_map_selected)
	_apply_selected_map()
	_open_menu(true)
	_update_ui(true)

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
	var option: Dictionary = LEVEL_OPTIONS[selected_level_index]
	start_menu.call("set_map_details", option, game_started)
	GameState.set_level(String(option["id"]), String(option["name"]))
	_update_ui(true)

func _on_map_selected(index: int) -> void:
	selected_level_index = index
	_apply_selected_map()

func _on_start_pressed() -> void:
	var option: Dictionary = LEVEL_OPTIONS[selected_level_index]
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
	start_menu.call("set_map_details", LEVEL_OPTIONS[selected_level_index], game_started and not initial_open)
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
	if combat_sandbox.has_method("load_for_level"):
		combat_sandbox.call("load_for_level", level_data)

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

func _update_ui(force: bool) -> void:
	if force:
		combat_hud.call("update_display", GameState.get_hud_snapshot())
	var snapshot: Dictionary = {}
	if player.has_method("get_debug_snapshot"):
		snapshot = player.call("get_debug_snapshot", menu_open)
	if force or status_panel.visible:
		status_panel.call("update_display", snapshot)
