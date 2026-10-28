extends RefCounted
## Exercise the production actor path, not just a copied speed formula.

const ActorScene = preload("res://scenes/combat/TacticalActor.tscn")
const Rules = preload("res://scripts/player/ClassicMovementRules.gd")
const Policy = preload("res://scripts/ai/ActorMovementPolicy.gd")

var failures: Array[String] = []
var checks := 0


static func run(owner: Node) -> Dictionary:
	var audit := new()
	await audit._run(owner)
	return {"checks": audit.checks, "failures": audit.failures}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run(owner: Node) -> void:
	GameState.reset_runtime_state()
	RoundManager.set_warmup()
	var world := Node3D.new()
	owner.add_child(world)
	var actor = ActorScene.instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	var brain: Node = actor.get_node("TacticalBotBrain")
	var defaults := Policy.current_defaults()
	_check(is_equal_approx(defaults.run, 6.2), "read current Player default run")
	brain.call("configure", {"weapon": "rifle", "aiEnabled": false})
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(5.4), 5.4),
		"retain default 5.4 navigation cap"
	)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(3.888), 3.888), "retain precise route cap"
	)
	actor.set_ai_crouching(true)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(2.2), 2.068),
		"Current rifle crouch uses player limit"
	)
	actor.set_ai_crouching(false)
	actor.set_ai_walking(true)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(5.4), 3.008),
		"Current rifle quiet walk uses player limit"
	)
	actor.set_ai_walking(false)
	for scheme in Rules.SCHEMES:
		actor.movement_scheme = scheme
		for weapon in ["rifle", "sniper", "smg", "shotgun", "pistol", "knife"]:
			brain.call("configure", {"weapon": weapon, "aiEnabled": false})
			for pose in ["run", "walk", "crouch"]:
				actor.set_ai_crouching(pose == "crouch")
				actor.set_ai_walking(pose == "walk")
				for scoped in [false, true]:
					actor.set_ai_scoped(scoped)
					var context: Dictionary = brain.call("get_movement_context")
					(
						context
						. merge(
							{
								"scoped": scoped and weapon == "sniper",
								"crouching": pose == "crouch",
								"walking": pose == "walk",
								"tagging": 1.0,
								"water": 1.0,
							}
						)
					)
					var expected: float = Rules.speed_limit(scheme, context, defaults)
					_check(
						is_equal_approx(actor.resolve_ai_navigation_speed(20.0), expected),
						"actor shares %s %s %s scoped=%s" % [scheme, weapon, pose, scoped]
					)
					_check(actor.ai_scoped == (scoped and weapon == "sniper"), "only AWP can scope")
					actor.velocity = Vector3.ZERO
					actor.apply_ai_navigation(Vector3.RIGHT * 3.0, 1.0, 0.0, 1.0)
					_check(
						(
							Vector2(actor.velocity.x, actor.velocity.z).length()
							<= minf(1.0, expected) + 0.00001
						),
						"navigation cap and overlong direction do not exceed shared limit"
					)
	# Damage state survives pose/equipment changes and applies after a lower nav cap.
	brain.call("configure", {"weapon": "rifle", "aiEnabled": false})
	actor.movement_scheme = "modern_cs"
	actor.set_ai_crouching(false)
	actor.set_ai_walking(false)
	var damage: Dictionary = actor.apply_hitscan_damage(1, actor.global_position, 1.0, false, "T")
	_check(bool(damage.get("hit", false)), "real damage entry accepted")
	var tagged_speed: float = actor.resolve_ai_navigation_speed(1.0)
	_check(is_equal_approx(tagged_speed, 0.48), "tagging applies after small navigation cap")
	actor.set_ai_crouching(true)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(1.0), tagged_speed),
		"crouch cannot clear tagging"
	)
	brain.call("configure", {"weapon": "sniper", "aiEnabled": false})
	actor.set_ai_crouching(false)
	actor.set_ai_scoped(true)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(1.0), tagged_speed),
		"switch/scope cannot clear tagging"
	)
	brain.call("_switch_to_weapon", "pistol")
	_check(not actor.ai_scoped, "switch cancels scope")
	actor.reset_actor()
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(1.0), 1.0),
		"respawn clears old damage state"
	)
	_check(
		not actor.ai_scoped and not actor.ai_walking and not actor.ai_crouching,
		"respawn clears stance/scope"
	)
	# Real combat transition activates sniper scope, then freeze/disable cancels it.
	brain.call("configure", {"weapon": "sniper", "aiEnabled": true, "aiCombatEnabled": true})
	var enemy = ActorScene.instantiate()
	enemy.team = "T"
	enemy.position = Vector3(0, 0, -12)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	brain.set("_target", enemy)
	brain.call("_tick_engage", 1.0 / 60.0)
	_check(actor.ai_scoped, "actual sniper combat transition enters scope")
	brain.call("tick", 1.0 / 60.0)
	_check(not actor.ai_scoped, "freeze leaves combat scope")
	actor.set_ai_scoped(true)
	brain.call("set_ai_combat_enabled", false)
	_check(not actor.ai_scoped, "combat disable cancels scope immediately")
	actor.set_ai_scoped(true)
	brain.set("enabled", false)
	brain.call("tick", 1.0 / 60.0)
	_check(not actor.ai_scoped, "disabled brain cannot retain scope")
	actor.set("_ai_tagging_multiplier", 0.48)
	var water := Area3D.new()
	world.add_child(water)
	actor.set("_current_water", water)
	actor.set("_water_depth", 1.3)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(1.0), 0.48 * 0.52),
		"deep water and tagging apply once after navigation cap"
	)
	actor.set("_water_depth", 0.5)
	_check(
		is_equal_approx(actor.resolve_ai_navigation_speed(1.0), 0.48 * 0.72),
		"shallow water uses same Player default"
	)
	actor.set("_current_water", null)
	actor.set("_water_depth", 0.0)
	actor.reset_actor()
	# An authored quiet edge reaches the actual actor without treating precise as quiet.
	brain.call(
		"configure",
		{
			"aiEnabled": true,
			"aiCombatEnabled": false,
			"weapon": "rifle",
			"navigationGraph":
			{
				"points": [[0, 0, 0], [0, 0, -5]],
				"links": [{"from": 0, "to": 1, "quiet": true, "precise": true}]
			}
		}
	)
	brain.set("_active_navigation_link", {"quiet": true, "precise": true})
	brain.call("_move_toward", Vector3(0, 0, -5), 1.0)
	_check(actor.ai_walking, "quiet navigation reaches walking state")
	_check(
		(
			actor.get_ai_movement_snapshot().navigation_speed
			<= actor.resolve_ai_navigation_speed(20.0)
		),
		"navigation target remains capped"
	)
	# A real quiet-edge -> combat transition must release walking even when the
	# strafe/pursuit branch never calls _stop(). Cover both scoped AWP and knife.
	for scheme in ["modern_cs", "current"]:
		actor.movement_scheme = scheme
		var weapon := "sniper" if scheme == "modern_cs" else "knife"
		(
			brain
			. call(
				"configure",
				{
					"aiEnabled": true,
					"aiCombatEnabled": true,
					"weapon": weapon,
					"aiHasKnife": weapon == "knife",
					"aiCrouchChance": 0.0,
					"navigationGraph":
					{
						"points": [[0, 0, 0], [0, 0, -5]],
						"links":
						[{"from": 0, "to": 1, "quiet": true, "precise": true, "crouch": true}]
					},
				}
			)
		)
		brain.call("_move_toward", Vector3(0, 0, -5), 1.0)
		_check(actor.ai_walking, "combat regression begins on an actual quiet edge")
		_check(actor.ai_crouching, "combat regression begins on a crouch edge")
		brain.set("_target", enemy)
		brain.set("_dodge_active", 0.4)
		brain.set("_dodge_direction", Vector3.RIGHT)
		brain.set("_crouch_timer", 10.0)
		brain.call("_tick_engage", 1.0 / 60.0)
		_check(not actor.ai_walking, "combat movement cannot retain a quiet navigation edge")
		_check(not actor.ai_crouching, "combat movement releases navigation crouch before moving")
		var snapshot: Dictionary = actor.get_ai_movement_snapshot()
		if scheme == "modern_cs":
			_check(actor.ai_scoped, "AWP combat regression uses actual scoped state")
			_check(
				is_equal_approx(snapshot.navigation_speed, 2.54),
				"Modern scoped strafe must not retain 0.52 quiet factor"
			)
		else:
			_check(
				is_equal_approx(snapshot.navigation_speed, 5.4 * 0.7),
				"Current knife pursuit must not retain quiet walking cap"
			)
		brain.set("_crouch_active", 0.4)
		brain.call("_tick_engage", 1.0 / 60.0)
		_check(actor.ai_crouching, "explicit combat crouch remains authorized")
		_check(
			(
				actor.get_ai_movement_snapshot().navigation_speed
				<= actor.resolve_ai_navigation_speed(20.0)
			),
			"combat crouch applies before movement in strafe and pursuit"
		)
	world.queue_free()
	await owner.get_tree().process_frame
