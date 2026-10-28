extends Node3D

signal level_prepared(level_data: Dictionary)
signal level_start_failed(level_id: String)

const WorldWeaponPickup = preload("res://scripts/combat/WorldWeaponPickup.gd")
const TrainingTelemetry = preload("res://scripts/training/TrainingTelemetry.gd")
const ClassicMatchLayout = preload("res://scripts/level/ClassicMatchLayout.gd")
const LocalClassicMaps = preload("res://scripts/level/LocalClassicMaps.gd")
const MatchSpectator = preload("res://scripts/player/MatchSpectator.gd")
const WeaponCatalog = preload("res://scripts/combat/WeaponCatalog.gd")

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
		"name": "铸造仓库（路线回归）",
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
	"name": "沙线深层（经典 CS 复刻）",
	"preview": "res://assets/maps/dustline-depths-preview.png",
	"description": "经典 CS 的 de_dust2 地面拓扑复刻研究图，B 区加空中走廊。本机可进行 5 对 5 爆破：你与四名 AI 队友对抗五名敌人，含购买、换边和结算；参考资源不进入版本库。",
	"route_profile": "\u53c2\u8003\u5730\u9762\u4e09\u8def\u7ebf + B \u533a\u5355\u6761\u53ef\u9009\u9ad8\u53f0",
	"recommended_use": "\u6bd4\u4f8b\u3001\u906e\u6321\u3001\u8def\u7ebf\u4e0e\u4ea4\u706b\u8ddd\u79bb\u5bf9\u7167",
	"test_focus": "关键门洞、坡度、掩体尺度与空中走廊差异层"
}

const LOCAL_REFERENCE_LEVEL_PATH := "res://data/levels/dustline-depths-original-local.json"
const LOCAL_REFERENCE_VISUAL_PATH := "res://assets/local_reference/dustline/de_dust2_original.glb"
const LOCAL_REFERENCE_OPTION := {
	"id": "dustline-depths-original-local",
	"name": "沙线·原始材质（经典 CS 复刻）",
	"preview": "res://assets/maps/dustline-depths-preview.png",
	"description": "经典 CS 复刻研究图的原始视觉 / 材质版本，使用审计碰撞与 B 区空中走廊。可进行 5 对 5 爆破，开局购买并点击就绪开战；仅本机保留。",
	"route_profile": "\u539f\u59cb\u5730\u9762\u5c42\u89c6\u89c9 + \u5355\u6761 B \u533a\u53ef\u9009\u9ad8\u53f0",
	"recommended_use": "\u5bf9\u9f50\u539f\u59cb\u6750\u8d28\u3001\u6bd4\u4f8b\u3001\u906e\u6321\u548c\u8def\u7ebf\u8fa8\u8bc6\u5ea6",
	"test_focus": "视觉/碰撞对齐、材质导入、空中走廊差异层"
}

var spectator: Node3D

var last_start_timings: Dictionary = {}
var _starting := false
var _preparation_timings: Dictionary = {}

var _start_failure := "map"

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

var selected_level_index: int = 2
var level_options: Array = []
var game_started: bool = false
var menu_open: bool = true
var _ui_update_timer: float = 0.0
var _radar_update_timer: float = 0.0
var _default_environment_state: Dictionary = {}
var _buy_menu_open: bool = false
var _radar_spotted_until: Dictionary = {}
var _radar_death_markers: Array[Dictionary] = []
var training_telemetry: Node
var selected_start_team: String = "T"
var _completed_match_record_path: String = ""
var _level_loading := false
var _level_load_failed := false
var _level_load_serial := 0
var _training_respawn_seconds := 0.0
const UI_UPDATE_INTERVAL: float = 0.18
const RADAR_UPDATE_INTERVAL: float = 0.05
const RADAR_RANGE_METERS: float = 24.0

func _training_active() -> bool:
	return game_started and GameState.current_level_id == "training-range"

func _training_supply(clear_projectiles: bool = false) -> void:
	if not _training_active():
		return
	weapon_system.call("refill_training_reserve")
	for kind in ["he_grenade", "flash_grenade", "smoke_grenade", "fire_grenade"]:
		(tactical_equipment.get("grenade_counts") as Dictionary)[kind] = 2 if kind == "flash_grenade" else 1
	if clear_projectiles:
		_clear_round_drops()

func _reset_training() -> void:
	if not _training_active():
		return
	_training_respawn_seconds = 0.0
	GameState.player_health = 100
	GameState.player_armor = 0
	GameState.player_helmet = false
	GameState.player_defuse_kit = false
	GameState.player_money = 0
	GameState.hit_count = 0
	GameState.kill_count = 0
	GameState.unit_scoreboard.clear()
	RoundManager.cancel_objective_interaction()
	RoundManager.bomb_carried = false
	c4_device.call("set_carried", "T", 0)
	_clear_round_drops()
	combat_sandbox.call("clear_saved_round_state", true)
	combat_sandbox.call("load_for_level", level.call("get_current_level_data"))
	player.call("reset_to_spawn")
	weapon_system.call("configure_default_loadout", true, false)
	tactical_equipment.call("reset_loadout")
	tactical_equipment.call("select_firearm")
	training_telemetry.call("begin_round", 1)
	_training_supply(true)
	if not menu_open:
		RoundManager.set_live()
	player.call("set_controls_enabled", not menu_open)
	player.call("set_movement_enabled", _can_accept_combat_input())
	player.call("set_mouse_capture_enabled", not menu_open)
	combat_hud.call("show_training_panel", true)
	_update_ui(true)

func _tick_training(delta: float) -> void:
	_training_supply()
	var living := 0
	for target in combat_sandbox.get_children():
		if not bool(target.get("is_dead")):
			living += 1
	if living < 3:
		_training_respawn_seconds += delta
		if _training_respawn_seconds >= 2.0:
			for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
				pickup.queue_free()
			combat_sandbox.call("load_for_level", level.call("get_current_level_data"))
			_training_respawn_seconds = 0.0
	else:
		_training_respawn_seconds = 0.0

func _leave_training() -> void:
	if not _training_active():
		return
	_training_supply(true)
	_clear_round_drops()
	game_started = false
	GameState.reset_runtime_state()
	GameState.set_game_started(false)
	combat_hud.call("show_training_panel", false)
	_open_menu(true)

