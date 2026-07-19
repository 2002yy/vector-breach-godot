extends Node3D

const WorldWeaponPickup = preload("res://scripts/combat/WorldWeaponPickup.gd")

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
		"name": "铸造仓库 v2（冻结）",
		"preview": "res://assets/maps/foundry-depot-preview.png",
		"description": "已冻结的铸造仓库 v2：保留现有中路、侧路和上层压制结构，后续设计不再覆盖此版。",
		"route_profile": "\u4e2d\u8def\u3001\u4fa7\u7ffc\u8def\u3001\u4e0a\u5c42\u538b\u5236\u7ebf",
		"recommended_use": "\u65e7\u7248\u5bf9\u7167\u3001\u56de\u5f52\u9a8c\u8bc1\u4e0e\u4f5c\u54c1\u96c6\u5386\u53f2\u7559\u75d5",
		"test_focus": "冻结基线、探头节奏、路线时序、枪线验证"
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
		"description": "冻结铸造仓库 v2 后独立重建的双目标对抗灰盒；三条地面主路围绕中路转点，只在 B 区保留一段局部高台选择。",
		"route_profile": "A \u957f\u8def\u3001\u4e2d\u8def\u8f6c\u70b9\u3001B \u7ef4\u4fee\u901a\u9053 + B \u533a\u5c40\u90e8\u9ad8\u53f0",
		"recommended_use": "\u53cc\u76ee\u6807\u8fdb\u653b\u9009\u62e9\u3001\u56de\u9632\u8f6c\u70b9\u4e0e\u4ea4\u706b\u8ddd\u79bb\u9a8c\u8bc1",
		"test_focus": "\u9996\u8f6e\u63a5\u89e6\u65f6\u5e8f\u3001\u4e09\u8def\u4e92\u901a\u3001\u76ee\u6807\u533a\u6e05\u70b9\u4e0e\u5c40\u90e8\u9ad8\u5dee"
	}
]

const LOCAL_DUSTLINE_LEVEL_PATH := "res://data/levels/dustline-depths.json"
const LOCAL_DUSTLINE_VISUAL_PATH := "res://assets/models/dustline/dustline_depths.glb"
const LOCAL_DUSTLINE_OPTION := {
	"id": "dustline-depths",
	"name": "沙线深层（本机参考）",
	"preview": "res://assets/maps/dustline-depths-preview.png",
	"description": "本机参考试玩：锁定参考地图地面拓扑，仅在 B 区增加一条空中走廊。派生碰撞与参考资源不进入版本库。",
	"route_profile": "\u53c2\u8003\u5730\u9762\u4e09\u8def\u7ebf + B \u533a\u5355\u6761\u53ef\u9009\u9ad8\u53f0",
	"recommended_use": "\u6bd4\u4f8b\u3001\u906e\u6321\u3001\u8def\u7ebf\u4e0e\u4ea4\u706b\u8ddd\u79bb\u5bf9\u7167",
	"test_focus": "关键门洞、坡度、掩体尺度与空中走廊差异层"
}

