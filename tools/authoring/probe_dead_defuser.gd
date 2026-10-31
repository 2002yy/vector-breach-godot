extends SceneTree
## Known-bug detector: exit0 means the orphan was reproduced, NOT gameplay PASS.
## Deliberately excluded from native test gates; no Main/map/model load.

var failures := 0
var _owned: Array[Node] = []
var _round: Node


class Body:
	extends CharacterBody3D
	var is_dead := false
	var team := "CT"

	func set_ai_scoped(_value: bool) -> void:
		pass


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var round_node := root.get_node_or_null("RoundManager")
	_round = round_node
	if not _check(round_node != null, "RoundManager autoload required"):
		_finish()
		return
	round_node.set_process(false)
	round_node.set_live()
	if not _check(round_node.plant_bomb("A"), "plant fixture bomb"):
		_finish()
		return
	var device := Node3D.new()
	root.add_child(device)
	_owned.append(device)
	var first := Body.new()
	var second := Body.new()
	root.add_child(first)
	_owned.append(first)
	root.add_child(second)
	_owned.append(second)
	var brain_script = load("res://tools/authoring/DeadDefuserBrainFixture.gd")
	if not _check(brain_script != null and brain_script.can_instantiate(), "brain fixture load"):
		_finish()
		return
	var a = brain_script.new()
	var b = brain_script.new()
	first.add_child(a)
	second.add_child(b)
	a.setup(first)
	b.setup(second)
	if not _check(a.actor == first and b.actor == second, "actor setup"):
		_finish()
		return
	a._c4_device = device
	b._c4_device = device
	a._begin_defuse()
	if not _check(a._bomb_interacting, "first CT starts defuse"):
		_finish()
		return
	a._tick_bomb_interaction(1.0)
	_check(round_node.interaction_elapsed == 1.0, "interaction progress equals1s")
	first.is_dead = true
	a.tick(0.25)
	b._tick_ct_side_objective(0.25)
	var remaining: float = round_node.time_remaining
	round_node._process(0.25)
	_check(round_node.is_objective_interacting(), "dead defuser leaves global interaction")
	_check(not b._bomb_interacting, "second CT remains blocked")
	_check(round_node.interaction_elapsed == 1.0, "interaction progress equals1s")
	_check(round_node.time_remaining < remaining, "bomb clock still advances")
	if failures == 0:
		print(
			"DEAD_DEFUSER_ORPHAN_CONFIRMED ",
			(
				JSON
				. stringify(
					{
						"interaction_owner": round_node.interaction_owner,
						"elapsed": round_node.interaction_elapsed,
						"second_ct_interacting": b._bomb_interacting,
						"clock_before": remaining,
						"clock_after": round_node.time_remaining,
						"fixture":
						"actual brain interaction and dead tick; motion overridden; synthetic death flag"
					}
				)
			)
		)
	_finish()


func _check(value: bool, label: String) -> bool:
	if not value:
		failures += 1
		printerr("DEAD_DEFUSER_DIAGNOSTIC_FAILED ", label)
	return value


func _finish() -> void:
	for node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
	if is_instance_valid(_round):
		_round.cancel_objective_interaction()
	quit(0 if failures == 0 else 1)