func _ready() -> void:
	GameState.area_damage_resolved.connect(_on_area_damage)
	spectator = MatchSpectator.new()
	spectator.name = "MatchSpectator"
	add_child(spectator)
	training_telemetry = TrainingTelemetry.new()
	add_child(training_telemetry)
	_isolate_environment_resource()
	_capture_default_environment()
	GameState.set_graphics_preset("prototype")
	level_options = SHIPPED_LEVEL_OPTIONS.duplicate(true)
	level_options.append({"id": "training-range", "name": "独立训练场", "preview": "res://assets/maps/yard-preview.png", "description": "独立射击与投掷训练：无限备弹、自动补雷，靶子击倒后重生。F5 重置全部，F6 补给/清场，F7 返回选图。练习命中、爆头、压枪及投掷距离和飞行时间。", "recommended_use": "自由训练，不计比赛成绩与经济"})
	var map_purposes := {
		"gatehouse": ["主比赛图：三路、双爆点，玩家与两名队友对抗三名敌人。包含手枪局、购买、换边和比赛结算。", "3 对 3 爆破比赛；首次游玩推荐"],
		"foundry-reforged": ["原创双目标练习与视觉展示图；由铸造仓库经验重新设计，尚未迁移完整 3 对 3 比赛。", "步枪 / 手枪练习、地图探索与画面展示"],
		"depot": ["冻结的铸造仓库第二版：历史尺度与路线基线，保留作对照，不是主比赛图。", "历史对照与回归测试"],
		"core-vault": ["源自旧灰盒的密集库区，包含爆破 AI；用于高密度战斗回归，未承诺与主地图同级平衡。", "进阶测试；不作为首次比赛推荐"],
		"test-collision-room": ["开发测试房：验证移动、台阶、梯子和水体，不是正式比赛地图。", "开发调试与碰撞回归"],
	}
	for option in level_options:
		if String(option["id"]) == "training-range":
			continue
		var purpose: Array = map_purposes[String(option["id"])]
		option["description"] = purpose[0]
		option["recommended_use"] = purpose[1]
	if _has_local_level(LOCAL_DUSTLINE_LEVEL_PATH, LOCAL_DUSTLINE_VISUAL_PATH):
		level_options.append(LOCAL_DUSTLINE_OPTION.duplicate(true))
	if _has_local_level(LOCAL_REFERENCE_LEVEL_PATH, LOCAL_REFERENCE_VISUAL_PATH):
		level_options.append(LOCAL_REFERENCE_OPTION.duplicate(true))
	level_options.append_array(LocalClassicMaps.installed_options())
	for index in range(level_options.size()):
		if String(level_options[index].get("id", "")) == "inferno-classic-local":
			selected_level_index = index
			break
	if level.has_signal("level_loaded"):
		level.connect("level_loaded", _on_level_loaded)
	if level.has_signal("load_progress"):
		level.connect("load_progress", _on_loading_progress)
	if combat_sandbox.has_signal("load_progress"):
		combat_sandbox.connect("load_progress", _on_loading_progress)
	if weapon_system.has_signal("shot_resolved"):
		weapon_system.connect("shot_resolved", _on_shot_resolved)
	tactical_equipment.connect("equipment_changed", _sync_equipment_view)
	tactical_equipment.connect("equipment_used", weapon_view_model.play_equipment_use)
	tactical_equipment.connect("melee_resolved", _on_melee_resolved)
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
	if combat_sandbox.has_signal("combatants_spawned"):
		combat_sandbox.connect("combatants_spawned", _on_combatants_spawned)
	elif combat_sandbox.has_signal("targets_spawned"):
		combat_sandbox.connect("targets_spawned", _on_targets_spawned)
	if combat_sandbox.has_signal("ai_shot"):
		combat_sandbox.connect("ai_shot", _on_ai_shot)
	if combat_sandbox.has_signal("ai_footstep"):
		combat_sandbox.connect("ai_footstep", _on_ai_footstep)
	if combat_sandbox.has_signal("radio_report"):
		combat_sandbox.connect("radio_report", _on_radio_report)
	if combat_sandbox.has_method("set_c4_device"):
		combat_sandbox.call("set_c4_device", c4_device)
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
	start_menu.connect("return_to_maps_pressed", _return_to_map_selection)
	start_menu.connect("map_selected", _on_map_selected)
	start_menu.connect("team_selected", _on_team_selected)
	start_menu.connect("settings_changed", _on_settings_changed)
	combat_hud.connect("purchase_requested", _purchase_item)
	combat_hud.connect("ready_requested", _on_player_ready)
	combat_hud.connect("help_visibility_changed", _on_help_visibility_changed)
	combat_hud.connect("buy_closed", func() -> void: _set_buy_menu(false))
	_apply_selected_map()
	_open_menu(true)
	_update_ui(true)

func _on_settings_changed(snapshot: Dictionary) -> void:
	UserSettings.apply_snapshot(snapshot)
	if combat_hud.has_method("apply_settings"):
		combat_hud.call("apply_settings", UserSettings.get_snapshot())

func _on_team_selected(team: String) -> void:
	if game_started or _starting:
		return
	selected_start_team = team if team in ["T", "CT"] else "T"
	start_menu.call("select_team", selected_start_team)
	GameState.player_team = selected_start_team
	if is_instance_valid(c4_device):
		c4_device.call("set_carried", "T", player.get_instance_id() if GameState.player_team == "T" else int(c4_device.get("carrier_id")))
	_update_ui(true)

func _isolate_environment_resource() -> void:
	if world_environment.environment != null:
		world_environment.environment = world_environment.environment.duplicate(true) as Environment

func _sync_equipment_view(kind: String) -> void:
	if kind == "firearm":
		var state: Dictionary = weapon_system.call("get_runtime_snapshot")
		weapon_view_model.call("set_weapon_identity", String(state.get("weapon_id", "rifle")))
		weapon_view_model.call("set_weapon_slot", int(state.get("weapon_slot", 1)))
		weapon_system.call("refresh_equipped_hud")
	else:
		weapon_system.call("cancel_reload")
		weapon_view_model.call("set_equipment", kind)

