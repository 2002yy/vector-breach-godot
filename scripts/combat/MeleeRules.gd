extends RefCounted


# Authored game rule: rear 120-degree sector, three times base knife damage.
# Evaluate at contact, using victim facing and attacker position on the ground.
static func is_backstab(attacker: Node3D, victim: Node3D) -> bool:
	if not victim is CharacterBody3D:
		return false
	var toward_attacker := attacker.global_position - victim.global_position
	toward_attacker.y = 0.0
	var forward := -victim.global_transform.basis.z
	forward.y = 0.0
	if toward_attacker.length_squared() < 0.01 or forward.length_squared() < 0.01:
		return false
	return forward.normalized().dot(toward_attacker.normalized()) < -0.5


static func damage(base: int, attacker: Node3D, victim: Node3D) -> int:
	return base * (3 if is_backstab(attacker, victim) else 1)
