extends RefCounted


class FailedLevel:
	extends "res://scripts/level/GrayboxLevel.gd"

	func load_level(next_level_id: String, _emit_errors: bool = true) -> bool:
		load_count += 1
		last_load_timings = {"id": next_level_id, "success": false}
		return false

	func load_level_async(next_level_id: String, emit_errors: bool = true) -> bool:
		return load_level(next_level_id, emit_errors)


static func run(host: Node) -> void:
	var main: Node = host.call("_instantiate_main", false)
	await host.call("_await_main_ready")
	var level := main.get_node("Level")
	var menu := main.get_node("StartMenu")
	var phases: Array[String] = []
	var observe := func(stage: String, _completed: int, _total: int) -> void: phases.append(stage)
	level.load_progress.connect(observe)
	main.get_node("CombatSandbox").load_progress.connect(observe)
	var reads_before: int = host.get_node("/root/SceneReader").submitted_count
	var player := main.get_node("Player")
	var at: Vector3 = player.global_position
	for id in ["training-range", "foundry-reforged", "gatehouse", "training-range", "gatehouse"]:
		main.call("_on_map_selected", main.call("find_level_option_index", id))
		host.call("_assert_equal", level.load_count, 0, "selecting cards must not load geometry")
		host.call(
			"_assert_equal",
			level.get_node("GeometryRoot").get_child_count(),
			0,
			"no preview collision"
		)
		host.call(
			"_assert_equal", level.get_node("VisualRoot").get_child_count(), 0, "no preview GLB"
		)
		host.call(
			"_assert_true", not player.is_physics_processing(), "unloaded-menu player cannot fall"
		)
		host.call("_assert_equal", player.global_position, at, "selection cannot move player")
	host.call(
		"_assert_equal",
		host.get_node("/root/SceneReader").submitted_count,
		reads_before,
		"cards cannot submit background reads"
	)
	menu.show_loading_error("layout")
	host.call(
		"_assert_true", menu.loading_status.detail.text.contains("对局数据"), "specific layout guidance"
	)
	main.call("_on_start_pressed")
	main.call("_on_start_pressed")
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	host.call("_assert_true", main._starting, "start is pending while loading frame is painted")
	host.call("_assert_equal", level.load_count, 0, "loading UI is shown before engine work")
	host.call(
		"_assert_equal", menu.loading_status.stage, "map", "retry clears old error immediately"
	)
	var partial_frames := 0
	while main._starting:
		if main._level_loading:
			host.call("_assert_true", not main.game_started, "loading world is not a live match")
			host.call(
				"_assert_equal",
				RoundManager.state,
				RoundManager.RoundState.WARMUP,
				"loading cannot advance the old round timer"
			)
		var sandbox := main.get_node("CombatSandbox")
		if sandbox.get_child_count() > 0 and sandbox.last_load_timings.actor_count == 0:
			partial_frames += 1
			host.call("_assert_true", not main.game_started, "partial roster cannot start match")
			for actor in sandbox.get_children():
				host.call(
					"_assert_equal",
					actor.process_mode,
					Node.PROCESS_MODE_DISABLED,
					"partial roster must not run AI or animation"
				)
		await host.get_tree().process_frame
	host.call("_assert_true", partial_frames > 1, "roster construction spans presented frames")
	host.call("_assert_equal", level.load_count, 1, "double start loads only once")
	host.call(
		"_assert_equal",
		level.get_current_level_data().id,
		"gatehouse",
		"pending start cannot change maps"
	)
	host.call(
		"_assert_true",
		main.game_started and main.last_start_timings.success,
		"match becomes playable"
	)
	host.call("_assert_true", main.last_start_timings.total_ms >= 0, "start duration measured")
	for phase in ["scene", "visual", "team"]:
		host.call("_assert_true", phase in phases, "real workflow reports " + phase)
	host.call("_assert_equal", menu.loading_status.state, "idle", "success clears progress")
	main.call("_on_loading_progress", "team", 1, 9)
	host.call("_assert_equal", menu.loading_status.state, "idle", "late progress stays hidden")
	var actors: Dictionary = main.last_start_timings.preparation.actor_phases
	host.call(
		"_assert_true",
		actors.has("detach_ms") and actors.deferred_free_excluded,
		"actor timing explicitly excludes deferred resource destruction"
	)
	host.call("_assert_equal", actors.id, "gatehouse", "actor phases belong to actual loaded map")
	host.call("_assert_true", actors.staged, "explicit start selects staged construction")
	host.call("_assert_equal", actors.yielded_frames, actors.actor_count, "one yield per actor")
	host.call(
		"_assert_equal", actors.navigation_prepare_count, 1, "topology prepares once per roster"
	)
	var roster_count := 0
	for actor in main.get_node("CombatSandbox").get_children():
		if actor is CharacterBody3D:
			roster_count += 1
			host.call(
				"_assert_true",
				actor.get("bot_brain").get("_navigation").points.is_read_only(),
				"real actors consume prepared topology"
			)
			host.call("_assert_true", actor.can_process(), "complete roster reactivates together")
	host.call(
		"_assert_equal", actors.actor_count, roster_count, "actor receipt matches actual roster"
	)
	host.call(
		"_assert_true",
		actors.total_ms >= actors.spawn_configure_ms,
		"actor total includes configuration"
	)
	main.call("_open_menu", false)
	main.call("_return_to_map_selection")
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	host.call("_assert_equal", level.load_count, 1, "return and reselect do not reload")
	await main.call("_on_start_pressed")
	host.call("_assert_equal", level.load_count, 2, "next start loads the final selection once")
	host.call(
		"_assert_equal",
		level.get_current_level_data().id,
		"training-range",
		"new map actually loaded"
	)
	await host.call("_cleanup_main", main)
	await _replacement(host)
	await _failure(host)