func _process(delta: float) -> void:
	if game_started and not menu_open:
		weapon_view_model.visible = (
			not bool(player.get("is_dead"))
			and not bool(weapon_system.call("get_runtime_snapshot").get("scoped", false))
		)
	else:
		weapon_view_model.hide()
	if is_instance_valid(spectator) and bool(spectator.get("active")) and not menu_open:
		spectator.call("tick")
	if _training_active() and not menu_open:
		_tick_training(delta)
	_update_objective_interaction(delta)
	_check_team_elimination()
	if String(tactical_equipment.get("equipped")) == "c4" and not _player_has_c4():
		tactical_equipment.call("select_knife")
	if weapon_view_model.has_method("update_motion") and player.has_method("get_accuracy_state"):
		var view_motion := player.call("get_accuracy_state") as Dictionary
		weapon_view_model.call(
			"update_motion",
			float(view_motion.get("speed", 0.0)),
			not bool(view_motion.get("airborne", false)),
			bool(view_motion.get("crouching", false))
		)
	var combat_enabled := _can_accept_combat_input() and not RoundManager.is_objective_interacting()
	weapon_view_model.call("set_objective_action", RoundManager.interaction_type if RoundManager.is_objective_interacting() and RoundManager.interaction_owner == "player" else "")
	if not combat_enabled:
		tactical_equipment.call("cancel_use", false)
		if not RoundManager.is_objective_interacting():
			weapon_view_model.call("cancel_actions", not bool(player.get("is_dead")) and String(tactical_equipment.get("equipped")) == "firearm")
	weapon_view_model.call("set_reload_paused", not combat_enabled)
	tactical_equipment.call("tick", delta)
	if game_started and not menu_open and player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", not bool(player.get("is_dead")) and not _help_is_open())
		if player.has_method("set_movement_enabled"):
			player.call("set_movement_enabled", combat_enabled)
	if combat_enabled:
		var fire_pressed: bool = Input.is_action_just_pressed("fire_primary")
		var fire_held: bool = Input.is_action_pressed("fire_primary")
		if String(tactical_equipment.get("equipped")) == "firearm" and weapon_system.has_method("tick"):
			if Input.is_action_just_pressed("fire_secondary"):
				weapon_system.call("toggle_scope", player)
			weapon_system.call("tick", delta, fire_pressed, fire_held, player)
		elif Input.is_action_just_pressed("fire_secondary"):
			tactical_equipment.call("use_secondary", player)
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
	if _starting:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("fullscreen_toggle"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		if (not menu_open and bool(combat_hud.call("dismiss_help"))) or (
			menu_open and bool(start_menu.call("dismiss_overlay"))
		):
			get_viewport().set_input_as_handled()
			return
		if game_started:
			if _buy_menu_open:
				_set_buy_menu(false)
			elif menu_open:
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		if game_started and not menu_open:
			combat_hud.call("toggle_player_help")
		else:
			start_menu.call("toggle_player_help")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		if combat_hud.has_method("toggle_training_telemetry"):
			combat_hud.call("toggle_training_telemetry")
		get_viewport().set_input_as_handled()
		return
	if game_started and not menu_open and bool(player.get("is_dead")):
		if _help_is_open():
			get_viewport().set_input_as_handled()
			return
		var direction := 0
		if event is InputEventMouseButton and event.pressed:
			if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_DOWN]:
				direction = 1
			elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP]:
				direction = -1
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE:
				spectator.call("toggle_mode")
			elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
				spectator.call("select_index", event.keycode - KEY_1)
			elif event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
				direction = -1 if event.keycode == KEY_BRACKETLEFT else 1
		if direction != 0:
			spectator.call("cycle", direction)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F5, KEY_F6, KEY_F7] and _training_active() and not menu_open:
		if event.keycode == KEY_F5:
			_reset_training()
		elif event.keycode == KEY_F6:
			_training_supply(true)
		elif event.keycode == KEY_F7:
			_leave_training()
		get_viewport().set_input_as_handled()
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_F2
		and _training_active()
		and _can_accept_weapon_management()
	):
		var snapshot: Dictionary = weapon_system.call("get_runtime_snapshot")
		var next := (
			(WeaponCatalog.PRIMARY.find(String(snapshot.get("weapon_id", "rifle"))) + 1)
			% WeaponCatalog.PRIMARY.size()
		)
		weapon_system.call("purchase_weapon", WeaponCatalog.PRIMARY[next])
		tactical_equipment.call("select_firearm")
		_sync_equipment_view("firearm")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("buy_menu"):
		if game_started and not menu_open and RoundManager.can_buy():
			_set_buy_menu(not _buy_menu_open)
		get_viewport().set_input_as_handled()
		return

	if _buy_menu_open and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]:
			var buy_items := {
				KEY_1: "rifle",
				KEY_2: "pistol",
				KEY_3: "armor",
				KEY_4: "armor_helmet",
				KEY_5: "defuse_kit",
				KEY_6: "he_grenade",
				KEY_7: "flash_grenade",
				KEY_8: "smoke_grenade",
				KEY_9: "sniper",
				KEY_0: "smg"
			}
			_purchase_item(String(buy_items[event.keycode]))
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("interact"):
		if _can_accept_combat_input():
			if not _try_begin_objective_interaction():
				_try_pickup_weapon()
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
		elif _can_accept_combat_input() and _player_has_c4():
			RoundManager.bomb_carried = false
			c4_device.call("drop_at", player.global_position + -player.global_transform.basis.z * 0.8 - Vector3.UP * 0.82)
			tactical_equipment.call("select_knife")
			_update_ui(true)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("reload_weapon"):
		if _can_accept_weapon_management() and String(tactical_equipment.get("equipped")) == "firearm" and weapon_system.has_method("request_reload"):
			weapon_system.call("request_reload")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_1"):
		if _can_accept_weapon_management() and weapon_system.has_method("switch_to_slot"):
			weapon_system.call("switch_to_slot", 0)
			var selected: Dictionary = weapon_system.call("get_runtime_snapshot")
			if int(selected.get("weapon_slot", -1)) == 0 and bool(selected.get("owned", false)):
				tactical_equipment.call("select_firearm")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("weapon_slot_2"):
		if _can_accept_weapon_management() and weapon_system.has_method("switch_to_slot"):
			weapon_system.call("switch_to_slot", 1)
			var selected: Dictionary = weapon_system.call("get_runtime_snapshot")
			if int(selected.get("weapon_slot", -1)) == 1 and bool(selected.get("owned", false)):
				tactical_equipment.call("select_firearm")
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

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_5:
		if _can_accept_weapon_management() and _player_has_c4():
			tactical_equipment.call("select_c4")
		get_viewport().set_input_as_handled()
		return

func _apply_selected_map() -> void:
	var option: Dictionary = level_options[selected_level_index]
	start_menu.call("set_map_details", option, game_started)
	GameState.set_level(String(option["id"]), String(option["name"]))
	_update_ui(true)

