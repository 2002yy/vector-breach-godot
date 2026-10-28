extends SceneTree
## Bounded collision/capsule diagnostic, not Player or human route acceptance.

const MAPS := ["dustline-depths-original-local", "mirage-classic-local", "inferno-classic-local"]
const Atlas = preload("res://scripts/ui/RadarAtlas.gd")


func _initialize() -> void:
	_run.call_deferred()


func _collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
	for child in node.get_children():
		_collisions(child)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]):
		quit(1)
		return
	Engine.physics_ticks_per_second = 60
	var results: Array = []
	for map_id in MAPS:
		var path: String = "res://data/levels/" + map_id + ".json"
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var world := Node3D.new()
		root.add_child(world)
		var original: Node3D = load(data.runtime_collision_scene).instantiate()
		world.add_child(original)
		_collisions(original)
		await physics_frame
		await physics_frame
		var space := world.get_world_3d().direct_space_state
		var atlas: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(
				"res://assets/local_reference/radar/" + map_id + "/v4/atlas.json"
			)
		)
		var anchors: Array = data.get("spawnHints", {}).values()
		var candidates: Array = []
		var controls: Array = []
		for anchor in anchors:
			var hits := {}
			for x in range(-4, 5):
				for z in range(-4, 5):
					var p := Vector3(
						float(anchor[0]) + x, float(anchor[1]) + 2, float(anchor[2]) + z
					)
					var hit := space.intersect_ray(
						PhysicsRayQueryParameters3D.create(p, p - Vector3.UP * 8)
					)
					if not hit.is_empty() and hit.normal.y > 0.7:
						hits[Vector2i(x, z)] = hit.position
			for key in hits:
				for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
					if hits.has(key + offset):
						var a: Vector3 = hits[key]
						var b: Vector3 = hits[key + offset]
						if absf(a.y - b.y) < 0.01 and controls.size() < 2:
							controls.append({"a": a, "b": b, "rise": 0.0})
						if absf(a.y - b.y) > 0.03 and absf(a.y - b.y) < 1.0:
							candidates.append({"a": a, "b": b, "rise": absf(a.y - b.y)})
		candidates.sort_custom(func(a, b): return a.rise > b.rise)
		var varying_candidates := candidates.size()
		if candidates.is_empty():
			candidates = controls
		var trials: Array = []
		for edge in candidates.slice(0, 2):
			var actor := CharacterBody3D.new()
			var collision := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.3
			capsule.height = 1.8
			collision.shape = capsule
			actor.add_child(collision)
			world.add_child(actor)
			actor.position = edge.a + Vector3.UP * 0.92
			var trace: Array = []
			var previous := -1
			var floor_height: float = edge.a.y
			for tick in range(90):
				await physics_frame
				var direction: Vector3 = edge.b - actor.position
				direction.y = 0
				direction = direction.normalized()
				actor.velocity.x = direction.x * 1.5
				actor.velocity.z = direction.z * 1.5
				actor.velocity.y -= 9.8 / 60.0
				actor.move_and_slide()
				var feet := actor.position.y - 0.9
				floor_height = Atlas.floor_sample(
					floor_height, feet, actor.is_on_floor(), tick == 0
				)
				previous = Atlas.nearest_layer(atlas.layers, floor_height, previous)
				trace.append(
					{
						"tick": tick,
						"position": [actor.position.x, actor.position.y, actor.position.z],
						"feet": feet,
						"grounded": actor.is_on_floor(),
						"layer": previous
					}
				)
			trials.append(
				{
					"start": [edge.a.x, edge.a.y, edge.a.z],
					"target": [edge.b.x, edge.b.y, edge.b.z],
					"distance_final":
					Vector2(actor.position.x - edge.b.x, actor.position.z - edge.b.z).length(),
					"trace": trace
				}
			)
			actor.queue_free()
			await process_frame
		results.append(
			{
				"map": map_id,
				"source_sha256": FileAccess.get_sha256(data.runtime_collision_scene),
				"level_sha256": FileAccess.get_sha256(path),
				"candidates": varying_candidates,
				"walk_only_control": varying_candidates == 0,
				"trials": trials
			}
		)
		world.queue_free()
		await process_frame
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{"kind": "collision_capsule_only", "human_acceptance": false, "maps": results}, "\t"
		)
	)
	file.close()
	print("RADAR_FLOOR_ROUTES_OK maps=3")
	quit(0)
