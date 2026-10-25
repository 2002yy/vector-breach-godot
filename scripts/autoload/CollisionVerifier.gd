extends Node

const Cache = preload("res://scripts/level/SourceCollisionCache.gd")
const Layout = preload("res://scripts/level/ClassicMatchLayout.gd")


class Job:
	extends RefCounted
	signal done
	var source := ""
	var directory := ""
	var result: Dictionary = {}
	var layout_data: Dictionary = {}
	var manifest_path := ""
	var layout_job := false


var submitted_count := 0
var _jobs: Dictionary = {}
var _queue: Array[String] = []
var _running := false
var _active_task := -1


func pending_count() -> int:
	return _jobs.size()


func verify(source: String, directory: String = Cache.DIRECTORY) -> Dictionary:
	var key := JSON.stringify([source, directory])
	if not _jobs.has(key):
		var queued := Job.new()
		queued.source = source
		queued.directory = directory
		_jobs[key] = queued
		_queue.append(key)
		_pump.call_deferred()
	var job: Job = _jobs[key]
	await job.done
	return job.result.duplicate(true)


static func _verify_files(job: Job) -> void:
	# Pure filesystem work; no scene nodes, shapes or physics-server calls.
	if job.layout_job:
		var stamps := Layout.input_stamps(job.layout_data, job.manifest_path)
		var layout := Layout.load_authored(job.layout_data, job.manifest_path)
		if stamps.is_empty() or stamps != Layout.input_stamps(job.layout_data, job.manifest_path):
			layout = {}
		job.result = {
			"layout": layout,
			"stamps": stamps,
			"status": "verified" if not layout.is_empty() else "invalid"
		}
	else:
		job.result = Cache.verify_files(job.source, job.directory)


func load_layout(data: Dictionary, manifest_path: String = Layout.AUTHORED_PATH) -> Dictionary:
	var key := JSON.stringify(["layout", data, manifest_path])
	if not _jobs.has(key):
		var queued := Job.new()
		queued.layout_data = data.duplicate(true)
		queued.manifest_path = manifest_path
		queued.layout_job = true
		_jobs[key] = queued
		_queue.append(key)
		_pump.call_deferred()
	var job: Job = _jobs[key]
	await job.done
	var result := job.result.duplicate(true)
	if result.status == "verified" and result.stamps != Layout.input_stamps(data, manifest_path):
		result.layout = {}
		result.status = "stale"
	return result


func _exit_tree() -> void:
	if _active_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_active_task)
		_active_task = -1


func _pump() -> void:
	if _running:
		return
	_running = true
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		var job: Job = _jobs[key]
		submitted_count += 1
		var began := Time.get_ticks_usec()
		_active_task = WorkerThreadPool.add_task(
			_verify_files.bind(job), false, "Collision file verification"
		)
		var frames := 0
		var maximum_gap := 0
		var previous := began
		while not WorkerThreadPool.is_task_completed(_active_task):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			maximum_gap = maxi(maximum_gap, now - previous)
			previous = now
			frames += 1
		WorkerThreadPool.wait_for_task_completion(_active_task)
		_active_task = -1
		# Completion joins the worker before the main thread reads its result.
		job.result["wait_frames"] = frames
		job.result["max_frame_gap_ms"] = maximum_gap / 1000.0
		job.result["wall_ms"] = (Time.get_ticks_usec() - began) / 1000.0
		_jobs.erase(key)
		job.done.emit()
	_running = false
