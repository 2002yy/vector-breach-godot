extends RefCounted
## UI transitions require a release observation before a fresh combat press.

var _blocked := true


func disarm() -> void:
	_blocked = true


func is_armed() -> bool:
	return not _blocked


func step(allowed: bool, primary: bool, secondary: bool, interact: bool) -> bool:
	if not allowed:
		disarm()
		return false
	if _blocked:
		if not primary and not secondary and not interact:
			_blocked = false
		# Even a fast down/up edge belongs to this transition frame.
		return false
	return true
