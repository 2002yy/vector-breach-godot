extends "res://tools/authoring/probe_c4_recovery_trace.gd"
## Observes actual flash state and shots, without changing perception or combat.

var _flash_trace: FileAccess


func _sample(frames: int) -> void:
	super._sample(frames)
	if _flash_trace == null:
		_flash_trace = FileAccess.open(
			OS.get_cmdline_user_args()[3] + "/flash.jsonl", FileAccess.WRITE
		)
	var actors: Array = []
	for actor in _main.get_node("CombatSandbox").get_children():
		if not actor is CharacterBody3D or not actor.has_node("TacticalBotBrain"):
			continue
		var brain: Node = actor.get_node("TacticalBotBrain")
		(
			actors
			. append(
				{
					"name": actor.get("display_name"),
					"dead": actor.get("is_dead"),
					"intensity": actor.call("get_flash_intensity"),
					"state": brain.call("get_snapshot").get("state"),
					"shots": brain.get("_shot_count"),
				}
			)
		)
	_flash_trace.store_line(JSON.stringify({"frame": frames, "actors": actors}))
	_flash_trace.flush()