func _on_map_selected(index: int) -> void:
	if game_started or _starting:
		return
	selected_level_index = clampi(index, 0, level_options.size() - 1)
	_apply_selected_map()

func _return_to_map_selection() -> void:
	if not menu_open or not game_started or _starting:
		return
	spectator.call("stop")
	_clear_round_drops()
	game_started = false
	GameState.reset_runtime_state()
	GameState.set_game_started(false)
	_open_menu(true)

func _on_start_pressed() -> void:
	if _starting:
		return
	_starting = true
	_start_failure = "map"
	var began := Time.get_ticks_usec()
	start_menu.call("set_loading", true)
	# Give the loading state a complete frame before synchronous engine work.
	await get_tree().process_frame
	await get_tree().process_frame
	var presented := Time.get_ticks_usec()
	await _start_selected_map()
	last_start_timings = {
		"id": String(level_options[selected_level_index].id),
		"success": game_started and not _level_load_failed,
		"menu_ms": (presented - began) / 1000.0,
		"total_ms": (Time.get_ticks_usec() - began) / 1000.0,
		"level": level.last_load_timings.duplicate(true),
		"preparation": _preparation_timings.duplicate(true),
	}
	_starting = false
	start_menu.call("set_loading", false)
	if not game_started:
		start_menu.call("show_loading_error", _start_failure)

func _on_loading_progress(stage: String, completed: int, total: int) -> void:
	if _starting:
		start_menu.call("set_loading_stage", stage, completed, total)

func _start_selected_map() -> void:
	spectator.call("stop")
	var option: Dictionary = level_options[selected_level_index]
	_level_loading = true
	_level_load_failed = false
	game_started = false
	GameState.set_game_started(false)
	RoundManager.set_warmup()
	_preparation_timings.clear()
	_set_world_active(false)
	combat_hud.call("show_training_panel", false)
	selected_start_team = "T" if (start_menu.get("team_select") as OptionButton).selected == 0 else "CT"
	if String(option["id"]) == "training-range":
		GameState.reset_runtime_state()
		GameState.player_team = "T"
	else:
		GameState.start_match(selected_start_team, 5 if LocalClassicMaps.is_classic(String(option["id"])) else 3)
	_completed_match_record_path = ""
	if combat_sandbox.has_method("clear_saved_round_state"):
		combat_sandbox.call("clear_saved_round_state", true)
	_radar_spotted_until.clear()
	_radar_death_markers.clear()
	if combat_hud.has_method("reset_transients"):
		combat_hud.call("reset_transients")
	if is_instance_valid(training_telemetry):
		training_telemetry.call("begin_round", 1)
	_clear_round_drops()
	if not await level.call("load_level_async", option["id"]):
		_level_load_failed = true
		_level_loading = false
	while _level_loading:
		await get_tree().physics_frame
	if _level_load_failed:
		game_started = false
		GameState.reset_runtime_state()
		GameState.set_game_started(false)
		level_start_failed.emit(String(option["id"]))
		_open_menu(true)
		return
	if player.has_method("reset_to_spawn"):
		player.call("reset_to_spawn")
	game_started = true
	_set_world_active(true)
	GameState.set_game_started(true)
	if weapon_system.has_method("configure_default_loadout"):
		weapon_system.call("configure_default_loadout", true, GameState.is_competitive_level())
	tactical_equipment.call("reset_loadout")
	if weapon_view_model.has_method("set_weapon_slot"):
		var equipped_slot := int((weapon_system.call("get_runtime_snapshot") as Dictionary).get("weapon_slot", 0))
		weapon_view_model.call("set_weapon_slot", equipped_slot, false)
	RoundManager.freeze_duration = 60.0 if GameState.is_competitive_level() else 5.0
	RoundManager.allow_player_ready = GameState.is_competitive_level()
	RoundManager.start_round()
	GameState.begin_match_round(RoundManager.round_serial)
	c4_device.call("set_carried", "T", player.get_instance_id() if GameState.player_team == "T" else int(c4_device.get("carrier_id")))
	_resume_game()
	if _training_active():
		_reset_training()
	if GameState.is_competitive_level():
		_set_buy_menu(true)

func _set_buy_menu(opened: bool) -> void:
	_buy_menu_open = opened and game_started and not menu_open and RoundManager.can_buy()
	if _buy_menu_open:
		combat_hud.call("dismiss_help")
	combat_hud.call("set_buy_menu_visible", _buy_menu_open)
	player.call("set_mouse_capture_enabled", not _buy_menu_open and not menu_open)
	_update_buy_page()

func _on_player_ready() -> void:
	if not game_started or menu_open or bool(player.get("is_dead")):
		return
	if RoundManager.player_ready():
		_set_buy_menu(false)
		_update_ui(true)

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
	weapon_view_model.visible = game_started and not bool(player.get("is_dead"))
	if bool(spectator.get("active")):
		spectator.call("tick")
	_update_ui(true)

func _open_menu(initial_open: bool) -> void:
	weapon_system.call("cancel_scope")
	_set_buy_menu(false)
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
	if initial_open:
		_set_world_active(false)
	_update_ui(true)

func _set_world_active(active: bool) -> void:
	if not active:
		c4_device.call("clear_explosion")
	level.visible = active
	combat_sandbox.visible = active
	c4_device.visible = active
	player.set_physics_process(active)

func _toggle_fullscreen() -> void:
	var current_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_ui(true)

