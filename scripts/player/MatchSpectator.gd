extends Node3D

var active := false
var first_person := false
var target: CharacterBody3D
var camera: Camera3D
var _player_camera: Camera3D
var _player: CharacterBody3D
var _team := ""
var _hidden_meshes: Array[Dictionary] = []
var _view_model: Node3D
var _view_target_id := 0
var _last_shots := 0
var _view_weapon := ""
var _view_reloading := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "SpectatorCamera"
	add_child(camera)


func _process(_delta: float) -> void:
	if is_instance_valid(_view_model):
		_view_model.call(
			"set_reload_paused", RoundManager.state == RoundManager.RoundState.PAUSED_MENU
		)


func begin(player: CharacterBody3D, team: String) -> void:
	stop()
	_player = player
	_player_camera = player.call("get_camera_node") as Camera3D
	_team = team
	active = true
	camera.fov = _player_camera.fov
	camera.global_transform = _player_camera.global_transform
	camera.make_current()
	cycle(1)


func stop() -> void:
	_restore_meshes()
	if is_instance_valid(_view_model):
		_view_model.free()
	_view_model = null
	_view_target_id = 0
	_view_weapon = ""
	_view_reloading = false
	active = false
	target = null
	if is_instance_valid(_player_camera):
		_player_camera.make_current()
	if is_instance_valid(camera):
		camera.clear_current(false)
	_player = null
	_player_camera = null


func teammates() -> Array[CharacterBody3D]:
	var alive: Array[CharacterBody3D] = []
	for candidate in get_tree().get_nodes_in_group("combat_actors"):
		if candidate is CharacterBody3D and candidate.get("team") == _team:
			if not bool(candidate.get("is_dead")):
				alive.append(candidate)
	alive.sort_custom(
		func(a: Node, b: Node) -> bool: return a.get_instance_id() < b.get_instance_id()
	)
	return alive


func cycle(direction: int) -> void:
	if not active:
		return
	_restore_meshes()
	var alive := teammates()
	if alive.is_empty():
		target = null
		return
	var index := alive.find(target)
	if index < 0:
		index = 0 if direction >= 0 else alive.size() - 1
	else:
		index = posmod(index + direction, alive.size())
	target = alive[index]
	_apply_first_person_visibility()


func toggle_mode() -> void:
	_restore_meshes()
	first_person = not first_person
	_apply_first_person_visibility()
	if is_instance_valid(_view_model):
		_view_model.visible = first_person


func tick() -> void:
	if not active:
		return
	if not is_instance_valid(target) or bool(target.get("is_dead")):
		cycle(1)
	if not is_instance_valid(target):
		if is_instance_valid(_view_model):
			_view_model.hide()
		return
	_update_view_model()
	var eye: Vector3 = target.call("get_eye_position")
	var forward := -target.global_basis.z
	var desired := eye if first_person else eye - forward * 2.8 + Vector3.UP * 0.55
	if not first_person and target.is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(eye, desired, 1)
		query.exclude = [target.get_rid()]
		if is_instance_valid(_player):
			query.exclude.append(_player.get_rid())
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			desired = (hit.position as Vector3).move_toward(eye, 0.16)
	camera.global_position = desired
	var aim := eye + forward * 8.0
	if first_person:
		var combat: Dictionary = target.call("get_combat_snapshot")
		var ai: Dictionary = combat.get("ai", {})
		if String(ai.get("state", "")) in ["ENGAGE", "ACQUIRE", "HOLD_ANGLE"]:
			aim = ai.get("last_known_position", aim) + Vector3.UP * 0.18
	if eye.distance_squared_to(aim) > 0.01:
		camera.look_at(aim, Vector3.UP)
	camera.make_current()


func get_snapshot() -> Dictionary:
	if not active:
		return {"active": false}
	var snapshot := {"active": true, "first_person": first_person, "has_target": false}
	if is_instance_valid(target) and not bool(target.get("is_dead")):
		var combat: Dictionary = target.call("get_combat_snapshot")
		var ai: Dictionary = combat.get("ai", {})
		(
			snapshot
			. merge(
				{
					"has_target": true,
					"name": combat.get("name", "队友"),
					"health": combat.get("health", 0),
					"armor": combat.get("armor", 0),
					"weapon": combat.get("weapon", ""),
					"ammo": ai.get("ammo", 0),
					"reserve": ai.get("ammo_reserve", 0),
					"c4": ai.get("bomb_carrier", false),
					"position": target.global_position,
					"yaw": target.rotation.y,
				},
				true
			)
		)
	return snapshot


func _apply_first_person_visibility() -> void:
	if not first_person or not is_instance_valid(target):
		return
	for mesh in target.find_children("*", "GeometryInstance3D", true, false):
		_hidden_meshes.append({"node": weakref(mesh), "visible": mesh.visible})
		mesh.hide()


func _update_view_model() -> void:
	if not first_person:
		return
	if not is_instance_valid(_view_model):
		_view_model = preload("res://scenes/player/WeaponViewModel.tscn").instantiate()
		camera.add_child(_view_model)
	_view_model.show()
	for entry in _hidden_meshes:
		var mesh: Node3D = entry.node.get_ref()
		if is_instance_valid(mesh):
			mesh.hide()
	var combat: Dictionary = target.call("get_combat_snapshot")
	var ai: Dictionary = combat.get("ai", {})
	var weapon := String(ai.get("weapon_id", "pistol"))
	var changed := _view_target_id != target.get_instance_id() or weapon != _view_weapon
	if changed:
		_view_model.get("hands").call(
			"set_appearance_profile", String(combat.get("appearance", ""))
		)
		_view_model.call("cancel_actions", true)
		_view_model.call("set_weapon_identity", weapon)
		if weapon == "knife":
			_view_model.call("set_equipment", "knife", false)
		else:
			_view_model.call("set_weapon_slot", int(ai.get("weapon_slot", 1)), false)
		_view_target_id = target.get_instance_id()
		_view_weapon = weapon
		_last_shots = int(ai.get("shots", 0))
		_view_reloading = false
	var reloading := String(ai.get("state", "")) == "RELOAD"
	if reloading != _view_reloading:
		_view_model.call("play_reload_started" if reloading else "play_reload_finished")
		_view_reloading = reloading
	if int(ai.get("shots", 0)) > _last_shots:
		_view_model.call("play_shot")
	_last_shots = int(ai.get("shots", 0))
	_view_model.call(
		"update_motion",
		Vector2(target.velocity.x, target.velocity.z).length(),
		target.is_on_floor(),
		bool(target.get("ai_crouching"))
	)


func _restore_meshes() -> void:
	for entry in _hidden_meshes:
		var mesh: Node3D = entry.node.get_ref()
		if is_instance_valid(mesh):
			mesh.visible = bool(entry.visible)
	_hidden_meshes.clear()


func _exit_tree() -> void:
	_restore_meshes()
