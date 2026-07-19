extends RigidBody3D

var grenade_type: String = "he_grenade"
var thrower: CharacterBody3D
var fuse_remaining: float = 1.7
var smoke_remaining: float = 0.0
var _detonated: bool = false

func configure(kind: String, owner_player: CharacterBody3D, origin: Vector3, velocity: Vector3) -> void:
	grenade_type = kind
	thrower = owner_player
	global_position = origin
	linear_velocity = velocity

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
	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.09
	sphere_mesh.height = 0.18
	mesh.mesh = sphere_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.14, 0.18, 0.13) if grenade_type == "he_grenade" else (Color(0.68, 0.72, 0.75) if grenade_type == "flash_grenade" else Color(0.25, 0.3, 0.28))
	mesh.material_override = material
	add_child(mesh)

func _physics_process(delta: float) -> void:
	if _detonated:
		if grenade_type == "smoke_grenade":
			smoke_remaining -= delta
			if smoke_remaining <= 0.0:
				queue_free()
		return
	fuse_remaining -= delta
	if fuse_remaining <= 0.0:
		_detonate()

func _detonate() -> void:
	_detonated = true
	if grenade_type == "he_grenade":
		_apply_he_damage()
		queue_free()
	elif grenade_type == "flash_grenade":
		_apply_flash()
		queue_free()
	else:
		_activate_smoke()

func _apply_he_damage() -> void:
	for target in get_tree().get_nodes_in_group("target_dummies"):
		if target is Node3D:
			var distance := global_position.distance_to((target as Node3D).global_position)
			if distance <= 7.0 and target.has_method("apply_hitscan_damage"):
				var damage := maxi(1, int(round(98.0 * pow(1.0 - distance / 7.0, 1.35) * _blast_cover_scale((target as Node3D).global_position, target))))
				var result := target.call("apply_hitscan_damage", damage, (target as Node3D).global_position, 0.5, false) as Dictionary
				if bool(result.get("hit", false)):
					GameState.register_hit(bool(result.get("killed", false)), "he_grenade")
	if is_instance_valid(thrower):
		var player_distance := global_position.distance_to(thrower.global_position)
		if player_distance <= 7.0:
			var self_damage := maxi(1, int(round(70.0 * pow(1.0 - player_distance / 7.0, 1.35) * _blast_cover_scale(thrower.global_position, thrower))))
			thrower.call("apply_explosive_damage", self_damage)

func _blast_cover_scale(target_position: Vector3, target_collider: Variant) -> float:
	var query := PhysicsRayQueryParameters3D.create(global_position, target_position + Vector3.UP * 0.25)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider", null) == target_collider:
		return 1.0
	return 0.35

func _apply_flash() -> void:
	if not is_instance_valid(thrower):
		return
	var camera := thrower.call("get_camera_node") as Camera3D
	if camera == null:
		return
	var delta := global_position - camera.global_position
	if delta.length() > 18.0:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, camera.global_position)
	query.exclude = [get_rid(), thrower.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	var facing := clampf((-camera.global_transform.basis.z).dot(delta.normalized()), -1.0, 1.0)
	var intensity := clampf((1.0 - delta.length() / 18.0) * lerpf(0.25, 1.0, maxf(facing, 0.0)), 0.0, 1.0)
	thrower.call("apply_flash_effect", intensity, lerpf(0.5, 3.4, intensity))

func _activate_smoke() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for child in get_children():
		if child is CollisionShape3D or child is MeshInstance3D:
			child.queue_free()
	var cloud := MeshInstance3D.new()
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = 3.1
	cloud_mesh.height = 5.2
	cloud.mesh = cloud_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.32, 0.36, 0.34, 0.78)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud.material_override = material
	add_child(cloud)
	add_to_group("smoke_volumes")
	smoke_remaining = 18.0
