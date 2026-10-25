extends RefCounted

const Scene = preload("res://scripts/SceneInstance.gd")


class FixtureLevel:
	extends "res://scripts/level/GrayboxLevel.gd"
	var fixture_path := ""

	func _begin_level(id: String, emit_errors: bool, began: int) -> Dictionary:
		if id != "visual-lifetime-fixture":
			return super._begin_level(id, emit_errors, began)
		_load_generation += 1
		load_count += 1
		last_load_timings = {"id": id, "success": false}
		_current_level_data = {
			"id": id, "visual_scene": fixture_path, "original_reference_materials": true
		}
		return _current_level_data


static func run(host: Node) -> void:
	var path := "user://map-visual-lifetime-%d.tscn" % Time.get_ticks_usec()
	_save(path)
	var level: Node = load("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.set_script(FixtureLevel)
	level.load_on_ready = false
	level.fixture_path = path
	host.add_child(level)
	host.call("_assert_true", await level.load_level_async("visual-lifetime-fixture"), "first load")
	await host.get_tree().process_frame
	var visual := level.get_node("VisualRoot/LevelVisual")
	var source: WeakRef = weakref(Scene.source(visual))
	host.call("_assert_true", source.get_ref() != null, "main visual owns source")
	host.call(
		"_assert_true", not level.last_load_timings.retained_visual_scene, "cold has no bridge"
	)
	var mesh := visual.get_node("Foliage") as MeshInstance3D
	mesh.get_surface_override_material(0).albedo_color = Color.MAGENTA
	var collision: Node = level.call(
		"_instantiate_visual_resource", path, "LevelCollisionSource", false
	)
	host.call("_assert_true", Scene.source(collision) == null, "collision source is not retained")
	_detach_fixture_meshes(level)
	host.call("_assert_true", await level.load_level_async("visual-lifetime-fixture"), "same map")
	await host.get_tree().process_frame
	visual = level.get_node("VisualRoot/LevelVisual")
	host.call("_assert_true", level.last_load_timings.retained_visual_scene, "warm uses bridge")
	host.call(
		"_assert_true", Scene.source(visual) == source.get_ref(), "same original packed scene"
	)
	host.call(
		"_assert_true",
		level.last_load_timings.scene_layers.LevelVisual.cached_before_load,
		"threaded reader sees retained loader resource"
	)
	mesh = visual.get_node("Foliage") as MeshInstance3D
	host.call(
		"_assert_equal",
		mesh.get_surface_override_material(0).albedo_color,
		Color.WHITE,
		"per-instance material edits do not contaminate replacement"
	)
	var untouched := Scene.source(visual).instantiate()
	var material := (untouched.get_node("Foliage") as MeshInstance3D).get_active_material(0)
	host.call("_assert_true", material.vertex_color_use_as_albedo, "source material stays original")
	untouched.free()
	_detach_fixture_meshes(level)
	host.call("_assert_true", level.load_level("visual-lifetime-fixture"), "sync same map")
	await host.get_tree().process_frame
	host.call(
		"_assert_true",
		Scene.source(level.get_node("VisualRoot/LevelVisual")) == source.get_ref(),
		"sync replacement also spans retirement"
	)
	_detach_fixture_meshes(level)
	host.call("_assert_true", await level.load_level_async("training-range"), "different map")
	await host.get_tree().process_frame
	host.call("_assert_true", source.get_ref() == null, "map change releases old packed scene")
	host.call(
		"_assert_true", not level.last_load_timings.retained_visual_scene, "no cross-map bridge"
	)
	host.call("_assert_true", await level.load_level_async("visual-lifetime-fixture"), "load again")
	await host.get_tree().process_frame
	var leaving: WeakRef = weakref(Scene.source(level.get_node("VisualRoot/LevelVisual")))
	_detach_fixture_meshes(level)
	level.free()
	await host.get_tree().process_frame
	host.call("_assert_true", leaving.get_ref() == null, "level destruction releases source")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _detach_fixture_meshes(level: Node) -> void:
	# Match existing material fixtures: Dummy renderer needs primitive meshes detached before free.
	for node in level.get_node("VisualRoot").find_children(
		"Foliage", "MeshInstance3D", true, false
	):
		node.mesh = null


static func _save(path: String) -> void:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Foliage"
	mesh.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.resource_name = "grape_leaves_01"
	material.vertex_color_use_as_albedo = true
	mesh.mesh.material = material
	root.add_child(mesh)
	mesh.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
