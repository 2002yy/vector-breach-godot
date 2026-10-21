extends "res://scripts/tests/CharacterProbeCompositeProbe.gd"

var _camera: Camera3D
var _composite: RefCounted
var _world: Node3D
var _lane: Dictionary


func _ready() -> void:
	get_tree().create_timer(600).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--evidence-dir") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	assert(await _composite_stage())
	if "--stage-only" in args:
		print("CHARACTER_POSTLIT_STAGE_OK checks=", _records.size())
		get_tree().quit()
		return
	assert(await _setup(args))
	for id in Appearance.NAMES:
		assert(await _exercise(id))
	var file := FileAccess.open(_out.path_join("motion.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"lane": _lane, "checks": _records}, "\t"))
	print("CHARACTER_COMPOSITE_MOTION_OK checks=", _records.size(), " profiles=6")
	get_tree().quit()


func _setup(args: PackedStringArray) -> bool:
	var bundle: String = args[args.find("--bundle") + 1]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bundle))
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/levels/" + data.level + ".json")
	)
	_world = Node3D.new()
	add_child(_world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-25, 145, 0)
	_world.add_child(sun)
	var level: Node3D = preload("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.level_id = data.level
	_world.add_child(level)
	var transform := Alignment.resolve(
		level.get_node("VisualRoot/LevelVisual"),
		config,
		args[args.find("--alignment-receipt") + 1] if "--alignment-receipt" in args else ""
	)
	var adapter := Adapter.new()
	assert(adapter.configure(bundle, config, transform, true))
	_composite = Composite.new()
	assert(
		_composite.configure(
			adapter,
			"res://assets/local_reference/cs_official/source-character-contrast-inputs.json",
			{
				"purpose": "diagnostic",
				"accept_average_candidate": true,
				"fog_input_kind": "diagnostic-constant",
				"strength": 0.8,
				"fog_modification": 1.0
			}
		)
	)
	_camera = Camera3D.new()
	_camera.fov = 45
	_camera.environment = Environment.new()
	_camera.environment.background_mode = Environment.BG_COLOR
	_camera.environment.background_color = Color("323b47")
	_camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_camera.environment.ambient_light_color = Color.WHITE
	_camera.environment.ambient_light_energy = 0.5
	_world.add_child(_camera)
	_camera.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var layout_path: String = config.get(
		"match_manifest", "res://data/levels/match-local/dustline.json"
	)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	_lane = _find_lane(layout.layout.navigationGraph.points)
	assert(not _lane.is_empty(), "no verified unobstructed perspective lane")
	print("PERSPECTIVE_LANE ", _lane)
	return true


func _find_lane(points: Array) -> Dictionary:
	var space := _world.get_world_3d().direct_space_state
	for target_index in range(0, points.size(), maxi(1, points.size() / 24)):
		var target := _vector(points[target_index])
		var ground := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(target + Vector3.UP, target + Vector3.DOWN * 3)
		)
		if ground.is_empty():
			continue
		target = ground.position + Vector3.UP * 0.02
		for camera_index in range(0, points.size(), maxi(1, points.size() / 100)):
			var camera_ground := _vector(points[camera_index])
			var camera_hit := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(
					camera_ground + Vector3.UP, camera_ground + Vector3.DOWN * 3
				)
			)
			if camera_hit.is_empty():
				continue
			var candidate: Vector3 = camera_hit.position + Vector3.UP * 1.6
			var distance_m := candidate.distance_to(target + Vector3.UP)
			if distance_m < 18 or distance_m > 35 or absf(candidate.y - target.y - 1.4) > 2:
				continue
			var clear := true
			var forward := ((candidate - target) * Vector3(1, 0, 1)).normalized()
			var side := forward.cross(Vector3.UP)
			for offset in [Vector3.ZERO, forward * 1.2, -forward * 1.2, side * 0.8, -side * 0.8]:
				for height in [0.15, 0.8, 1.5]:
					var ray := PhysicsRayQueryParameters3D.create(
						candidate, target + offset + Vector3.UP * height
					)
					clear = clear and space.intersect_ray(ray).is_empty()
			if clear:
				return {"target": target, "camera": candidate, "distance_m": distance_m}
	return {}


