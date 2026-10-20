extends RigidBody3D

const EquipmentVisuals = preload("res://scripts/player/EquipmentVisuals.gd")

var grenade_type: String = "he_grenade"
var thrower: CharacterBody3D
var fuse_remaining: float = 1.7
var smoke_remaining: float = 0.0
var _detonated: bool = false
var _launch_position := Vector3.ZERO
var _peak_height := -INF
var _flight_time := 0.0
var _smoke_age: float = 0.0
var _smoke_layers: Array[MeshInstance3D] = []
var _fire_attribution: Dictionary = {}

func configure(kind: String, owner_player: CharacterBody3D, origin: Vector3, velocity: Vector3) -> void:
	grenade_type = kind
	thrower = owner_player
	_fire_attribution = CombatEvents.actor_source(owner_player, kind, "explosion")
	global_position = origin
	linear_velocity = velocity
	_launch_position = origin
	_peak_height = origin.y

func _ready() -> void:
	add_to_group("grenade_projectiles")
	contact_monitor = true
	max_contacts_reported = 4
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.48
	physics_material_override.friction = 0.7
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.09
	collision.shape = sphere
	add_child(collision)
	# configure() follows add_child(); defer until the actual type is assigned.
	call_deferred("_build_visual")

func _build_visual() -> void:
	var visual: Node3D
	if grenade_type == "fire_grenade":
		visual = preload("res://scripts/player/OfficialEquipment.gd").build(
			grenade_type, GameState.player_team
		)
	if visual == null:
		visual = EquipmentVisuals.build(grenade_type)
	add_child(visual)
	for part in ["SafetyRing", "SafetyLever"]:
		var component := visual.get_node_or_null(part) as Node3D
		if component != null:
			component.hide()

func _physics_process(delta: float) -> void:
	if _detonated:
		if grenade_type == "smoke_grenade":
			_update_smoke_visual(delta)
			smoke_remaining -= delta
			if smoke_remaining <= 0.0:
				queue_free()
		return
	_flight_time += delta
	_peak_height = maxf(_peak_height, global_position.y)
	fuse_remaining -= delta
	if fuse_remaining <= 0.0:
		_detonate()

func _detonate() -> void:
	_detonated = true
	_publish_telemetry()
	if grenade_type == "he_grenade":
		_apply_he_damage()
		queue_free()
	elif grenade_type == "flash_grenade":
		_apply_flash()
		queue_free()
	elif grenade_type == "fire_grenade":
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.15,
			global_position + Vector3.DOWN * 12.0, 1)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.5:
			var zone := preload("res://scripts/combat/FireArea.gd").new()
			get_tree().current_scene.add_child(zone)
			var source: CharacterBody3D = thrower if is_instance_valid(thrower) else null
			zone.configure(
				source, String(_fire_attribution.get("team", GameState.player_team)),
				(hit.position as Vector3) + Vector3.UP * 0.04, _fire_attribution
			)
		queue_free()
	else:
		_activate_smoke()

func _publish_telemetry() -> void:
	var summary := {
		"type": grenade_type,
		"distance": _launch_position.distance_to(global_position),
		"flight_time": _flight_time,
		"peak_height": _peak_height,
		"landing_position": global_position,
	}
	for telemetry in get_tree().get_nodes_in_group("training_telemetry"):
		if telemetry.has_method("record_grenade"):
			telemetry.call("record_grenade", summary)

func _apply_he_damage() -> void:
	var source_team := String(_fire_attribution.get("team", ""))
	var targets: Array[Node] = get_tree().get_nodes_in_group("target_dummies")
	for viewer in get_tree().get_nodes_in_group("local_player"):
		if viewer not in targets:
			targets.append(viewer)
	for target in targets:
		if not target is Node3D:
			continue
		var distance := global_position.distance_to((target as Node3D).global_position)
		if distance > 7.0:
			continue
		var self_hit := target.get_instance_id() == int(_fire_attribution.get("actor_id", 0))
		var base_damage := 70.0 if self_hit else 98.0
		var damage := maxi(
			1,
			roundi(
				(
					base_damage
					* pow(1.0 - distance / 7.0, 1.35)
					* _blast_cover_scale((target as Node3D).global_position, target)
				)
			)
		)
		var result: Dictionary
		if target.is_in_group("local_player"):
			result = CombatEvents.apply_damage(
				target, "apply_explosive_damage", [damage], _fire_attribution
			)
		elif target.has_method("apply_hitscan_damage"):
			result = CombatEvents.apply_damage(
				target,
				"apply_hitscan_damage",
				[
					damage,
					(target as Node3D).global_position,
					0.5,
					false,
					source_team,
					global_position
				],
				_fire_attribution
			)
		else:
			continue
		if not bool(result.get("hit", false)):
			continue
		if bool(_fire_attribution.get("player", false)) and not self_hit:
			GameState.register_hit(
				bool(result.get("killed", false)),
				"he_grenade",
				String(result.get("target_team", ""))
			)
		elif (
			is_instance_valid(thrower)
			and not self_hit
			and bool(result.get("killed", false))
			and String(result.get("target_team", "")) != source_team
		):
			var brain := thrower.get_node_or_null("TacticalBotBrain")
			if brain != null:
				brain.set("ai_money", mini(16000, int(brain.get("ai_money")) + 300))
		GameState.area_damage_resolved.emit(
			result, String(_fire_attribution.get("name", "环境")), source_team
		)


