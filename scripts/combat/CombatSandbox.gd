extends Node3D

signal targets_spawned(count: int)

@export var dummy_scene: PackedScene
@export var use_spawn_points: bool = true
@export var use_landmarks: bool = true
@export var fallback_target_count: int = 3
@export var max_targets: int = 5
@export var dummy_height: float = 1.15
@export var fallback_spacing: float = 6.0

func load_for_level(level_data: Dictionary) -> void:
	_clear_targets()
	if dummy_scene == null:
		targets_spawned.emit(0)
		return

	var spawn_records: Array = _build_spawn_records(level_data)
	var spawned_count: int = 0
	for record_variant in spawn_records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant as Dictionary
		var target_instance: Node = dummy_scene.instantiate()
		if not (target_instance is Node3D):
			continue

		var target_node: Node3D = target_instance as Node3D
		target_node.position = Vector3(
			float(record.get("x", 0.0)),
			float(record.get("y", dummy_height)),
			float(record.get("z", 0.0))
		)
		add_child(target_node)
		if target_node.has_method("configure_from_record"):
			target_node.call("configure_from_record", record)
		spawned_count += 1

	targets_spawned.emit(spawned_count)

func _clear_targets() -> void:
	for child in get_children():
		child.queue_free()

func _build_spawn_records(level_data: Dictionary) -> Array:
	var records: Array = []
	var combat_targets: Array = level_data.get("combatTargets", []) as Array
	for index in range(mini(max_targets, combat_targets.size())):
		var target_variant: Variant = combat_targets[index]
		if typeof(target_variant) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_variant as Dictionary
		records.append({
			"name": String(target.get("name", "CombatTarget%d" % (index + 1))),
			"x": float(target.get("x", 0.0)),
			"y": float(target.get("y", dummy_height)),
			"z": float(target.get("z", 0.0))
		})
	if not records.is_empty():
		return records

	if use_spawn_points:
		var spawn_points: Array = level_data.get("spawnPoints", []) as Array
		for index in range(mini(max_targets, spawn_points.size())):
			var point_variant: Variant = spawn_points[index]
			if typeof(point_variant) != TYPE_DICTIONARY:
				continue
			var point: Dictionary = point_variant as Dictionary
			records.append({
				"name": "SpawnDummy%d" % (index + 1),
				"x": float(point.get("x", 0.0)),
				"y": float(point.get("y", dummy_height)),
				"z": float(point.get("z", 0.0))
			})
	if not records.is_empty():
		return records

	if use_landmarks:
		var landmarks: Array = level_data.get("landmarks", []) as Array
		for index in range(mini(max_targets, landmarks.size())):
			var landmark_variant: Variant = landmarks[index]
			if typeof(landmark_variant) != TYPE_DICTIONARY:
				continue
			var landmark: Dictionary = landmark_variant as Dictionary
			records.append({
				"name": String(landmark.get("name", "LandmarkDummy%d" % (index + 1))),
				"x": float(landmark.get("x", 0.0)),
				"y": float(landmark.get("y", dummy_height)),
				"z": float(landmark.get("z", 0.0))
			})
	if not records.is_empty():
		return records

	var exit_record: Array = level_data.get("exit", [0.0, 0.0]) as Array
	var base_x: float = 0.0
	var base_z: float = 0.0
	if exit_record.size() >= 2:
		base_x = float(exit_record[0])
		base_z = float(exit_record[1])

	for index in range(fallback_target_count):
		records.append({
			"name": "FallbackDummy%d" % (index + 1),
			"x": base_x - fallback_spacing * float(index),
			"y": dummy_height,
			"z": base_z
		})
	return records