func _exercise(id: String) -> bool:
	var model := Appearance.instantiate(id)
	assert(model != null)
	_world.add_child(model)
	model.position = _lane.target
	model.look_at(Vector3(_lane.camera.x, model.position.y, _lane.camera.z))
	var players := model.find_children("*", "AnimationPlayer", true, false)
	assert(not players.is_empty())
	var player := players[0] as AnimationPlayer
	var skeleton := Appearance.find_skeleton(model)
	assert(skeleton != null and _composite.attach(model) > 0)
	var proxies := model.find_children("PostlitSurface*", "MeshInstance3D", true, false)
	for action in ["idle", "run", "crouch", "reload", "hit", "death"]:
		assert(player.has_animation(action), id + " missing animation " + action)
		var animation := player.get_animation(action)
		assert(animation.length > 0 and animation.get_track_count() > 0)
		player.play(action)
		player.pause()
		var signatures := {}
		for step in range(12):
			player.seek(animation.length * float(step) / 12.0, true)
			await get_tree().process_frame
			await get_tree().process_frame
			var pose := []
			for bone in range(skeleton.get_bone_count()):
				pose.append(str(skeleton.get_bone_global_pose(bone)))
			signatures[hash(pose)] = true
			for proxy in proxies:
				var source := proxy.get_parent() as MeshInstance3D
				assert(proxy.skin == source.skin)
				assert(proxy.global_transform.is_equal_approx(source.global_transform))
				for shape in range(proxy.mesh.get_blend_shape_count()):
					assert(
						is_equal_approx(
							proxy.get_blend_shape_value(shape), source.get_blend_shape_value(shape)
						)
					)
			if step == 6:
				assert(await _compare(model, proxies, skeleton, id + "-" + action))
		if action in ["run", "death"]:
			assert(signatures.size() > 1, "animation must move actual bones: " + id + action)
		_records.append(
			{
				"role": id,
				"action": action,
				"pose_samples": 12,
				"distinct_bone_poses": signatures.size()
			}
		)
	for transparency in [0.25, 0.65, 1.0]:
		assert(await _fade(model, skeleton, id, transparency))
	_composite.detach()
	model.queue_free()
	await get_tree().process_frame
	return true


func _compare(model: Node3D, proxies: Array, skeleton: Skeleton3D, label: String) -> bool:
	for near in [true, false]:
		_camera.position = _lane.camera
		var center := model.position + Vector3.UP
		if near:
			_camera.position = center + (_camera.position - center).normalized() * 3
		_camera.look_at(center)
		for proxy in proxies:
			proxy.hide()
		var baseline := await _capture(label + ("-near" if near else "-far") + "-baseline")
		for proxy in proxies:
			proxy.show()
		var active := await _capture(label + ("-near" if near else "-far") + "-composite")
		var bounds := _screen_bounds(skeleton, active.get_size())
		var difference := _difference(baseline.get_region(bounds), active.get_region(bounds))
		if not near and difference == 0.0:
			var saved := []
			var flat := StandardMaterial3D.new()
			flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flat.albedo_color = Color.MAGENTA
			for proxy in proxies:
				saved.append(proxy.material_override)
				proxy.material_override = flat
			await _capture(label + "-geometry-debug")
			for index in range(proxies.size()):
				proxies[index].material_override = saved[index]
			print(
				"ZERO_DIFF_DEBUG ",
				bounds,
				" probe_count=",
				saved[0].get_shader_parameter("source_probe_count")
			)
		assert(
			difference < 0.001 if near else difference > 0.0001,
			label + " near=" + str(near) + " ROI difference=" + str(difference)
		)
		_records.append(
			{"capture": label, "near": near, "roi": str(bounds), "difference": difference}
		)
	return true


func _screen_bounds(skeleton: Skeleton3D, size: Vector2i) -> Rect2i:
	var minimum := Vector2(size)
	var maximum := Vector2.ZERO
	var pixel_scale := Vector2(size) / get_viewport().get_visible_rect().size
	for bone in range(skeleton.get_bone_count()):
		var point := (
			_camera.unproject_position(
				skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			)
			* pixel_scale
		)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var region := Rect2i(
		Vector2i(minimum) - Vector2i(8, 8), Vector2i(maximum - minimum) + Vector2i(17, 17)
	)
	return region.intersection(Rect2i(Vector2i.ZERO, size))


func _fade(model: Node3D, skeleton: Skeleton3D, id: String, transparency: float) -> bool:
	model.show()
	id += "-opacity-" + str(transparency)
	_camera.position = _lane.camera
	_camera.look_at(model.position + Vector3.UP)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.has_meta("source_postlit_surface"):
			mesh.transparency = transparency
	var proxies := model.find_children("PostlitSurface*", "MeshInstance3D", true, false)
	for proxy in proxies:
		proxy.hide()
	var original := await _capture(id + "-faded-original")
	for proxy in proxies:
		proxy.show()
	var hidden := await _capture(id + "-faded")
	var bounds := _screen_bounds(skeleton, hidden.get_size())
	model.hide()
	var absent := await _capture(id + "-absent")
	var difference := _difference(hidden.get_region(bounds), original.get_region(bounds))
	assert(difference < 0.0001, "faded character must not leave a postlit ghost")
	_records.append(
		{
			"fade": id,
			"transparency": transparency,
			"difference": difference,
			"roi": str(bounds),
			"original_fade_residual":
			_difference(original.get_region(bounds), absent.get_region(bounds))
		}
	)
	return true


func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