func _on_level_loaded(level_data: Dictionary) -> void:
	var began := Time.get_ticks_usec()
	var timings := {"physics_settle_ms": 0.0, "layout_ms": 0.0}
	_level_load_failed = false
	_apply_level_environment(level_data)
	preload("res://scripts/level/SourceModulateMaterials.gd").update_environment(
		level, world_environment.environment
	)
	_level_load_serial += 1
	var serial := _level_load_serial
	var level_load_count: int = level.load_count
	timings["environment_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	var phase := Time.get_ticks_usec()
	if LocalClassicMaps.is_classic(String(level_data.get("id", ""))):
		_level_loading = true
		for _frame in range(2):
			await get_tree().physics_frame
		if serial != _level_load_serial or level_load_count != level.load_count:
			return
		timings["physics_settle_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
		phase = Time.get_ticks_usec()
		_on_loading_progress("rules", 0, 0)
		var verified: Dictionary = await get_node("/root/CollisionVerifier").load_layout(level_data)
		if serial != _level_load_serial or level_load_count != level.load_count:
			return
		var layout: Dictionary = verified.get("layout", {})
		verified.erase("layout")
		timings["layout_verification"] = verified
		if layout.is_empty():
			_start_failure = "layout"
			_level_load_failed = true
			_level_loading = false
			push_error("经典地图缺少有效的本机冻结路网 JSON，或碰撞/关卡资源已变更。请显式重建并审计本机基线。")
			return
		level_data.merge(layout, true)
		var spawns: Array = (layout.get("matchSpawns", {}) as Dictionary).get(GameState.player_team, [])
		if not spawns.is_empty():
			var spawn: Array = spawns[spawns.size() / 2]
			GameState.player_spawn = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
			var yaw_defaults := {"T": 77.0, "CT": -100.0}
			var spawn_yaws: Dictionary = level_data.get("spawnYawDegrees", yaw_defaults)
			GameState.player_spawn_yaw_radians = deg_to_rad(float(spawn_yaws.get(GameState.player_team, 0.0)))
		timings["layout_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	phase = Time.get_ticks_usec()
	_on_loading_progress("team", 0, 0)
	if combat_sandbox.has_method("load_for_level"):
		await combat_sandbox.call("load_for_level", level_data, _starting)
	if serial != _level_load_serial or level_load_count != level.load_count:
		return
	timings["actors_ms"] = (Time.get_ticks_usec() - phase) / 1000.0
	timings["actor_phases"] = combat_sandbox.last_load_timings.duplicate(true)
	timings["prepare_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	_preparation_timings = timings
	_level_loading = false
	level_prepared.emit(level_data)

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
	if is_instance_valid(training_telemetry):
		training_telemetry.call("record_shot", result)
	for damage in result.get("damage_events", [result.get("damage_result", {})]):
		GameState.record_scoreboard_damage("你", GameState.player_team, damage)
	if weapon_view_model.has_method("play_shot"):
		weapon_view_model.call("play_shot")
	if hit_feedback_layer.has_method("show_shot_feedback"):
		hit_feedback_layer.call("show_shot_feedback", result)
	if shot_debug_line.has_method("show_shot"):
		shot_debug_line.call("show_shot", result)
	if combat_audio_feedback.has_method("play_shot"):
		combat_audio_feedback.call("play_shot", result, player.global_position)
	combat_sandbox.call("notify_ai_sound", player.global_position, 52.0, GameState.player_team)
	for damage_result in result.get("damage_events", [result.get("damage_result", {})]):
		if bool(damage_result.get("killed", false)) and combat_hud.has_method("add_kill_feed"):
			var death_position: Vector3 = damage_result.get(
				"position", result.get("position", Vector3.ZERO)
			)
			(
				_radar_death_markers
				. append(
					{
						"team":
						String(
							damage_result.get(
								"target_team", "CT" if GameState.player_team == "T" else "T"
							)
						),
						"alive": false,
						"spotted": true,
						"x": death_position.x,
						"y": death_position.y,
						"z": death_position.z,
						"expires": Time.get_ticks_msec() + 5000,
					}
				)
			)

			_check_team_elimination()
			if (
				not _training_active()
				and not GameState.is_competitive_level()
				and GameState.enemy_alive == 0
			):
				RoundManager.end_round(GameState.player_team, "ELIMINATION")

func _on_melee_resolved(result: Dictionary) -> void:
	GameState.record_scoreboard_damage("你", GameState.player_team, result)
	hit_feedback_layer.call("show_shot_feedback", {"hit": true, "damage_result": result})

	_check_team_elimination()

func _on_targets_spawned(count: int) -> void:
	GameState.set_training_target_count(count)

func _on_combatants_spawned(friendly_count: int, enemy_count: int) -> void:
	GameState.set_combatant_counts(friendly_count, enemy_count)

func _on_player_died() -> void:
	if _training_active():
		_reset_training.call_deferred()
		return
	if not GameState.is_competitive_level():
		RoundManager.end_round("CT" if GameState.player_team == "T" else "T", "ELIMINATION")
		return
	if _player_has_c4():
		c4_device.call("drop_at", player.global_position - Vector3.UP * 0.82)
		RoundManager.bomb_carried = false
		combat_hud.call("show_radio_report", "队伍", "携弹队员阵亡，C4 已掉落")
	weapon_system.call("cancel_reload")
	tactical_equipment.call("cancel_use")
	weapon_view_model.hide()
	_set_buy_menu(false)
	spectator.call("begin", player, GameState.player_team)
	_check_team_elimination()

func _check_team_elimination() -> void:
	if not game_started or not GameState.is_competitive_level() or RoundManager.state not in [RoundManager.RoundState.LIVE, RoundManager.RoundState.BOMB_PLANTED]:
		return
	var counts := {"T": 0, "CT": 0}
	if not bool(player.get("is_dead")):
		counts[GameState.player_team] += 1
	for actor in combat_sandbox.get_children():
		if actor is CharacterBody3D and not bool(actor.get("is_dead")):
			var team := String(actor.get("team"))
			if team not in ["T", "CT"]:
				team = "CT" if GameState.player_team == "T" else "T"
			counts[team] += 1
	GameState.friendly_alive = int(counts[GameState.player_team])
	GameState.enemy_alive = int(counts["CT" if GameState.player_team == "T" else "T"])
	if int(counts["CT"]) == 0:
		RoundManager.end_round("T", "ELIMINATION")
	elif int(counts["T"]) == 0 and RoundManager.state != RoundManager.RoundState.BOMB_PLANTED:
		RoundManager.end_round("CT", "ELIMINATION")

func _on_round_phase_changed(state_name: String) -> void:
	if not RoundManager.can_buy():
		_set_buy_menu(false)
	if combat_hud.has_method("show_radio_report"):
		if state_name == "Freeze":
			combat_hud.call(
				"show_radio_report",
				"对局规则",
				"本回合友伤已开启" if CombatEvents.friendly_fire else "本回合友伤已关闭"
			)
		elif state_name == "Bomb Planted":
			combat_hud.call("show_radio_report", "指挥", "C4 已安装，立即回防或守包")
		elif state_name == "Round End":
			combat_hud.call("show_radio_report", "指挥", "回合结束，准备下一局")
	_update_ui(true)


func _on_round_ended(winner: String, reason: String) -> void:
	var transition := GameState.complete_round(winner, reason, RoundManager.round_serial)
	if bool(transition.get("accepted", false)) and bool(transition.get("match_complete", false)):
		call_deferred("_persist_completed_match")
	_update_ui(true)

func _persist_completed_match() -> void:
	if GameState.match_phase == "complete" and _completed_match_record_path.is_empty():
		_completed_match_record_path = GameState.export_match_record()

func _on_round_restart_requested() -> void:
	var transition := GameState.consume_match_transition()
	if transition.is_empty():
		return
	spectator.call("stop")
	if bool(transition.get("match_complete", false)):
		var record_path := _completed_match_record_path
		if record_path.is_empty():
			_completed_match_record_path = GameState.export_match_record()
			record_path = _completed_match_record_path
		RoundManager.set_warmup()
		game_started = false
		GameState.set_game_started(false)
		_open_menu(true)
		if start_menu.has_method("set_match_summary"):
			start_menu.call("set_match_summary", GameState.get_match_snapshot(), record_path)
		return
	var player_survived := not bool(player.get("is_dead"))
	_clear_round_drops()
	var hard_reset := bool(transition.get("reset_economy", false))
	if hard_reset:
		GameState.reset_competitive_loadout()
		_radar_spotted_until.clear()
		_radar_death_markers.clear()
		if combat_hud.has_method("reset_transients"):
			combat_hud.call("reset_transients")
		if combat_sandbox.has_method("clear_saved_round_state"):
			combat_sandbox.call("clear_saved_round_state", false)
	GameState.prepare_next_round()
	if is_instance_valid(training_telemetry):
		var completed_round := training_telemetry.call("get_snapshot") as Dictionary
		training_telemetry.call("begin_round", int(completed_round.get("round_number", 1)) + 1)
	var option: Dictionary = level_options[selected_level_index]
	level.call("load_level", option["id"])
	while _level_loading:
		await get_tree().physics_frame
	if _level_load_failed:
		game_started = false
		GameState.set_game_started(false)
		RoundManager.set_warmup()
		_open_menu(true)
		return
	player.call("reset_to_spawn")
	weapon_view_model.show()
	if hard_reset or not player_survived:
		if not player_survived and not hard_reset:
			GameState.clear_eliminated_player_equipment()
		weapon_system.call("configure_default_loadout", true, GameState.is_competitive_level())
		tactical_equipment.call("reset_loadout")
		if weapon_view_model.has_method("set_weapon_slot"):
			var reset_slot := int((weapon_system.call("get_runtime_snapshot") as Dictionary).get("weapon_slot", 0))
			weapon_view_model.call("set_weapon_slot", reset_slot, false)
	RoundManager.start_round()
	GameState.begin_match_round(RoundManager.round_serial)
	c4_device.call("set_carried", "T", player.get_instance_id() if GameState.player_team == "T" else int(c4_device.get("carrier_id")))
	if GameState.is_competitive_level():
		_set_buy_menu(true)

func _purchase_item(item_id: String) -> void:
	var offer := _purchase_offer(item_id)
	var result: Dictionary = (
		GameState.purchase(item_id) if bool(offer.get("success", false)) else offer
	)
	if (
		bool(result.get("success", false))
		and (item_id in WeaponCatalog.PRIMARY or item_id == "pistol")
	):
		var slot := 1 if item_id == "pistol" else 0
		var replaced: Dictionary = weapon_system.call("get_slot_record", slot)
		weapon_system.call("purchase_weapon", item_id)
		if not replaced.is_empty():
			_spawn_replaced_weapon(replaced)
		tactical_equipment.call("select_firearm")
	if (
		bool(result.get("success", false))
		and item_id in ["he_grenade", "flash_grenade", "smoke_grenade", "fire_grenade"]
	):
		tactical_equipment.call("purchase_grenade", item_id)
	combat_hud.call("show_purchase_result", "购买成功" if bool(result.get("success", false)) else String(result.get("reason", "购买失败")))
	_update_buy_page()

func _purchase_offer(item_id: String) -> Dictionary:
	var denied := ""
	if menu_open or not game_started:
		denied = "比赛尚未开始"
	elif bool(player.get("is_dead")):
		denied = "阵亡后不能购买"
	elif player.global_position.distance_to(GameState.player_spawn) > 8.0:
		denied = "请返回出生点购买区"
	if not denied.is_empty():
		return {"success": false, "reason": denied}
	var slot_index := 0 if item_id in WeaponCatalog.PRIMARY else (1 if item_id == "pistol" else -1)
	if slot_index >= 0 and bool(weapon_system.call("is_slot_owned", slot_index)):
		var held: Dictionary = weapon_system.call("get_slot_record", slot_index)
		if held.get("weapon_id") == item_id:
			return {"success": false, "reason": "已持有"}
	if item_id in ["he_grenade", "flash_grenade", "smoke_grenade", "fire_grenade"]:
		var inventory: Dictionary = tactical_equipment.get("grenade_counts")
		var total := 0
		for count in inventory.values():
			total += int(count)
		if total >= 4:
			return {"success": false, "reason": "最多携带四枚投掷物"}
		if int(inventory.get(item_id, 0)) >= (2 if item_id == "flash_grenade" else 1):
			return {"success": false, "reason": "已达携带上限"}
	return GameState.get_purchase_offer(item_id)

func _update_buy_page() -> void:
	if not is_instance_valid(combat_hud):
		return
	var offers := {}
	for item in WeaponCatalog.PRICES:
		offers[item] = _purchase_offer(item)
	combat_hud.call("update_buy_page", {"money": GameState.player_money, "seconds": RoundManager.time_remaining, "offers": offers, "team": GameState.player_team, "ready_allowed": RoundManager.allow_player_ready and RoundManager.can_buy()})

func _try_plant_c4() -> bool:
	return _try_begin_objective_interaction()

func _try_pickup_weapon() -> bool:
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		if pickup is Node3D and pickup.has_method("can_pick_up") and bool(pickup.call("can_pick_up", player.global_position)):
			var record: Dictionary = pickup.get("weapon_record")
			var replaced: Dictionary = weapon_system.call(
				"get_slot_record", int(record.get("slot_index", -1))
			)
			if bool(weapon_system.call("pickup_weapon", pickup.get("weapon_record"))):
				if not replaced.is_empty():
					_spawn_replaced_weapon(replaced)
				tactical_equipment.call("select_firearm")
				pickup.queue_free()
				return true
	return false

func _spawn_replaced_weapon(record: Dictionary) -> void:
	var pickup := WorldWeaponPickup.new()
	add_child(pickup)
	pickup.configure(record, player.global_position - Vector3.UP * 0.75)

func _clear_round_drops() -> void:
	for group_name in ["weapon_pickups", "grenade_projectiles", "smoke_volumes"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()

func _try_begin_objective_interaction() -> bool:
	if _training_active():
		return false
	if c4_device.call("can_pick_up", player.global_position, GameState.player_team):
		if bool(c4_device.call("pick_up", GameState.player_team, player.get_instance_id())):
			RoundManager.bomb_carried = true
			_update_ui(true)
			return true
	if GameState.player_team == "CT" and RoundManager.state == RoundManager.RoundState.BOMB_PLANTED:
		if bool(c4_device.call("is_player_in_interaction_range", player.global_position)):
			return RoundManager.begin_defuse(GameState.player_team, GameState.player_defuse_kit)
		return false
	if not _player_has_c4():
		return false
	var site := _get_current_plant_site()
	return RoundManager.begin_plant(String(site.get("label", "")), GameState.player_team) if not site.is_empty() else false

func _get_current_plant_site() -> Dictionary:
	var radar_snapshot := _build_radar_snapshot()
	var player_position := Vector2(player.global_position.x, player.global_position.z)
	for target_variant in radar_snapshot.get("targets", []):
		var target := target_variant as Dictionary
		var target_position := Vector2(float(target.get("x", 0.0)), float(target.get("z", 0.0)))
		if target.has("y") and absf(player.global_position.y - float(target["y"])) > 1.5:
			continue
		var plant_radius := maxf(3.0, minf(float(target.get("sx", 6.0)), float(target.get("sz", 6.0))) * 0.5)
		if player_position.distance_to(target_position) <= plant_radius:
			return target
	return {}

func _update_objective_interaction(delta: float) -> void:
	if not game_started or menu_open or bool(player.get("is_dead")):
		return
	if RoundManager.is_objective_interacting() and String(RoundManager.interaction_owner) != "player":
		return
	var holding_c4_primary := String(tactical_equipment.get("equipped")) == "c4" and Input.is_action_pressed("fire_primary")
	if not Input.is_action_pressed("interact") and not holding_c4_primary:
		RoundManager.cancel_objective_interaction()
		return
	if not RoundManager.is_objective_interacting():
		_try_begin_objective_interaction()
	if not RoundManager.is_objective_interacting():
		return
	var interaction_type := RoundManager.interaction_type
	weapon_system.call("cancel_reload")
	if String(tactical_equipment.get("equipped")) == "firearm":
		weapon_system.call("refresh_equipped_hud")
	var interaction_site := RoundManager.interaction_site
	var still_valid := false
	if interaction_type == "plant":
		var site := _get_current_plant_site()
		still_valid = String(site.get("label", "")) == interaction_site and _player_has_c4()
	elif interaction_type == "defuse":
		still_valid = bool(c4_device.call("is_player_in_interaction_range", player.global_position))
	var completed := RoundManager.tick_objective_interaction(delta, still_valid)
	if completed and interaction_type == "plant":
		c4_device.call("plant_at", player.global_position - Vector3(0.0, 0.82, 0.0), interaction_site)
		GameState.reward_objective_action("plant")
	elif completed and interaction_type == "defuse":
		c4_device.call("set_carried", "CT")

func _on_bomb_exploded(_site_label: String) -> void:
	if not bool(c4_device.call("detonate")):
		return
	_apply_c4_damage(player)
	for actor in combat_sandbox.get_children():
		if actor is CharacterBody3D:
			_apply_c4_damage(actor)


func _apply_c4_damage(target: CharacterBody3D) -> void:
	if bool(target.get("is_dead")):
		return
	var damage := int(
		c4_device.call(
			"calculate_explosion_damage",
			target.global_position,
			get_world_3d().direct_space_state,
			[target.get_rid()]
		)
	)
	if damage > 0:
		CombatEvents.apply_damage(
			target,
			"apply_hitscan_damage",
			[damage, target.global_position, 0.65, false],
			CombatEvents.actor_source(null, "c4", "objective")
		)


func _on_player_footstep(world_position: Vector3, surface: String, quiet: bool) -> void:
	if combat_audio_feedback.has_method("play_footstep"):
		combat_audio_feedback.call("play_footstep", world_position, surface, quiet)
	combat_sandbox.call("notify_ai_sound", world_position, 14.0 if quiet else 34.0, GameState.player_team)

func _on_player_landed(world_position: Vector3, surface: String, strength: float) -> void:
	if weapon_view_model.has_method("play_landing"):
		weapon_view_model.call("play_landing", strength)
	if combat_audio_feedback.has_method("play_landing"):
		combat_audio_feedback.call("play_landing", world_position, surface, strength)
	combat_sandbox.call("notify_ai_sound", world_position, lerpf(18.0, 38.0, strength), GameState.player_team)

func _on_ai_shot(result: Dictionary, world_position: Vector3) -> void:
	if combat_audio_feedback.has_method("play_shot"):
		combat_audio_feedback.call("play_shot", result, world_position)


func _on_area_damage(result: Dictionary, _shooter_name: String, _shooter_team: String) -> void:
	if bool(result.get("killed", false)):
		_check_team_elimination()

func _on_ai_footstep(world_position: Vector3, surface: String, quiet: bool) -> void:
	if combat_audio_feedback.has_method("play_footstep"):
		combat_audio_feedback.call("play_footstep", world_position, surface, quiet)

func _on_radio_report(caller: String, message: String) -> void:
	if combat_hud.has_method("show_radio_report"):
		combat_hud.call("show_radio_report", caller, message)

func _on_weapon_switched(_weapon_name: String, slot_index: int) -> void:
	var identity: Dictionary = weapon_system.call("get_runtime_snapshot")
	weapon_view_model.call("set_weapon_identity", String(identity.get("weapon_id", "rifle")))
	tactical_equipment.call("select_firearm")
	if weapon_view_model.has_method("set_weapon_slot"):
		weapon_view_model.call("set_weapon_slot", slot_index)
	if combat_audio_feedback.has_method("play_weapon_switched"):
		combat_audio_feedback.call("play_weapon_switched")

func _on_reload_started() -> void:
	if weapon_view_model.has_method("play_reload_started"):
		weapon_view_model.call("play_reload_started")
	if combat_audio_feedback.has_method("play_reload_started"):
		combat_audio_feedback.call("play_reload_started")

func _on_reload_finished() -> void:
	if weapon_view_model.has_method("play_reload_finished"):
		weapon_view_model.call("play_reload_finished")
	if combat_audio_feedback.has_method("play_reload_finished"):
		combat_audio_feedback.call("play_reload_finished")

func _on_hud_state_changed(snapshot: Dictionary) -> void:
	combat_hud.call("update_display", _build_hud_snapshot(snapshot))

func _can_accept_combat_input() -> bool:
	return (
		game_started
		and not menu_open
		and not _buy_menu_open
		and not _help_is_open()
		and RoundManager.can_player_move()
		and not bool(player.get("is_dead"))
	)


func _help_is_open() -> bool:
	return is_instance_valid(combat_hud) and bool(combat_hud.call("is_help_open"))

func _on_help_visibility_changed(opened: bool) -> void:
	player.call(
		"set_mouse_capture_enabled",
		not opened and game_started and not menu_open and not _buy_menu_open
	)
	player.call("set_controls_enabled", not opened and not bool(player.get("is_dead")))

func _can_accept_weapon_management() -> bool:
	return game_started \
		and not menu_open \
		and not _help_is_open() \
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
	_update_buy_page()
	if is_instance_valid(training_telemetry) and combat_hud.has_method("update_training_telemetry"):
		combat_hud.call("update_training_telemetry", training_telemetry.call("get_snapshot"))
	var snapshot: Dictionary = {}
	if player.has_method("get_debug_snapshot"):
		snapshot = player.call("get_debug_snapshot", menu_open)
	if force or status_panel.visible:
		status_panel.call("update_display", snapshot)

func _build_hud_snapshot(snapshot: Dictionary) -> Dictionary:
	var enriched := snapshot.duplicate(true)
	if bool(c4_device.call("is_explosion_presenting")):
		enriched["training_complete"] = false
	enriched["scoped"] = (
		bool(weapon_system.call("get_runtime_snapshot").get("scoped", false))
		and not bool(player.get("is_dead"))
	)
	enriched["magazine_capacity"] = weapon_system.call("get_runtime_snapshot").get(
		"magazine_capacity", 30
	)
	if is_instance_valid(training_telemetry):
		enriched["training_debrief"] = training_telemetry.call("get_snapshot")
	var bomb: Dictionary = enriched.get("bomb", {})
	bomb["bomb_carried"] = _player_has_c4()
	enriched["bomb"] = bomb
	enriched["objective_hint"] = _get_objective_hint()
	enriched["radar"] = _build_radar_snapshot()
	enriched["flash_intensity"] = float(player.call("get_flash_intensity"))
	enriched["spectator"] = spectator.call("get_snapshot")
	if bool((enriched["spectator"] as Dictionary).get("active", false)):
		enriched["flash_intensity"] = 0.0
	return enriched

func _player_has_c4() -> bool:
	return GameState.player_team == "T" and RoundManager.bomb_carried and bool(c4_device.call("is_carried_by", player))

func _get_objective_hint() -> String:
	if _training_active():
		return ""
	if not game_started or bool(player.get("is_dead")):
		return ""
	if RoundManager.is_objective_interacting():
		if String(RoundManager.interaction_owner) != "player":
			var interacting_team := "T" if RoundManager.interaction_type == "plant" else "CT"
			if interacting_team == GameState.player_team:
				return "队友正在处理 C4 · 注意掩护"
			return "敌方正在%s C4 · 立即阻止" % ("安装" if interacting_team == "T" else "拆除")
		return "持续按住 E（持 C4 可按左键）· 松开即取消"
	if RoundManager.state == RoundManager.RoundState.BOMB_PLANTED:
		if GameState.player_team == "CT":
			if bool(c4_device.call("is_player_in_interaction_range", player.global_position)):
				return "[按住 E] 拆除 C4 · %s" % ("有拆弹器：5 秒" if GameState.player_defuse_kit else "无拆弹器：10 秒")
			return "C4 已安装 · 前往雷达炸弹标记拆除"
		return "C4 已安装 · 守住爆点，阻止拆除"
	if RoundManager.state != RoundManager.RoundState.LIVE:
		return ""
	if bool(c4_device.call("can_pick_up", player.global_position, GameState.player_team)):
		return "[E] 拾取地上的 C4"
	if _player_has_c4():
		var site := _get_current_plant_site()
		if not site.is_empty():
			return "[按住 E] 在 %s 区安装 C4 · 3.2 秒" % String(site.get("label", ""))
		return "携带 C4 · [5] 查看 · 前往 A / B 爆点安装"
	if GameState.player_team == "T" and String(c4_device.get("device_state")) == "carried":
		return "队友携带 C4 · 掩护队友前往爆点"
	if GameState.player_team == "T" and String(c4_device.get("device_state")) == "dropped":
		return "C4 已掉落 · 前往雷达标记拾取"
	return ""

func _build_radar_snapshot() -> Dictionary:
	var level_data: Dictionary = level.call("get_current_level_data") if level.has_method("get_current_level_data") else {}
	var feet_height := player.global_position.y - 0.9
	var body_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null and body_shape.shape is CapsuleShape3D:
		feet_height = (
			body_shape.global_position.y
			- body_shape.shape.height * body_shape.global_basis.y.length() * 0.5
		)
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
		if objective.has("y"):
			targets[-1]["y"] = float(objective["y"])
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
		"level_id": String(level_data.get("id", "")),
		"feet_height": feet_height,
		"grounded": player.is_on_floor(),
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
	for target in get_tree().get_nodes_in_group("combat_actors"):
		if target is Node3D:
			var target_node := target as Node3D
			var actor_snapshot: Dictionary = target_node.call("get_combat_snapshot") if target_node.has_method("get_combat_snapshot") else {}
			var actor_team := String(actor_snapshot.get("team", "CT" if GameState.player_team == "T" else "T"))
			if bool(player.get("is_dead")) and actor_team != GameState.player_team:
				continue
			var target_id := target_node.get_instance_id()
			if actor_team != GameState.player_team and _is_target_legally_spotted(target_node):
				_radar_spotted_until[target_id] = Time.get_ticks_msec() + 2500
			records.append({
				"team": actor_team,
				"alive": bool(actor_snapshot.get("alive", true)),
				"spotted": actor_team == GameState.player_team or int(_radar_spotted_until.get(target_id, 0)) >= Time.get_ticks_msec(),
				"x": target_node.global_position.x,
				"y": target_node.global_position.y,
				"z": target_node.global_position.z,
				"yaw": target_node.rotation.y,
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
