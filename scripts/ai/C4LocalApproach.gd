extends RefCounted
## Conservative final approach only; never replaces general map navigation.


static func allowed(actor: CharacterBody3D, target: Vector3) -> bool:
	if bool(actor.get("ai_crouching")):
		return false
	var motion := target - actor.global_position
	if motion.length() > 3.0 or absf(motion.y) > 0.3:
		return false
	motion.y = 0.0
	if actor.test_move(actor.global_transform, motion):
		return false
	var steps := maxi(1, ceili(motion.length() / 0.2))
	var collision := actor.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D
	if capsule == null:
		return false
	var foot_offset := collision.position.y - capsule.height * 0.5
	for sample in range(steps + 1):
		var at := actor.global_position.lerp(target, float(sample) / steps)
		at.y += foot_offset
		var query := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 0.2, at - Vector3.UP * 0.2, 1
		)
		query.exclude = [actor.get_rid()]
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.9:
			return false
	return true
