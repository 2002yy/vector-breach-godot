extends Node3D


func _ready() -> void:
	var result: Dictionary = await preload("res://scripts/tests/AISharedMovementTests.gd").run(self)
	for failure in result.failures:
		push_error(String(failure))
	print("AI_SHARED_MOVEMENT_OK checks=", result.checks, " failures=", result.failures.size())
	get_tree().quit(0 if result.failures.is_empty() and result.checks > 0 else 1)
