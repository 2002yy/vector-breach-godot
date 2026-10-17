extends Node

const Appearance = preload("res://scripts/characters/CharacterAppearance.gd")
const ACTOR = preload("res://scenes/combat/TacticalActor.tscn")
var _out := "user://character-proof"
var _records: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--evidence-dir" in args:
		_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	for id in Appearance.NAMES:
		if not Appearance.available(id):
			print("CHARACTER_PROBE_SKIPPED: local characters are not installed")
			get_tree().quit()
			return
	await _lineup()
	if not await _gameplay():
		get_tree().quit(1)
		return
	var receipt := FileAccess.open(_out.path_join("visual-receipt.json"), FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"profiles": Appearance.NAMES, "samples": _records}, "\t"))
	print("CHARACTER_VISUAL_PROBE_OK: six actors, matching hands, equipment actions and 5v5")
	get_tree().quit()


func _frames(count: int = 8) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func _capture(label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png")) == OK)


func _lineup() -> void:
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("323b47")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 140, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	world.add_child(light)
	var floor := MeshInstance3D.new()
	floor.mesh = PlaneMesh.new()
	floor.scale = Vector3(9, 1, 5)
	world.add_child(floor)
	var camera := Camera3D.new()
	camera.fov = 44
	world.add_child(camera)
	camera.position = Vector3(0, 1.2, -5.5)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.make_current()
	var actors: Array = []
	var index := 0
	for team in ["CT", "T"]:
		for id in Appearance.PROFILES[team]:
			var actor := ACTOR.instantiate() as CharacterBody3D
			world.add_child(actor)
			actor.position = Vector3((2.5 - index) * 1.1, 0.9, 0)
			actor.call(
				"configure_from_record",
				{
					"name": Appearance.NAMES[id],
					"team": team,
					"appearance_id": id,
					"aiEnabled": false
				}
			)
			actor.set_physics_process(false)
			actors.append(actor)
			var label := Label3D.new()
			label.text = Appearance.NAMES[id]
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 40
			label.position = Vector3(actor.position.x, 2.05, 0)
			world.add_child(label)
			index += 1
	for action in [&"idle", &"run", &"crouch", &"hit", &"death"]:
		for actor in actors:
			actor.call("_set_visual_animation", action)
			var player: AnimationPlayer = actor.get("_imported_animation_player")
			player.seek(0.65 if action == &"death" else 0.25, true)
			player.pause()
		await _capture("actors-" + String(action))
	world.queue_free()
	await _frames(2)


func _gameplay() -> bool:
	var original_settings := UserSettings.get_snapshot()
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	await main.call("_on_start_pressed")
	var view: Node3D = main.get_node("Player/CameraPivot/Camera3D/WeaponViewModel")
	var hands: Node3D = view.get("hands")
	var animator: AnimationPlayer = hands.get("animator")
	for team in ["CT", "T"]:
		GameState.player_team = team
		for id in Appearance.PROFILES[team]:
			UserSettings.apply_snapshot(
				{"ct_appearance": id} if team == "CT" else {"t_appearance": id}, false
			)
			for kind in ["rifle", "knife"]:
				if kind == "rifle":
					view.call("set_weapon_slot", 0, false)
				else:
					view.call("set_equipment", kind, false)
				hands.call("reset_pose")
				await _capture(id + "-" + kind)
			var sample: Dictionary = hands.call("snapshot")
			sample["asset_root"] = Appearance.record(id).get("asset_root", "")
			sample["equipment"] = view.call("get_debug_snapshot")
			_records.append(sample)
	for kind in ["pistol", "knife", "he_grenade", "c4"]:
		if kind == "pistol":
			view.call("set_weapon_slot", 1, false)
		else:
			view.call("set_equipment", kind, false)
		for action in ["reload", "knife_heavy", "throw", "plant", "defuse"]:
			hands.call("play_action", action, 0.95)
			animator.seek(0.22, true)
			animator.pause()
			await _capture("action-" + kind + "-" + action)
	for gun in ["rifle", "pistol"]:
		view.call("set_equipment", gun, false)
		view.call("play_reload_started")
		var weapon: Node3D = view.get("rifle_model" if gun == "rifle" else "pistol_model")
		for player in weapon.find_children("*", "AnimationPlayer", true, false):
			if player.has_animation("reload"):
				player.seek(player.get_animation("reload").length * 0.45, true)
		animator.seek(animator.current_animation_length * 0.45, true)
		view.call("set_reload_paused", true)
		await _capture("native-" + gun + "-reload-midpoint")
		view.call("set_reload_paused", false)
		view.call("play_reload_finished")
		view.call("play_shot")
		await _capture("native-" + gun + "-shot")
	view.call("set_weapon_slot", 0, false)
	UserSettings.apply_snapshot(original_settings, false)
	main.call("_leave_training")
	main.get_node("StartMenu").call("_toggle_settings", true)
	await _capture("appearance-settings")
	main.get_node("StartMenu").call("_toggle_settings", false)
	main.call(
		"_on_map_selected", main.call("find_level_option_index", "dustline-depths-original-local")
	)
	await main.call("_on_start_pressed")
	var roster: Array = []
	for actor in main.get_node("CombatSandbox").get_children():
		if actor.has_method("get_combat_snapshot"):
			roster.append(actor.call("get_combat_snapshot"))
	if roster.size() != 9:
		push_error("Expected nine AI in classic 5v5, got %d" % roster.size())
		return false
	for record in roster:
		if not record.native_appearance:
			push_error("AI failed to install native appearance")
			return false
	_records.append({"5v5_roster": roster, "player_team": GameState.player_team})
	main.call("_on_player_ready")
	await _frames(30)
	await _capture("match-5v5")
	main.queue_free()
	await _frames(2)
	return true
