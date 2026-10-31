extends "res://scripts/ai/TacticalBotBrain.gd"


## Preserve real objective methods; suppress movement only in the empty-world diagnostic.
func _move_to_or_hold(
	_delta: float, _destination: Vector3, _hold: bool = false, _recovery: bool = false
) -> void:
	pass


func _stop(_delta: float) -> void:
	pass
