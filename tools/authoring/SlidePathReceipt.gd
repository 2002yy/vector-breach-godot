extends RefCounted
## Observe the central CharacterBody move. Remainders are requests, not traveled paths.


static func array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func capture(body: CharacterBody3D, stage: String) -> Dictionary:
	var movements: Array[Dictionary] = []
	for index in body.get_slide_collision_count():
		var hit := body.get_slide_collision(index)
		var contacts: Array[Dictionary] = []
		for contact in hit.get_collision_count():
			var collider := hit.get_collider(contact) as Node
			(
				contacts
				. append(
					{
						"body": String(collider.get_path()) if collider != null else "",
						"shape": hit.get_collider_shape_index(contact),
						"normal": array(hit.get_normal(contact)),
						"position": array(hit.get_position(contact)),
					}
				)
			)
		(
			movements
			. append(
				{
					"index": index,
					"travel": array(hit.get_travel()),
					"remainder": array(hit.get_remainder()),
					"depth": hit.get_depth(),
					"contacts": contacts,
				}
			)
		)
	var delta := body.get_position_delta()
	return {
		"stage": stage,
		"end": array(body.global_position),
		"start": array(body.global_position - delta),
		"position_delta": array(delta),
		"last_motion": array(body.get_last_motion()),
		"slide_count": movements.size(),
		"movements": movements,
	}
