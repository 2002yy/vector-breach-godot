extends RefCounted

const Layout = preload("res://scripts/level/ClassicMatchLayout.gd")


class Waiter:
	extends Node
	var result: Dictionary = {}
	var finished := false

	func start(data: Dictionary) -> void:
		result = await get_node("/root/CollisionVerifier").load_layout(data)
		finished = true


static func run(host: Node) -> void:
	var prefix := "user://layout-worker-%d" % Time.get_ticks_usec()
	var source := prefix + ".txt"
	var manifest := prefix + ".json"
	_write(source, "audited collision")
	var spawns := [[0, 1, 0], [1, 1, 0], [2, 1, 0], [3, 1, 0], [4, 1, 0]]
	var expected := {
		"navigationGraph": {"points": [[0, 1, 0], [1, 1, 0]], "links": [{"from": 0, "to": 1}]},
		"objectives": [{"x": 10}, {"x": 20}],
		"matchSpawns": {"T": spawns, "CT": spawns}
	}
	var level_path := "res://data/levels/gatehouse.json"
	var raw := {
		"schema": 1,
		"collision_path": source,
		"collision_sha256": FileAccess.get_sha256(source),
		"level_sha256": {level_path: FileAccess.get_sha256(level_path)},
		"layout": expected
	}
	var original := JSON.stringify(raw)
	_write(manifest, original)
	var data := {"id": "gatehouse", "runtime_collision_scene": source, "match_manifest": manifest}
	var verifier := host.get_node("/root/CollisionVerifier")
	var before: int = verifier.submitted_count
	var first := Waiter.new()
	var second := Waiter.new()
	var abandoned := Waiter.new()
	for waiter in [first, second, abandoned]:
		host.add_child(waiter)
		waiter.start(data)
	host.call("_assert_equal", verifier.pending_count(), 1, "same layout request coalesces")
	abandoned.free()
	while not first.finished or not second.finished:
		await host.get_tree().process_frame
	host.call("_assert_equal", verifier.submitted_count - before, 1, "one file worker")
	host.call("_assert_equal", first.result.status, "verified", "full layout verification succeeds")
	host.call(
		"_assert_equal", first.result.layout, Layout.load_authored(data), "sync layout unchanged"
	)
	host.call("_assert_true", first.result.wait_frames > 0, "worker wait yields main loop")
	first.result.layout.objectives.clear()
	host.call(
		"_assert_equal", second.result.layout.objectives.size(), 2, "client layouts are isolated"
	)
	first.free()
	second.free()
	_write(source, "Audited collision")
	var changed: Dictionary = await verifier.load_layout(data)
	host.call("_assert_true", changed.layout.is_empty(), "same-size source edit is rehashed")
	_write(source, "audited collision")
	raw.level_sha256[level_path] = "wrong"
	_write(manifest, JSON.stringify(raw))
	changed = await verifier.load_layout(data)
	host.call("_assert_true", changed.layout.is_empty(), "level hash still checked independently")
	_write(manifest, original)
	first = Waiter.new()
	second = Waiter.new()
	host.add_child(first)
	host.add_child(second)
	first.start(data)
	var job: RefCounted = verifier._jobs.values()[0]
	# Change the manifest after the first consumer, before the second consumes the same job.
	job.done.connect(_write.bind(manifest, "[]"), CONNECT_ONE_SHOT)
	second.start(data)
	while not first.finished or not second.finished:
		await host.get_tree().process_frame
	host.call("_assert_equal", first.result.status, "verified", "first consumer has original input")
	host.call("_assert_equal", second.result.status, "stale", "handoff rechecks input stamps")
	host.call("_assert_true", second.result.layout.is_empty(), "changed handoff is not published")
	first.free()
	second.free()
	_write(manifest, original)
	changed = await verifier.load_layout(data)
	host.call(
		"_assert_equal", changed.status, "verified", "failed requests do not poison later loads"
	)
	host.call("_assert_equal", verifier.pending_count(), 0, "all jobs joined and released")
	await _cancel_preparation(host, source, manifest, raw)
	for path in [source, manifest]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _cancel_preparation(
	host: Node, source: String, manifest: String, raw: Dictionary
) -> void:
	var path := "res://data/levels/mirage-classic-local.json"
	raw.level_sha256 = {path: FileAccess.get_sha256(path)}
	_write(manifest, JSON.stringify(raw))
	var main: Node = host.call("_instantiate_main")
	var level := main.get_node("Level")
	var prepared: Array = []
	main.level_prepared.connect(func(data: Dictionary): prepared.append(data.id))
	main.call(
		"_on_level_loaded",
		{
			"id": "mirage-classic-local",
			"runtime_collision_scene": source,
			"match_manifest": manifest
		}
	)
	for frame in range(2):
		await host.get_tree().physics_frame
	var verifier := host.get_node("/root/CollisionVerifier")
	host.call("_assert_true", verifier.pending_count() > 0, "layout verification is in flight")
	# Begin a newer map without a level_loaded callback: serial alone cannot detect this.
	level.call("_begin_level", "training-range", false, Time.get_ticks_usec())
	while verifier.pending_count() > 0:
		await host.get_tree().process_frame
	await host.get_tree().process_frame
	host.call("_assert_true", prepared.is_empty(), "old layout cannot prepare a newer load")
	host.call("_assert_true", main._level_loading, "old result cannot clear newer loading state")
	await host.call("_cleanup_main", main)


static func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
