extends "res://tools/run_match_acceptance.gd"
## Read-only extension of the frozen full-match harness; never calls lease selection.

var _recovery_trace: FileAccess


class TargetFixture:
	extends RefCounted
	var _target: Object


func _initialize() -> void:
	if OS.get_cmdline_user_args() == PackedStringArray(["--stale-target-check"]):
		var fixture := TargetFixture.new()
		fixture._target = Node.new()
		fixture._target.free()
		var target: Variant = fixture.get("_target")
		assert(not is_instance_valid(target))
		var label: Variant = target.get("display_name") if is_instance_valid(target) else ""
		assert(label == "")
		print("C4_TRACE_STALE_TARGET_OK")
		quit(0)
		return
	super._initialize()


func _sample(frames: int) -> void:
	super._sample(frames)
	if _recovery_trace == null:
		_recovery_trace = FileAccess.open(
			OS.get_cmdline_user_args()[3] + "/recovery.jsonl", FileAccess.WRITE
		)
	var c4: Node3D = _main.get_node("C4Device")
	var owner: Object = null
	var reference: Variant = (
		c4.get_meta("recovery_actor") if c4.has_meta("recovery_actor") else null
	)
	if reference is WeakRef:
		owner = reference.get_ref()
	var actors: Array = []
	for actor in _main.get_node("CombatSandbox").get_children():
		if not actor is CharacterBody3D or not actor.has_node("TacticalBotBrain"):
			continue
		var brain: Node = actor.get_node("TacticalBotBrain")
		var target: Variant = brain.get("_target")
		var navigation: RefCounted = brain.get("_navigation")
		var points: Array = []
		for index in brain.get("_navigation_path"):
			points.append(navigation.get("points")[index])
		(
			actors
			. append(
				{
					"name": actor.get("display_name"),
					"position": actor.global_position,
					"velocity": actor.velocity,
					"dead": actor.get("is_dead"),
					"team": actor.get("team"),
					"lease_owner": owner == actor,
					"enemy": target.get("display_name") if is_instance_valid(target) else "",
					"snapshot": brain.call("get_snapshot"),
					"path_points": points,
					"path_index": brain.get("_navigation_path_index"),
					"unreachable": brain.get("_navigation_unreachable"),
					"known_c4_state": brain.get("_c4_known_state"),
					"known_c4_position": brain.get("_c4_known_position"),
				}
			)
		)
	(
		_recovery_trace
		. store_line(
			(
				JSON
				. stringify(
					{
						"frame": frames,
						"serial": _round.round_serial,
						"round_state": _round.get_state_name(),
						"remaining": _round.time_remaining,
						"c4_state": c4.get("device_state"),
						"c4_position": c4.global_position,
						"owner": owner.get("display_name") if is_instance_valid(owner) else "",
						"actors": actors,
					}
				)
			)
		)
	)
	_recovery_trace.flush()
