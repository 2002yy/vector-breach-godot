extends Node3D
## Synthetic flat-plane diagnostic, real Player and WeaponSystem, no parameter edits.

const SCHEMES := ["current", "legacy_16", "modern_cs"]
const CASES := [
	"run", "walk", "crouch", "release", "reverse", "jump", "crouch_jump", "awp", "awp_scoped"
]
const ACTIONS := ["move_forward", "move_backward", "walk", "crouch", "jump"]

var rate := 60
var output := ""
var stable_ticks := 0
var player: CharacterBody3D
var weapons: Node
var case_index := -1
var scheme_index := 0
var tick := 0
var rows: Array = []
var trace: Array = []
var source_lock: Dictionary = {}
var previous_foot := 0.0
var finished := false
var case_pending := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		_fail("Expected new output.json and 60|120")
		return
	output = args[0]
	rate = int(args[1])
	if rate not in [60, 120] or FileAccess.file_exists(output):
		_fail("Invalid rate or output exists")
		return
	Engine.physics_ticks_per_second = rate
	for path in [
		"tools/authoring/measure_movement_feel.gd",
		"scripts/player/PlayerController.gd",
		"scripts/player/ClassicMovementRules.gd",
		"scenes/player/Player.tscn",
		"scripts/combat/WeaponSystem.gd",
		"scripts/combat/WeaponCatalog.gd",
		"scripts/combat/WeaponProfile.gd",
		"scenes/combat/WeaponSystem.tscn",
		"data/weapons/rifle.tres",
		"data/weapons/pistol.tres",
		"project.godot"
	]:
		source_lock[path] = FileAccess.get_sha256("res://" + path)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	GameState.reset_runtime_state()
	RoundManager.set_warmup()


func _spawn() -> void:
	GameState.player_spawn = Vector3(0, 0.9, 0)
	GameState.player_spawn_yaw_radians = 0.0
	player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	weapons = load("res://scenes/combat/WeaponSystem.tscn").instantiate()
	weapons.name = "WeaponSystem"
	add_child(weapons)
	weapons.configure_default_loadout()
	player.movement_step.connect(_record)
	_next_case()


func _next_case() -> void:
	case_pending = false
	for action in ACTIONS:
		Input.action_release(action)
	if case_index >= 0:
		rows.append({"scheme": SCHEMES[scheme_index], "case": CASES[case_index], "trace": trace})
	case_index += 1
	if case_index >= CASES.size():
		case_index = 0
		scheme_index += 1
	if scheme_index >= SCHEMES.size():
		_save()
		return
	trace = []
	tick = 0
	player.reset_to_spawn()
	player.set_movement_scheme(SCHEMES[scheme_index])
	player.set_controls_enabled(true)
	player.set_mouse_capture_enabled(false)
	weapons.cancel_scope()
	var case_name: String = CASES[case_index]
	if not weapons.purchase_weapon("sniper" if case_name.begins_with("awp") else "rifle"):
		_fail("Real weapon setup failed")
		return
	if case_name == "awp_scoped":
		weapons.toggle_scope(player)
	previous_foot = _foot_y()


func _physics_process(delta: float) -> void:
	if finished or case_pending:
		return
	if player == null:
		stable_ticks = stable_ticks + 1 if absf(delta - 1.0 / rate) < 0.000000001 else 0
		if stable_ticks >= 3:
			_spawn()
		return
	if absf(delta - 1.0 / rate) > 0.000000001:
		_fail("Physics clock drift")
		return
	var name: String = CASES[case_index]
	if tick == int(rate * 0.25):
		if name in ["crouch", "crouch_jump"]:
			Input.action_press("crouch")
		if name == "walk":
			Input.action_press("walk")
		if name not in ["jump", "crouch_jump"]:
			Input.action_press("move_forward")
	if name in ["jump", "crouch_jump"]:
		if tick == int(rate * 0.5):
			Input.action_press("jump")
		if tick == int(rate * 0.5) + 1:
			Input.action_release("jump")
	if name in ["release", "reverse"] and tick == int(rate * 1.75):
		Input.action_release("move_forward")
		if name == "reverse":
			Input.action_press("move_backward")
	weapons.tick(delta, false, false, player)
	tick += 1


func _foot_y() -> float:
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	return collider.global_position.y - float(collider.shape.height) * 0.5


func _record(sample: Dictionary) -> void:
	if finished or case_pending:
		return
	if absf(float(sample.delta) - 1.0 / rate) > 0.000000001:
		_fail("Recorded physics clock drift")
		return
	var context: Dictionary = weapons.get_movement_context()
	var foot := _foot_y()
	(
		trace
		. append(
			{
				"tick": tick,
				"delta": sample.delta,
				"direction": [sample.input.direction.x, sample.input.direction.y],
				"position": [sample.position.x, sample.position.y, sample.position.z],
				"velocity": [sample.velocity.x, sample.velocity.y, sample.velocity.z],
				"foot_y": foot,
				"foot_before": previous_foot,
				"jump_requested": sample.input.jump,
				"jumped": sample.jumped,
				"grounded_before": sample.grounded_before,
				"grounded": sample.grounded_after,
				"crouching": player.is_crouching,
				"walking": sample.input.walk,
				"weapon_id": context.weapon_id,
				"scoped": context.scoped,
				"fov": player.get_camera_node().fov,
				"speed_limit": player.resolve_final_move_speed(bool(sample.input.walk)),
			}
		)
	)
	previous_foot = foot
	var name: String = CASES[case_index]
	var duration := 4.0 if name in ["release", "reverse"] else 2.5
	if tick >= int(rate * duration):
		case_pending = true
		player.set_controls_enabled(false)
		_next_case.call_deferred()


func _save() -> void:
	finished = true
	player.set_controls_enabled(false)
	weapons.cancel_scope()
	var report := {
		"schema": 1,
		"kind": "synthetic_flat_real_player_measurement",
		"physics_rate": rate,
		"input_mode": "synthetic_action_press_parent_physics",
		"engine_hash": Engine.get_version_info().hash,
		"foot_definition": "collision_shape_global_y_minus_half_current_capsule_height",
		"airtime_definition": "end_of_first_grounded_sample_minus_start_of_jump_sample",
		"fixture": {"floor_size": [200, 1, 200], "floor_top_y": 0.0},
		"source_lock": source_lock,
		"human_review": "pending",
		"formal_release_ready": false,
		"rows": rows
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot open new report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MOVEMENT_FEEL_MEASURE_OK rate=", rate, " rows=", rows.size())
	get_tree().quit(0)


func _fail(reason: String) -> void:
	finished = true
	push_error(reason)
	get_tree().quit(1)