static func _failure(host: Node) -> void:
	var main: Node = host.call("_instantiate_main", false)
	await host.call("_await_main_ready")
	main.get_node("Level").set_script(FailedLevel)
	var failed: Array = []
	var selected: String = main.level_options[main.selected_level_index].id
	main.level_start_failed.connect(func(id: String): failed.append(id))
	await main.call("_on_start_pressed")
	host.call("_assert_equal", failed, [selected], "failed Start publishes one lifecycle failure")
	host.call(
		"_assert_true",
		not main._starting and not main._level_loading,
		"failure releases loading state"
	)
	host.call(
		"_assert_true",
		not main.game_started and not main.last_start_timings.success,
		"failure cannot enter old world"
	)
	host.call(
		"_assert_true",
		main.menu_open and not GameState.match_active,
		"failure returns to inactive menu"
	)
	host.call(
		"_assert_true", not main.get_node("StartMenu").start_button.disabled, "failure allows retry"
	)
	var menu := main.get_node("StartMenu")
	host.call("_assert_equal", menu.loading_status.state, "failed", "failure remains visible")
	host.call(
		"_assert_true", menu.loading_status.detail.text.contains("完整"), "failure offers recovery"
	)
	host.call("_assert_equal", menu.start_button.text, "重试对局", "action is explicit")
	await main.call("_on_start_pressed")
	host.call("_assert_equal", failed.size(), 2, "retry runs a fresh attempt")
	host.call("_assert_true", not menu.start_button.disabled, "repeated failure remains retryable")
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	host.call(
		"_assert_equal", menu.loading_status.state, "idle", "new selection clears old failure"
	)
	await host.call("_cleanup_main", main)


static func _replacement(host: Node) -> void:
	var main: Node = host.call("_instantiate_main", false)
	await host.call("_await_main_ready")
	var sandbox := main.get_node("CombatSandbox")
	var Loader = preload("res://scripts/level/LevelDataLoader.gd")
	var completed: Array = []
	sandbox.combatants_spawned.connect(func(_friendly: int, _enemy: int): completed.append(true))
	sandbox.call("load_for_level", Loader.load_level("gatehouse"), true)
	host.call("_assert_equal", sandbox.get_child_count(), 1, "staged load yields after first actor")
	sandbox.call("load_for_level", Loader.load_level("training-range"))
	var replacement_count := sandbox.get_child_count()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	host.call("_assert_equal", completed.size(), 1, "cancelled roster cannot publish completion")
	host.call(
		"_assert_equal",
		sandbox.get_child_count(),
		replacement_count,
		"old load cannot append actors"
	)
	host.call(
		"_assert_equal",
		sandbox.last_load_timings.id,
		"training-range",
		"new receipt survives old resume"
	)
	host.call(
		"_assert_true",
		not sandbox.last_load_timings.staged,
		"round and direct paths stay synchronous"
	)
	await host.call("_cleanup_main", main)