const LOCAL_REFERENCE_LEVEL_PATH := "res://data/levels/dustline-depths-original-local.json"
const LOCAL_REFERENCE_VISUAL_PATH := "res://assets/local_reference/dustline/de_dust2_original.glb"
const LOCAL_REFERENCE_OPTION := {
	"id": "dustline-depths-original-local",
	"name": "沙线原始材质（本机）",
	"preview": "res://assets/maps/dustline-depths-preview.png",
	"description": "仅本机试玩：原始沙线完整视觉 + 已审计碰撞 + B 区空中走廊；参考资源不会进入版本库。",
	"route_profile": "\u539f\u59cb\u5730\u9762\u5c42\u89c6\u89c9 + \u5355\u6761 B \u533a\u53ef\u9009\u9ad8\u53f0",
	"recommended_use": "\u5bf9\u9f50\u539f\u59cb\u6750\u8d28\u3001\u6bd4\u4f8b\u3001\u906e\u6321\u548c\u8def\u7ebf\u8fa8\u8bc6\u5ea6",
	"test_focus": "视觉/碰撞对齐、材质导入、空中走廊差异层"
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
@onready var combat_audio_feedback: Node = $CombatAudioFeedback
@onready var c4_device: Node3D = $C4Device
@onready var tactical_equipment: Node = $TacticalEquipment

var selected_level_index: int = 1
var level_options: Array = []
var game_started: bool = false
var menu_open: bool = true
var _ui_update_timer: float = 0.0
var _radar_update_timer: float = 0.0
var _default_environment_state: Dictionary = {}
var _buy_menu_open: bool = false
var _radar_spotted_until: Dictionary = {}
var _radar_death_markers: Array[Dictionary] = []
const UI_UPDATE_INTERVAL: float = 0.18
const RADAR_UPDATE_INTERVAL: float = 0.05
const RADAR_RANGE_METERS: float = 24.0

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
	if weapon_system.has_signal("reload_started"):
		weapon_system.connect("reload_started", _on_reload_started)
	if weapon_system.has_signal("reload_finished"):
		weapon_system.connect("reload_finished", _on_reload_finished)
	if player.has_signal("footstep_emitted"):
		player.connect("footstep_emitted", _on_player_footstep)
	if player.has_signal("landed"):
		player.connect("landed", _on_player_landed)
	if combat_sandbox.has_signal("targets_spawned"):
		combat_sandbox.connect("targets_spawned", _on_targets_spawned)
	if player.has_signal("player_died"):
		player.connect("player_died", _on_player_died)
	if not RoundManager.phase_changed.is_connected(_on_round_phase_changed):
		RoundManager.phase_changed.connect(_on_round_phase_changed)
	if not RoundManager.round_ended.is_connected(_on_round_ended):
		RoundManager.round_ended.connect(_on_round_ended)
	if not RoundManager.restart_requested.is_connected(_on_round_restart_requested):
		RoundManager.restart_requested.connect(_on_round_restart_requested)
	if not RoundManager.bomb_exploded.is_connected(_on_bomb_exploded):
		RoundManager.bomb_exploded.connect(_on_bomb_exploded)
	if not GameState.hud_state_changed.is_connected(_on_hud_state_changed):
		GameState.hud_state_changed.connect(_on_hud_state_changed)
	start_menu.call("set_map_options", level_options, selected_level_index)
	start_menu.connect("start_pressed", _on_start_pressed)
	start_menu.connect("resume_pressed", _on_resume_pressed)
	start_menu.connect("map_selected", _on_map_selected)
	start_menu.connect("team_selected", _on_team_selected)
	start_menu.connect("settings_changed", _on_settings_changed)
	_apply_selected_map()
	_open_menu(true)
	_update_ui(true)

func _on_settings_changed(snapshot: Dictionary) -> void:
	UserSettings.apply_snapshot(snapshot)
	if combat_hud.has_method("apply_settings"):
		combat_hud.call("apply_settings", UserSettings.get_snapshot())

func _on_team_selected(team: String) -> void:
	GameState.player_team = team if team in ["T", "CT"] else "T"
	if is_instance_valid(c4_device):
		c4_device.call("set_carried", GameState.player_team)
	_update_ui(true)

func _isolate_environment_resource() -> void:
	if world_environment.environment != null:
		world_environment.environment = world_environment.environment.duplicate(true) as Environment

func _process(delta: float) -> void:
	_update_objective_interaction(delta)
	tactical_equipment.call("tick", delta)
	var combat_enabled := _can_accept_combat_input() and not RoundManager.is_objective_interacting()
	if game_started and not menu_open and player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", not bool(player.get("is_dead")))
		if player.has_method("set_movement_enabled"):
			player.call("set_movement_enabled", combat_enabled)
	if combat_enabled:
		var fire_pressed: bool = Input.is_action_just_pressed("fire_primary")
		var fire_held: bool = Input.is_action_pressed("fire_primary")
		if String(tactical_equipment.get("equipped")) == "firearm" and weapon_system.has_method("tick"):
			weapon_system.call("tick", delta, fire_pressed, fire_held, player)
		elif fire_pressed:
			tactical_equipment.call("use_primary", player)

	_ui_update_timer += delta
	if _ui_update_timer >= UI_UPDATE_INTERVAL:
		_ui_update_timer = 0.0
		_update_ui(false)
	_radar_update_timer += delta
	if _radar_update_timer >= RADAR_UPDATE_INTERVAL:
		_radar_update_timer = 0.0
		if combat_hud.has_method("update_radar"):
			combat_hud.call("update_radar", _build_radar_snapshot())

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

	if event.is_action_pressed("buy_menu"):
		if game_started and not menu_open and RoundManager.can_buy():
			_buy_menu_open = not _buy_menu_open
			if combat_hud.has_method("set_buy_menu_visible"):
				combat_hud.call("set_buy_menu_visible", _buy_menu_open)
		get_viewport().set_input_as_handled()
		return

	if _buy_menu_open and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]:
			var buy_items := {KEY_1: "rifle", KEY_2: "pistol", KEY_3: "armor", KEY_4: "armor_helmet", KEY_5: "defuse_kit", KEY_6: "he_grenade", KEY_7: "flash_grenade", KEY_8: "smoke_grenade"}
			_purchase_item(String(buy_items[event.keycode]))
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("interact"):
		if _can_accept_combat_input():
			if not _try_pickup_weapon():
				_try_begin_objective_interaction()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("drop_weapon"):
		if _can_accept_combat_input() and String(tactical_equipment.get("equipped")) == "firearm":
			var dropped := weapon_system.call("drop_current_weapon") as Dictionary
			if not dropped.is_empty():
				var pickup := WorldWeaponPickup.new()
				add_child(pickup)
				pickup.configure(dropped, player.global_position - player.global_transform.basis.z * 0.9 - Vector3.UP * 0.75)
				if not bool((weapon_system.call("get_runtime_snapshot") as Dictionary).get("owned", false)):
					tactical_equipment.call("select_knife")
		elif _can_accept_combat_input() and RoundManager.bomb_carried and GameState.player_team == "T":
			RoundManager.bomb_carried = false
			c4_device.call("drop_at", player.global_position + -player.global_transform.basis.z * 0.8)
			_update_ui(true)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("reload_weapon"):
		if _can_accept_weapon_management() and weapon_system.has_method("request_reload"):
			weapon_system.call("request_reload")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_1"):
		if _can_accept_weapon_management() and weapon_system.has_method("switch_to_slot"):
			tactical_equipment.call("select_firearm")
			weapon_system.call("switch_to_slot", 0)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_2"):
		if _can_accept_weapon_management() and weapon_system.has_method("switch_to_slot"):
			tactical_equipment.call("select_firearm")
			weapon_system.call("switch_to_slot", 1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_3"):
		if _can_accept_weapon_management():
			tactical_equipment.call("select_knife")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_4"):
		if _can_accept_weapon_management():
			tactical_equipment.call("select_next_grenade")
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
	GameState.reset_runtime_state()
	_clear_round_drops()
	level.call("load_level", option["id"])
	if player.has_method("reset_to_spawn"):
		player.call("reset_to_spawn")
	game_started = true
	GameState.set_game_started(true)
	if weapon_system.has_method("configure_default_loadout"):
		weapon_system.call("configure_default_loadout", true, true)
	tactical_equipment.call("reset_loadout")
	if weapon_view_model.has_method("set_weapon_slot"):
		var equipped_slot := int((weapon_system.call("get_runtime_snapshot") as Dictionary).get("weapon_slot", 0))
		weapon_view_model.call("set_weapon_slot", equipped_slot, false)
	RoundManager.start_round()
	c4_device.call("set_carried", GameState.player_team)
	_resume_game()

func _on_resume_pressed() -> void:
	_resume_game()

func _resume_game() -> void:
	var was_paused := RoundManager.state == RoundManager.RoundState.PAUSED_MENU
	menu_open = false
	GameState.set_menu_state(false)
	if was_paused:
		RoundManager.resume_round()
	start_menu.call("set_menu_visible", false)
	if player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", game_started and not bool(player.get("is_dead")))
	if player.has_method("set_movement_enabled"):
		player.call("set_movement_enabled", _can_accept_combat_input())
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

	var sky_mode := String(settings.get("sky_mode", "")).to_lower()
	if sky_mode == "physical":
		var physical_material := PhysicalSkyMaterial.new()
		physical_material.energy_multiplier = clampf(
			float(settings.get("sky_energy_multiplier", 1.0)),
			0.0,
			8.0
		)
		physical_material.turbidity = clampf(
			float(settings.get("sky_turbidity", physical_material.turbidity)),
			0.0,
			1000.0
		)
		physical_material.ground_color = _color_from_array(
			settings.get("sky_ground_color"),
			physical_material.ground_color
		)
		physical_material.mie_coefficient = clampf(
			float(settings.get("sky_mie_coefficient", physical_material.mie_coefficient)),
			0.0,
			1.0
		)
		physical_material.mie_color = _color_from_array(
			settings.get("sky_mie_color"),
			physical_material.mie_color
		)
		physical_material.rayleigh_coefficient = clampf(
			float(settings.get("sky_rayleigh_coefficient", physical_material.rayleigh_coefficient)),
			0.0,
			64.0
		)
		physical_material.rayleigh_color = _color_from_array(
			settings.get("sky_rayleigh_color"),
			physical_material.rayleigh_color
		)
		physical_material.sun_disk_scale = clampf(
			float(settings.get("sky_sun_disk_scale", physical_material.sun_disk_scale)),
			0.0,
			16.0
		)
		physical_material.use_debanding = bool(settings.get("sky_use_debanding", true))
		var physical_sky := Sky.new()
		physical_sky.sky_material = physical_material
		environment.sky = physical_sky
	var panorama_path := String(settings.get("sky_panorama", ""))
	if sky_mode != "physical" and not panorama_path.is_empty() and ResourceLoader.exists(panorama_path):
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
	if combat_audio_feedback.has_method("play_shot"):
		combat_audio_feedback.call("play_shot", result, player.global_position)
	var damage_result: Dictionary = result.get("damage_result", {}) as Dictionary
	if bool(damage_result.get("killed", false)) and combat_hud.has_method("add_kill_feed"):
		var death_position: Vector3 = result.get("position", Vector3.ZERO) as Vector3
		_radar_death_markers.append({
			"team": "CT" if GameState.player_team == "T" else "T", "alive": false, "spotted": true,
			"x": death_position.x, "y": death_position.y, "z": death_position.z,
			"expires": Time.get_ticks_msec() + 5000,
		})
		combat_hud.call("add_kill_feed", "你", String(damage_result.get("target_name", "训练目标")), String(result.get("weapon_name", "步枪")))
		if GameState.enemy_alive == 0 and RoundManager.state in [RoundManager.RoundState.LIVE, RoundManager.RoundState.BOMB_PLANTED]:
			RoundManager.end_round("T", "ELIMINATION")

func _on_targets_spawned(count: int) -> void:
	GameState.set_training_target_count(count)

func _on_player_died() -> void:
	RoundManager.end_round("CT", "ELIMINATION")

func _on_round_phase_changed(_state_name: String) -> void:
	if not RoundManager.can_buy():
		_buy_menu_open = false
		if combat_hud.has_method("set_buy_menu_visible"):
			combat_hud.call("set_buy_menu_visible", false)
	_update_ui(true)

func _on_round_ended(winner: String, reason: String) -> void:
	GameState.complete_round(winner, reason)
	_update_ui(true)

func _on_round_restart_requested() -> void:
	var player_survived := not bool(player.get("is_dead"))
	_clear_round_drops()
	GameState.prepare_next_round()
	var option: Dictionary = level_options[selected_level_index]
	level.call("load_level", option["id"])
	player.call("reset_to_spawn")
	if not player_survived:
		weapon_system.call("configure_default_loadout", true, true)
		tactical_equipment.call("reset_loadout")
	RoundManager.start_round()
	c4_device.call("set_carried", GameState.player_team)

func _purchase_item(item_id: String) -> void:
	var in_buy_zone := player.global_position.distance_to(GameState.player_spawn) <= 8.0
	var slot_index := 0 if item_id == "rifle" else (1 if item_id == "pistol" else -1)
	var already_owned := slot_index >= 0 and bool(weapon_system.call("is_slot_owned", slot_index))
	var result: Dictionary
	if not in_buy_zone:
		result = {"success": false, "reason": "请返回出生点购买区"}
	elif already_owned:
		result = {"success": false, "reason": "已拥有该武器；弹药随武器保留"}
	else:
		result = GameState.purchase(item_id)
	if bool(result.get("success", false)) and item_id in ["rifle", "pistol"] and weapon_system.has_method("purchase_slot"):
		weapon_system.call("purchase_slot", 0 if item_id == "rifle" else 1)
	if bool(result.get("success", false)) and item_id in ["he_grenade", "flash_grenade", "smoke_grenade"]:
		if not bool(tactical_equipment.call("purchase_grenade", item_id)):
			GameState.player_money = mini(GameState.MAX_MONEY, GameState.player_money + int(result.get("price", 0)))
			GameState.notify_player_vitals_changed()
			result = {"success": false, "reason": "该投掷物已达携带上限"}
	if combat_hud.has_method("show_purchase_result"):
		combat_hud.call("show_purchase_result", String(result.get("reason", "购买成功")))

func _try_plant_c4() -> bool:
	return _try_begin_objective_interaction()

func _try_pickup_weapon() -> bool:
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		if pickup is Node3D and pickup.has_method("can_pick_up") and bool(pickup.call("can_pick_up", player.global_position)):
			if bool(weapon_system.call("pickup_weapon", pickup.get("weapon_record"))):
				tactical_equipment.call("select_firearm")
				pickup.queue_free()
				return true
	return false

func _clear_round_drops() -> void:
	for group_name in ["weapon_pickups", "grenade_projectiles"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()

func _try_begin_objective_interaction() -> bool:
	if c4_device.call("can_pick_up", player.global_position, GameState.player_team):
		if bool(c4_device.call("pick_up", GameState.player_team)):
			RoundManager.bomb_carried = true
			_update_ui(true)
			return true
	if GameState.player_team == "CT" and RoundManager.state == RoundManager.RoundState.BOMB_PLANTED:
		if bool(c4_device.call("is_player_in_interaction_range", player.global_position)):
			return RoundManager.begin_defuse(GameState.player_team, GameState.player_defuse_kit)
		return false
	if not RoundManager.bomb_carried or GameState.player_team != "T":
		return false
	var site := _get_current_plant_site()
	return RoundManager.begin_plant(String(site.get("label", "")), GameState.player_team) if not site.is_empty() else false

func _get_current_plant_site() -> Dictionary:
	var radar_snapshot := _build_radar_snapshot()
	var player_position := Vector2(player.global_position.x, player.global_position.z)
	for target_variant in radar_snapshot.get("targets", []):
		var target := target_variant as Dictionary
		var target_position := Vector2(float(target.get("x", 0.0)), float(target.get("z", 0.0)))
		var plant_radius := maxf(3.0, minf(float(target.get("sx", 6.0)), float(target.get("sz", 6.0))) * 0.5)
		if player_position.distance_to(target_position) <= plant_radius:
			return target
	return {}

func _update_objective_interaction(delta: float) -> void:
	if not game_started or menu_open or bool(player.get("is_dead")):
		return
	if not Input.is_action_pressed("interact"):
		RoundManager.cancel_objective_interaction()
		return
	if not RoundManager.is_objective_interacting():
		_try_begin_objective_interaction()
	if not RoundManager.is_objective_interacting():
		return
	var interaction_type := RoundManager.interaction_type
	var interaction_site := RoundManager.interaction_site
	var still_valid := false
	if interaction_type == "plant":
		var site := _get_current_plant_site()
		still_valid = String(site.get("label", "")) == interaction_site and RoundManager.bomb_carried
	elif interaction_type == "defuse":
		still_valid = bool(c4_device.call("is_player_in_interaction_range", player.global_position))
	var completed := RoundManager.tick_objective_interaction(delta, still_valid)
	if completed and interaction_type == "plant":
		c4_device.call("plant_at", player.global_position - Vector3(0.0, 0.82, 0.0), interaction_site)
		GameState.reward_objective_action("plant")
	elif completed and interaction_type == "defuse":
		c4_device.call("set_carried", "CT")

func _on_bomb_exploded(_site_label: String) -> void:
	var damage := int(c4_device.call(
		"calculate_explosion_damage",
		player.global_position,
		get_world_3d().direct_space_state,
		[player.get_rid()]
	))
	if damage > 0 and not bool(player.get("is_dead")):
		player.call("apply_hitscan_damage", damage, player.global_position, 0.65, false)

func _on_player_footstep(world_position: Vector3, surface: String, quiet: bool) -> void:
	if combat_audio_feedback.has_method("play_footstep"):
		combat_audio_feedback.call("play_footstep", world_position, surface, quiet)

func _on_player_landed(world_position: Vector3, surface: String, strength: float) -> void:
	if combat_audio_feedback.has_method("play_landing"):
		combat_audio_feedback.call("play_landing", world_position, surface, strength)

func _on_weapon_switched(_weapon_name: String, slot_index: int) -> void:
	if weapon_view_model.has_method("set_weapon_slot"):
		weapon_view_model.call("set_weapon_slot", slot_index)
	if combat_audio_feedback.has_method("play_weapon_switched"):
		combat_audio_feedback.call("play_weapon_switched")

func _on_reload_started() -> void:
	if combat_audio_feedback.has_method("play_reload_started"):
		combat_audio_feedback.call("play_reload_started")

func _on_reload_finished() -> void:
	if combat_audio_feedback.has_method("play_reload_finished"):
		combat_audio_feedback.call("play_reload_finished")

func _on_hud_state_changed(snapshot: Dictionary) -> void:
	combat_hud.call("update_display", _build_hud_snapshot(snapshot))

func _can_accept_combat_input() -> bool:
	return game_started and not menu_open and RoundManager.can_player_move() and not bool(player.get("is_dead"))

func _can_accept_weapon_management() -> bool:
	return game_started \
		and not menu_open \
		and RoundManager.state in [RoundManager.RoundState.FREEZE, RoundManager.RoundState.LIVE, RoundManager.RoundState.BOMB_PLANTED] \
		and not RoundManager.is_objective_interacting() \
		and not bool(player.get("is_dead"))

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
	combat_hud.call("update_display", _build_hud_snapshot(GameState.get_hud_snapshot()))
	var snapshot: Dictionary = {}
	if player.has_method("get_debug_snapshot"):
		snapshot = player.call("get_debug_snapshot", menu_open)
	if force or status_panel.visible:
		status_panel.call("update_display", snapshot)

func _build_hud_snapshot(snapshot: Dictionary) -> Dictionary:
	var enriched := snapshot.duplicate(true)
	enriched["radar"] = _build_radar_snapshot()
	enriched["flash_intensity"] = float(player.call("get_flash_intensity"))
	return enriched

func _build_radar_snapshot() -> Dictionary:
	var level_data: Dictionary = level.call("get_current_level_data") if level.has_method("get_current_level_data") else {}
	var arena_size := float(level_data.get("arenaSize", 56.0))
	var bounds := Vector2(
		float(level_data.get("arenaSizeX", arena_size)),
		float(level_data.get("arenaSizeZ", arena_size))
	)
	var targets: Array[Dictionary] = []
	for objective_variant in level_data.get("objectives", []):
		if not objective_variant is Dictionary:
			continue
		var objective := objective_variant as Dictionary
		var objective_id := String(objective.get("id", "")).to_lower()
		var objective_label := "A" if objective_id.contains("a") else ("B" if objective_id.contains("b") else "T")
		var objective_radius := float(objective.get("radius", 2.0))
		targets.append({
			"label": objective_label,
			"x": float(objective.get("x", 0.0)),
			"z": float(objective.get("z", 0.0)),
			"sx": objective_radius * 2.0,
			"sz": objective_radius * 2.0,
		})
	for floor_variant in level_data.get("floors", []):
		if not targets.is_empty():
			break
		if not floor_variant is Dictionary:
			continue
		var floor_entry := floor_variant as Dictionary
		var floor_id := String(floor_entry.get("id", "")).to_lower()
		if not floor_id.contains("site"):
			continue
		var label := "T"
		if floor_id.contains("site-a"):
			label = "A"
		elif floor_id.contains("site-b"):
			label = "B"
		targets.append({
			"label": label,
			"x": float(floor_entry.get("x", 0.0)),
			"z": float(floor_entry.get("z", 0.0)),
			"sx": float(floor_entry.get("sx", 2.0)),
			"sz": float(floor_entry.get("sz", 2.0)),
		})
	if targets.is_empty():
		var target_route: Variant = (level_data.get("routes", {}) as Dictionary).get("target", [])
		if target_route is Array and target_route.size() >= 2:
			targets.append({"label": "T", "x": float(target_route[0]), "z": float(target_route[1])})
	return {
		"bounds": bounds,
		"range_meters": UserSettings.radar_range,
		"player_position": Vector2(player.global_position.x, player.global_position.z),
		"player_yaw": player.rotation.y if UserSettings.radar_rotates else 0.0,
		"player_height": player.global_position.y,
		"local_team": GameState.player_team,
		"targets": targets,
		"features": _collect_radar_features(level_data),
		"players": _build_radar_players(),
		"c4": c4_device.call("get_radar_record"),
	}

func _build_radar_players() -> Array[Dictionary]:
	var records: Array[Dictionary] = [{
		"team": GameState.player_team,
		"alive": not bool(player.get("is_dead")),
		"local": true,
		"x": player.global_position.x,
		"y": player.global_position.y,
		"z": player.global_position.z,
		"yaw": player.rotation.y,
	}]
	for target in get_tree().get_nodes_in_group("target_dummies"):
		if target is Node3D:
			var target_node := target as Node3D
			var target_id := target_node.get_instance_id()
			if _is_target_legally_spotted(target_node):
				_radar_spotted_until[target_id] = Time.get_ticks_msec() + 2500
			records.append({
				"team": "CT" if GameState.player_team == "T" else "T",
				"alive": true,
				"spotted": int(_radar_spotted_until.get(target_id, 0)) >= Time.get_ticks_msec(),
				"x": target_node.global_position.x,
				"y": target_node.global_position.y,
				"z": target_node.global_position.z,
			})
	var now := Time.get_ticks_msec()
	var retained_markers: Array[Dictionary] = []
	for marker in _radar_death_markers:
		if int(marker.get("expires", 0)) >= now:
			retained_markers.append(marker)
			records.append(marker)
	_radar_death_markers = retained_markers
	return records

func _is_target_legally_spotted(target: Node3D) -> bool:
	var camera := player.call("get_camera_node") as Camera3D
	if camera == null:
		return false
	var target_point := target.global_position + Vector3.UP * 0.25
	var delta := target_point - camera.global_position
	if delta.length() > UserSettings.radar_range or delta.length_squared() <= 0.001:
		return false
	if (-camera.global_transform.basis.z).dot(delta.normalized()) < 0.42:
		return false
	if _is_segment_blocked_by_smoke(camera.global_position, target_point):
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target_point)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider", null) == target

func _is_segment_blocked_by_smoke(from: Vector3, to: Vector3) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false
	for smoke in get_tree().get_nodes_in_group("smoke_volumes"):
		if smoke is Node3D:
			var t := clampf(((smoke as Node3D).global_position - from).dot(segment) / length_squared, 0.0, 1.0)
			var closest := from + segment * t
			if closest.distance_to((smoke as Node3D).global_position) <= 3.1:
				return true
	return false

func _collect_radar_features(level_data: Dictionary) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	for collection_name in ["walls", "covers", "obstacles", "floors", "stairs", "ramps", "catwalks"]:
		for feature_variant in level_data.get(collection_name, []):
			if not feature_variant is Dictionary:
				continue
			var feature := (feature_variant as Dictionary).duplicate(true)
			if not feature.has("role"):
				feature["role"] = String(collection_name).trim_suffix("s")
			features.append(feature)
	return features
