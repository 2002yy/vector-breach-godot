extends Node


class Job:
	extends RefCounted
	signal done
	var result: Dictionary = {}
	var queued_usec := Time.get_ticks_usec()


var submitted_count := 0
var _jobs: Dictionary = {}
var _queue: Array[String] = []
var _running := false


func pending_count() -> int:
	return _jobs.size()


func read_scene(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return {"threaded": true, "resource": null, "resource_ms": 0.0, "status": "missing"}
	if not _jobs.has(path):
		_jobs[path] = Job.new()
		_queue.append(path)
		_pump.call_deferred()
	var job: Job = _jobs[path]
	await job.done
	# Each waiter gets its own receipt, including its own resource reference.
	return job.result.duplicate()


func _pump() -> void:
	if _running:
		return
	_running = true
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		var job: Job = _jobs[path]
		var began := Time.get_ticks_usec()
		var cached := ResourceLoader.has_cached(path)
		submitted_count += 1
		var error := ResourceLoader.load_threaded_request(path, "PackedScene", false)
		var requested := Time.get_ticks_usec()
		var frames := 0
		var maximum_gap := 0
		var previous := requested
		var status := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		if error == OK:
			status = ResourceLoader.load_threaded_get_status(path)
			while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				maximum_gap = maxi(maximum_gap, now - previous)
				previous = now
				frames += 1
				status = ResourceLoader.load_threaded_get_status(path)
		var ready := Time.get_ticks_usec()
		var resource: Resource
		# Terminal failures also own a native token that get() must release.
		if error == OK:
			resource = ResourceLoader.load_threaded_get(path)
		job.result = {
			"threaded": true,
			"resource": resource,
			"cached_before_load": cached,
			"thread_wait_frames": frames,
			"thread_wait_max_gap_ms": maximum_gap / 1000.0,
			"queue_ms": (began - job.queued_usec) / 1000.0,
			"request_ms": (requested - began) / 1000.0,
			"get_ms": (Time.get_ticks_usec() - ready) / 1000.0,
			"resource_ms": (Time.get_ticks_usec() - job.queued_usec) / 1000.0,
			"thread_status": status,
			"request_error": error,
		}
		_jobs.erase(path)
		job.done.emit()
	_running = false
