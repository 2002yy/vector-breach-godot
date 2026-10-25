extends RefCounted


static func run(host: Node) -> void:
	for kind in ["open", "authored", "precise", "crouch"]:
		var fixture: Dictionary = await host._make_fixture()
		fixture.player.position.x = 12
		var actor: CharacterBody3D = fixture.actor
		var record := {"team": "T", "aiEnabled": true, "aiCombatEnabled": false}
		if kind == "authored":
			record["aiMoveSpeed"] = 2.0
		if kind in ["precise", "crouch"]:
			record["navigationGraph"] = {
				"points": [[0, 1.15, 6], [0, 1.15, -12]],
				"links": [{"from": 0, "to": 1, "precise": true, "crouch": kind == "crouch"}]
			}
		actor.call("configure_from_record", record)
		var brain: Node = actor.get_node("TacticalBotBrain")
		brain.call("configure_objective", "support", Vector3(0, 1.15, -12))
		RoundManager.set_live()
		var initial := actor.global_position
		var peak := 0.0
		for frame in range(120 if kind in ["open", "authored"] else 60):
			await host.get_tree().physics_frame
			peak = maxf(peak, Vector2(actor.velocity.x, actor.velocity.z).length())
		if kind == "open":
			var traveled := initial.distance_to(actor.global_position)
			host._assert_true(
				traveled > 9.5 and traveled < 11.0, "open route advances at useful running pace"
			)
			host._assert_true(peak <= 6.2, "bot stays below player run limit")
		elif kind == "authored":
			host._assert_true(
				peak > 1.9 and peak <= 2.01, "explicit slow authored speed is preserved"
			)
		elif kind == "precise":
			host._assert_true(
				peak > 3.8 and peak <= 4.01, "precise arrival permits controlled route progress"
			)
		else:
			host._assert_true(
				peak > 2.0 and peak <= 2.21, "crouch link does not inherit faster open run"
			)
			host._assert_true(actor.get("ai_crouching"), "crouch semantics still applied")
		await host._cleanup_fixture(fixture)
	var fixture: Dictionary = await host._make_fixture()
	var actor: CharacterBody3D = fixture.actor
	var brain: Node = actor.get_node("TacticalBotBrain")
	brain.get("_rng").seed = 4139
	actor.call(
		"configure_from_record",
		{
			"team": "CT",
			"aiEnabled": true,
			"aiReactionTime": 0.05,
			"aiAimAcquisitionTime": 0.05,
			"aiDamage": 1,
			"aiCrouchChance": 0.0
		}
	)
	GameState.player_health = 100000
	RoundManager.set_live()
	var reversals := 0
	var previous_side := 0.0
	var peak := 0.0
	for frame in range(480):
		await host.get_tree().physics_frame
		peak = maxf(peak, Vector2(actor.velocity.x, actor.velocity.z).length())
		if absf(actor.velocity.x) > 0.42:
			var side := signf(actor.velocity.x)
			if previous_side != 0.0 and previous_side != side:
				reversals += 1
			previous_side = side
	var ai: Dictionary = brain.call("get_snapshot")
	host._assert_true(
		int(ai.dodges) >= 2 and int(ai.dodges) <= 5,
		"occasional dodge remains without constant shuffle"
	)
	host._assert_true(reversals <= 4, "side reversals are bounded during stationary duel")
	host._assert_true(peak <= 2.61, "faster route speed cannot amplify combat dodge speed")
	host._assert_true(int(ai.shots) > 0, "calmer motion does not disable firing")
	await host._cleanup_fixture(fixture)
