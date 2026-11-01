extends RefCounted


static func run(host: Node) -> void:
	for kind in ["plant", "defuse"]:
		var fixture: Dictionary = await host.call("_make_fixture")
		RoundManager.cancel_objective_interaction()
		RoundManager.set_live()
		RoundManager.bomb_carried = true
		var team := "T" if kind == "plant" else "CT"
		if kind == "defuse":
			RoundManager.plant_bomb("A")
		var first: CharacterBody3D = host.call(
			"_make_actor", fixture.world, "原交互者", team, Vector3(0, 1, 0)
		)
		var next: CharacterBody3D = host.call(
			"_make_actor", fixture.world, "接替者", team, Vector3(0, 1, 0)
		)
		var old_brain := first.get_node("TacticalBotBrain")
		var new_brain := next.get_node("TacticalBotBrain")
		new_brain.set("has_defuse_kit", true)
		if kind == "plant":
			fixture.c4.call("set_carried", "T", first.get_instance_id())
		else:
			fixture.c4.call("plant_at", Vector3.ZERO, "A")
		for brain in [old_brain, new_brain]:
			brain.call("set_c4_device", fixture.c4)
			brain.call("configure_objective", kind, Vector3(0, 1, 0), "A", true)
		old_brain.call("_begin_" + kind)
		old_brain.call("_tick_bomb_interaction", 0.5)
		host.call("_assert_true", RoundManager.interaction_elapsed > 0.0, "interaction started")
		new_brain.call("_begin_" + kind)
		host.call(
			"_assert_true", not new_brain.get("_bomb_interacting"), "live owner cannot be stolen"
		)
		first.call(
			"apply_hitscan_damage",
			1000,
			Vector3.UP,
			1.0,
			false,
			"CT" if team == "T" else "T",
			Vector3.ZERO
		)
		host.call("_assert_true", first.get("is_dead"), "actual damage kills interaction actor")
		if kind == "plant":
			fixture.c4.call("set_carried", "T", next.get_instance_id())
		new_brain.call("_begin_" + kind)
		host.call("_assert_true", new_brain.get("_bomb_interacting"), "survivor can take over")
		host.call("_assert_equal", RoundManager.interaction_elapsed, 0.0, "handoff resets progress")
		if kind == "defuse":
			host.call(
				"_assert_equal", RoundManager.interaction_duration, 5.0, "replacement uses own kit"
			)
		RoundManager.cancel_objective_interaction(first)
		host.call(
			"_assert_true", RoundManager.is_objective_interacting(), "old owner cannot cancel new"
		)
		old_brain.call("_tick_bomb_interaction", 0.2)
		host.call("_assert_equal", RoundManager.interaction_elapsed, 0.0, "stale owner cannot tick")
		new_brain.call("_tick_bomb_interaction", 0.2)
		host.call("_assert_true", RoundManager.interaction_elapsed > 0.0, "new owner can progress")
		var progress := RoundManager.interaction_elapsed
		RoundManager.set_paused_menu()
		RoundManager._process(1.0)
		host.call(
			"_assert_equal", RoundManager.interaction_elapsed, progress, "pause preserves progress"
		)
		RoundManager.resume_round()
		if kind == "plant":
			fixture.c4.call("drop_at", Vector3.ZERO)
			host.call(
				"_assert_true", not RoundManager.is_objective_interacting(), "drop releases plant"
			)
			fixture.c4.call("set_carried", "T", next.get_instance_id())
			new_brain.call("_begin_plant")
		RoundManager.end_round("CT", "fixture")
		host.call(
			"_assert_true", not RoundManager.is_objective_interacting(), "round end clears owner"
		)
		RoundManager.set_live()
		RoundManager.bomb_carried = true
		if kind == "defuse":
			RoundManager.plant_bomb("A")
		new_brain.call("_begin_" + kind)
		next.free()
		RoundManager._process(0.0)
		host.call(
			"_assert_true", not RoundManager.is_objective_interacting(), "freed owner releases"
		)
		RoundManager.cancel_objective_interaction()
		await host.call("_cleanup_fixture", fixture)