func _blast_cover_scale(target_position: Vector3, target_collider: Variant) -> float:
	var query := PhysicsRayQueryParameters3D.create(global_position, target_position + Vector3.UP * 0.25)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider", null) == target_collider:
		return 1.0
	return 0.35

func _apply_flash() -> void:
	var viewer: Node = null
	if is_instance_valid(thrower):
		if (thrower as Node).is_in_group("local_player"):
			viewer = thrower as Node
		else:
			viewer = get_tree().get_first_node_in_group("local_player")
	if viewer == null:
		return
	var camera := viewer.call("get_camera_node") as Camera3D
	if camera == null:
		return
	var delta := global_position - camera.global_position
	if delta.length() > 18.0:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, camera.global_position)
	query.exclude = [get_rid()]
	if is_instance_valid(thrower):
		query.exclude.append(thrower.get_rid())
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	var facing := clampf((-camera.global_transform.basis.z).dot(delta.normalized()), -1.0, 1.0)
	var intensity := clampf((1.0 - delta.length() / 18.0) * lerpf(0.25, 1.0, maxf(facing, 0.0)), 0.0, 1.0)
	viewer.call("apply_flash_effect", intensity, lerpf(0.5, 3.4, intensity))

func _activate_smoke() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for child in get_children():
		if child is CollisionShape3D or child is MeshInstance3D:
			child.queue_free()
	_smoke_age = 0.0
	_smoke_layers.clear()
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.9, 0.0),
		Vector3(-1.2, 0.65, 0.25),
		Vector3(1.15, 0.72, -0.2),
		Vector3(-0.35, 1.55, -0.9),
		Vector3(0.45, 1.45, 0.95),
		Vector3(-0.9, 1.65, 0.75),
		Vector3(0.95, 1.7, -0.65),
	]
	var scales: Array[Vector3] = [
		Vector3(2.4, 1.7, 2.35),
		Vector3(1.7, 1.35, 1.75),
		Vector3(1.65, 1.45, 1.7),
		Vector3(1.55, 1.55, 1.65),
		Vector3(1.6, 1.45, 1.55),
		Vector3(1.35, 1.3, 1.4),
		Vector3(1.4, 1.35, 1.35),
	]
	for index in offsets.size():
		var puff := MeshInstance3D.new()
		puff.name = "SmokePuff%02d" % index
		var puff_mesh := SphereMesh.new()
		puff_mesh.radius = 1.0
		puff_mesh.height = 2.0
		puff_mesh.radial_segments = 18
		puff_mesh.rings = 10
		puff.mesh = puff_mesh
		puff.position = offsets[index]
		puff.scale = scales[index] * 0.08
		puff.rotation.y = float(index) * 0.73
		var puff_material := StandardMaterial3D.new()
		puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		puff_material.albedo_color = Color(0.27 + index * 0.008, 0.30 + index * 0.007, 0.285 + index * 0.006, 0.0)
		puff_material.roughness = 1.0
		puff.material_override = puff_material
		puff.set_meta("target_scale", scales[index])
		puff.set_meta("base_position", offsets[index])
		add_child(puff)
		_smoke_layers.append(puff)
	add_to_group("smoke_volumes")
	smoke_remaining = 18.0

func _update_smoke_visual(delta: float) -> void:
	_smoke_age += delta
	var growth := ease(clampf(_smoke_age / 1.15, 0.0, 1.0), 0.35)
	var fade := clampf(smoke_remaining / 2.25, 0.0, 1.0)
	var opacity := 0.0
	if _smoke_age < 0.35:
		opacity = lerpf(0.0, 0.72, _smoke_age / 0.35)
	else:
		opacity = 0.72 * fade
	for index in _smoke_layers.size():
		var puff := _smoke_layers[index]
		if not is_instance_valid(puff):
			continue
		var target_scale: Vector3 = puff.get_meta("target_scale", Vector3.ONE)
		var base_position: Vector3 = puff.get_meta("base_position", Vector3.ZERO)
		var pulse := 1.0 + sin(_smoke_age * (0.42 + index * 0.025) + index) * 0.025
		puff.scale = target_scale * maxf(growth, 0.08) * pulse
		puff.position = base_position + Vector3(sin(_smoke_age * 0.16 + index) * 0.08, minf(_smoke_age * 0.018, 0.24), cos(_smoke_age * 0.13 + index) * 0.08)
		puff.rotation.y += delta * (0.025 if index % 2 == 0 else -0.02)
		var puff_material := puff.material_override as StandardMaterial3D
		if puff_material != null:
			var color := puff_material.albedo_color
			color.a = opacity * (0.94 + (index % 3) * 0.03)
			puff_material.albedo_color = color
