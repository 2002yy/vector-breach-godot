extends RefCounted
## Only a legal observation can replace an enemy's last-known pose.

var _seen: Dictionary = {}


func clear() -> void:
	_seen.clear()


func observe(id: int, position: Vector3, yaw: float, now: int) -> void:
	_seen[id] = {"position": position, "yaw": yaw, "expires": now + 2500}


func recall(id: int, now: int) -> Dictionary:
	var record: Dictionary = _seen.get(id, {})
	if record.is_empty():
		return {}
	if int(record["expires"]) < now:
		_seen.erase(id)
		return {}
	return record.duplicate(true)
