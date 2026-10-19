extends Node3D

var remaining := 7.0
var radius := 3.6
var _tick_remaining := 0.0
var _source: WeakRef
var _team := ""
var _source_name := ""
var _player_source := false
var _flames: Array[MeshInstance3D] = []


func configure(
	source: CharacterBody3D, team: String, at: Vector3, attribution: Dictionary = {}
) -> void:
	_source = weakref(source) if is_instance_valid(source) else null
	_team = team
	_player_source = is_instance_valid(source) and source.is_in_group("local_player")
	_source_name = "你" if _player_source else "AI"
	if (
		not _player_source
		and is_instance_valid(source)
		and source.has_method("get_combat_snapshot")
	):
		_source_name = String(source.call("get_combat_snapshot").get("name", "AI"))
	if not attribution.is_empty():
		_player_source = bool(attribution.get("player", false))
		_source_name = String(attribution.get("name", "AI"))
	global_position = at
	add_to_group("grenade_projectiles")
	add_to_group("fire_areas")
	for index in range(13):
		var angle := float(index) * TAU / 12.0
		var distance := 0.0 if index == 0 else (1.3 if index % 2 == 0 else 2.8)
		var offset := Vector3(cos(angle), 0, sin(angle)) * distance
		if not _clear_to(global_position + offset + Vector3.UP * 0.25, null):
			continue
		var flame := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 1.0
		mesh.radial_segments = 8
		mesh.rings = 4
		flame.mesh = mesh
		flame.position = offset + Vector3.UP * 0.35
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.28, 0.035, 0.8)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.12, 0.01)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame.material_override = material
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		_flames.append(flame)


func _physics_process(delta: float) -> void:
	if RoundManager.state == RoundManager.RoundState.PAUSED_MENU:
		return
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
		return
	for index in range(_flames.size()):
		_flames[index].scale.y = 0.8 + sin(remaining * 9.0 + index * 1.7) * 0.25
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining += 0.25
	apply_damage_tick()


func apply_damage_tick() -> void:
	var candidates := get_tree().get_nodes_in_group("combat_actors")
	candidates.append_array(get_tree().get_nodes_in_group("local_player"))
	for dummy in get_tree().get_nodes_in_group("target_dummies"):
		if dummy not in candidates:
			candidates.append(dummy)
	for candidate in candidates:
		if (
			not is_instance_valid(candidate)
			or not candidate is Node3D
			or not candidate.has_method("apply_hitscan_damage")
		):
			continue
		var dead: bool = (
			candidate.get("is_dead") if candidate is CharacterBody3D else candidate.get("_is_dead")
		)
		if dead:
			continue
		var offset: Vector3 = candidate.global_position - global_position
		if Vector2(offset.x, offset.z).length() > radius or absf(offset.y) > 1.7:
			continue
		if not _clear_to(candidate.global_position + Vector3.UP * 0.18, candidate):
			continue
		var result: Dictionary
		if candidate.is_in_group("local_player"):
			result = candidate.call("apply_explosive_damage", 5, 1.0)
			result["target_name"] = "你"
			result["target_team"] = GameState.player_team
		else:
			result = candidate.call(
				"apply_hitscan_damage",
				5,
				candidate.global_position,
				1.0,
				false,
				_team,
				global_position
			)
		var source: CharacterBody3D = _source.get_ref() if _source != null else null
		if _player_source:
			GameState.register_hit(
				bool(result.get("killed", false)),
				"fire_grenade",
				String(result.get("target_team", ""))
			)
		elif (
			is_instance_valid(source)
			and bool(result.get("killed", false))
			and String(result.get("target_team", "")) != _team
		):
			var brain := source.get_node_or_null("TacticalBotBrain")
			if brain != null:
				brain.set("ai_money", mini(16000, int(brain.get("ai_money")) + 300))
		GameState.record_scoreboard_damage(_source_name, _team, result)
		GameState.area_damage_resolved.emit(result, _source_name, _team)


func _clear_to(at: Vector3, target: Object) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.25, at, 1)
	var source: CharacterBody3D = _source.get_ref() if _source != null else null
	if is_instance_valid(source):
		query.exclude = [source.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target
