extends RefCounted


class Waiter:
	extends Node
	var result: Dictionary = {}
	var finished := false

	func start(path: String) -> void:
		result = await get_node("/root/SceneReader").read_scene(path)
		finished = true


class FixtureLevel:
	extends "res://scripts/level/GrayboxLevel.gd"
	var fixture_path := ""

	func _begin_level(id: String, emit_errors: bool, began: int) -> Dictionary:
		if id != "async-fixture":
			return super._begin_level(id, emit_errors, began)
		_load_generation += 1
		load_count += 1
		last_load_timings = {"id": id, "success": false}
		return {"id": id, "visual_scene": fixture_path}


static func run(host: Node) -> void:
	var reader := host.get_node("/root/SceneReader")
	var path := "user://threaded-scene-%d.tscn" % Time.get_ticks_usec()
	var root := Node3D.new()
	root.name = "ThreadedFixture"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
	packed = null
	var before: int = reader.submitted_count
	var abandoned := Waiter.new()
	var first := Waiter.new()
	var second := Waiter.new()
	host.add_child(abandoned)
	host.add_child(first)
	host.add_child(second)
	abandoned.start(path)
	first.start(path)
	second.start(path)
	host.call("_assert_equal", reader.pending_count(), 1, "same-path requests join one job")
	abandoned.free()
	while not first.finished or not second.finished:
		await host.get_tree().process_frame
	host.call(
		"_assert_equal",
		reader.submitted_count - before,
		1,
		"one threaded request for multiple clients"
	)
	host.call("_assert_equal", reader.pending_count(), 0, "all requests drain")
	host.call("_assert_true", first.result.resource is PackedScene, "reader returns a ready scene")
	host.call(
		"_assert_true",
		first.result.resource == second.result.resource,
		"clients receive the same source"
	)
	var weak: WeakRef = weakref(first.result.resource)
	first.result.erase("resource")
	host.call(
		"_assert_true", second.result.resource != null, "receipts do not share mutable dictionaries"
	)
	second.result.clear()
	first.free()
	second.free()
	await host.get_tree().process_frame
	host.call("_assert_true", weak.get_ref() == null, "no service cache retains completed scene")
	await _two_paths(host, path)
	await _stale_level(host, path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var missing: Dictionary = await reader.read_scene(path)
	host.call("_assert_true", missing.resource == null, "missing file fails without creating a job")
	host.call("_assert_equal", reader.pending_count(), 0, "failed request leaves no job")
	await _failure_retry(host, path)


static func _stale_level(host: Node, path: String) -> void:
	var level := preload("res://scenes/level/GrayboxLevel.tscn").instantiate()
	level.set_script(FixtureLevel)
	level.load_on_ready = false
	level.fixture_path = path
	host.add_child(level)
	var completed: Array = []
	level.level_loaded.connect(func(data: Dictionary): completed.append(data.id))
	level.call("load_level_async", "async-fixture", false)
	level.call("load_level", "gatehouse", false)
	var visual_count: int = level.get_node("VisualRoot").get_child_count()
	var reader := host.get_node("/root/SceneReader")
	while reader.pending_count() > 0:
		await host.get_tree().process_frame
	host.call("_assert_equal", completed, ["gatehouse"], "stale completion cannot publish a level")
	host.call(
		"_assert_equal",
		level.last_load_timings.id,
		"gatehouse",
		"stale receipt cannot overwrite newer load"
	)
	host.call(
		"_assert_true",
		level.get_node("VisualRoot").get_child_count() == visual_count,
		"stale scene cannot attach"
	)
	level.call("load_level_async", "async-fixture", false)
	level.free()
	while reader.pending_count() > 0:
		await host.get_tree().process_frame
	host.call(
		"_assert_equal", reader.pending_count(), 0, "reader drains after level owner is destroyed"
	)


static func _two_paths(host: Node, path: String) -> void:
	var other := path.get_basename() + "-other.tscn"
	var file := FileAccess.open(other, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(path))
	file.close()
	var first := Waiter.new()
	var second := Waiter.new()
	host.add_child(first)
	host.add_child(second)
	first.start(path)
	second.start(other)
	var reader := host.get_node("/root/SceneReader")
	host.call("_assert_equal", reader.pending_count(), 2, "different paths queue separate jobs")
	while not first.finished or not second.finished:
		await host.get_tree().process_frame
	host.call(
		"_assert_true",
		first.result.resource != second.result.resource,
		"queued paths cannot mix results"
	)
	var cached: Dictionary = await reader.read_scene(path)
	host.call("_assert_true", cached.cached_before_load, "already retained source is handled")
	host.call(
		"_assert_true",
		cached.resource == first.result.resource,
		"cached request returns its source"
	)
	cached.clear()
	first.free()
	second.free()
	host.call("_assert_equal", reader.pending_count(), 0, "queue fully drains")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(other))


static func _failure_retry(host: Node, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[gd_scene format=3]\nINVALID CONTENT\n")
	file.close()
	var reader := host.get_node("/root/SceneReader")
	# Only the known native parse failure is expected; restore before assertions.
	var previous_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var failed: Dictionary = await reader.read_scene(path)
	Engine.print_error_messages = previous_errors
	host.call("_assert_true", failed.resource == null, "native read failure returns no scene")
	host.call(
		"_assert_equal",
		failed.thread_status,
		ResourceLoader.THREAD_LOAD_FAILED,
		"native failure recorded"
	)
	host.call(
		"_assert_equal",
		ResourceLoader.load_threaded_get_status(path),
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"failed native request token is consumed"
	)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[gd_scene format=3]\n[node name="Retry" type="Node3D"]\n')
	file.close()
	var valid: Dictionary = await reader.read_scene(path)
	host.call(
		"_assert_true", valid.resource is PackedScene, "corrected source retries on the same path"
	)
	host.call("_assert_equal", reader.pending_count(), 0, "retry leaves no service job")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
