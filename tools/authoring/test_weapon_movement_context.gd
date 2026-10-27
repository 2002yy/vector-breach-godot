extends Node3D
## Real equipment API fixture; no synthetic scope context or parameter edits.

var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool) -> void:
	checks += 1
	assert(condition)
	if not condition:
		get_tree().quit(1)


func _run() -> void:
	GameState.reset_runtime_state()
	var player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	var weapons = load("res://scenes/combat/WeaponSystem.tscn").instantiate()
	weapons.name = "WeaponSystem"
	add_child(weapons)
	var equipment = load("res://scripts/combat/TacticalEquipment.gd").new()
	add_child(equipment)
	weapons.configure_default_loadout()
	var initial_fov: float = player.get_camera_node().fov
	for scheme in ["current", "legacy_16", "modern_cs"]:
		player.set_movement_scheme(scheme)
		for crouching in [false, true]:
			player.is_crouching = crouching
			for walking in [false, true]:
				equipment.select_firearm()
				_check(weapons.purchase_weapon("sniper"))
				_check(weapons.get_movement_context().weapon_id == "sniper")
				_check(not weapons.get_movement_context().scoped)
				var unscoped_speed: float = player.resolve_final_move_speed(walking)
				weapons.toggle_scope(player)
				_check(weapons.get_movement_context().scoped)
				_check(is_equal_approx(player.get_camera_node().fov, 28.0))
				var scoped_speed: float = player.resolve_final_move_speed(walking)
				_check(scoped_speed > 0.0 and scoped_speed <= unscoped_speed)
				if scheme == "current":
					_check(is_equal_approx(scoped_speed, unscoped_speed))
				elif not crouching:
					_check(scoped_speed < unscoped_speed)
				_check(weapons.purchase_weapon("rifle"))
				_check(not weapons.get_movement_context().scoped)
				_check(is_equal_approx(player.get_camera_node().fov, initial_fov))
				weapons.toggle_scope(player)
				_check(not weapons.get_movement_context().scoped)
				var rifle_speed: float = player.resolve_final_move_speed(walking)
				weapons.cancel_scope()
				equipment.select_knife()
				_check(GameState.current_weapon_slot == 2)
				_check(player.resolve_final_move_speed(walking) >= rifle_speed)
				equipment.select_firearm()
				_check(weapons.purchase_weapon("sniper"))
				_check(not weapons.get_movement_context().scoped)
				_check(is_equal_approx(player.resolve_final_move_speed(walking), unscoped_speed))
	weapons.cancel_scope()
	player.queue_free()
	weapons.queue_free()
	equipment.queue_free()
	print("WEAPON_MOVEMENT_CONTEXT_OK checks=", checks)
	get_tree().quit(0)
